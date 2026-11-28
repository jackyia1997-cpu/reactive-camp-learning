// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title GuardReactive — 钱包守护的「哨兵」（部署在 Reactive Lasna）
/// @notice 只听一件事：Sepolia 上 PRAC 代币「从受保护地址转出」的 Transfer。
///         转出数量 >= 阈值、收款方不是安全地址 → 请 Sepolia 上的 RescueGuardian 把剩余币搬到安全地址。
/// @dev    防误触发：订阅层就只听 topic1 = 受保护地址；转给安全地址（救援本身）一律忽略。
///         防重复：同一笔 (chainId, txHash, logIndex) 只处理一次。
///         防烧钱：最多处理 remaining 次，用完自动退订；可随时 pause。不满足条件用 return，不用 revert（revert 也收费）。
contract GuardReactive is AbstractReactive {
    error NotOwner();
    error ZeroAddress();

    /// keccak256("Transfer(address,address,uint256)")
    uint256 public constant TRANSFER_TOPIC_0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;

    address public immutable OWNER;
    uint256 public immutable ORIGIN_CHAIN_ID;
    address public immutable TOKEN;
    address public immutable PROTECTED;
    address public immutable SAFE;
    uint256 public immutable DEST_CHAIN_ID;

    address public guardian;
    uint256 public threshold;
    uint256 public remaining;
    bool public paused;
    bool public alertOnly;

    mapping(bytes32 => bool) public seen;
    mapping(address => bool) public trustedRecipients;
    uint256 public lastTxHash;
    uint256 public lastReactBlock;

    event Seen(uint256 indexed originTxHash, address indexed to, uint256 amount);
    event RescueRequested(uint256 indexed originTxHash, uint256 logIndex, uint256 amount);

    event RiskAlert(uint256 indexed originTxHash, address indexed recipient, uint256 logIndex, uint256 amount);
    event AlertModeUpdated(bool alertOnly);
    event TrustedRecipientUpdated(address indexed recipient, bool trusted);

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert NotOwner();
        _;
    }

    constructor(
        uint256 originChainId_,
        address token_,
        address protected_,
        address safe_,
        uint256 destChainId_,
        uint256 threshold_,
        uint256 limit_
    ) payable {
        if (token_ == address(0) || protected_ == address(0) || safe_ == address(0)) revert ZeroAddress();
        OWNER = msg.sender;
        ORIGIN_CHAIN_ID = originChainId_;
        TOKEN = token_;
        PROTECTED = protected_;
        SAFE = safe_;
        DEST_CHAIN_ID = destChainId_;
        threshold = threshold_;
        remaining = limit_;
        // 只订阅「这个代币、Transfer、from = 受保护地址」
        SYSTEM.subscribe(originChainId_, token_, TRANSFER_TOPIC_0, uint256(uint160(protected_)), REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    function setGuardian(address guardian_) external onlyOwner {
        if (guardian_ == address(0)) revert ZeroAddress();
        guardian = guardian_;
    }

    function setThreshold(uint256 threshold_) external onlyOwner {
        threshold = threshold_;
    }

    function setTrustedRecipient(address recipient_, bool trusted_) external onlyOwner {
        if (recipient_ == address(0)) revert ZeroAddress();
        trustedRecipients[recipient_] = trusted_;
        emit TrustedRecipientUpdated(recipient_, trusted_);
    }

    function setAlertOnly(bool enabled_) external onlyOwner {
        alertOnly = enabled_;
        emit AlertModeUpdated(enabled_);
    }

    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
    }

    /// @notice 充值 lREACT 并重设剩余次数
    function topUp(uint256 limit_) external payable onlyOwner {
        remaining = limit_;
    }

    function react(LogRecord calldata log_) external onlySystem {
        if (paused || remaining == 0 || guardian == address(0)) return;
        // Transfer 有 3 个 topic → LOG3 → opCode 3
        if (log_.opCode != 3 || log_.topic0 != TRANSFER_TOPIC_0) return;
        if (log_.chainId != ORIGIN_CHAIN_ID || log_.contractAddress != TOKEN) return;
        if (address(uint160(log_.topic1)) != PROTECTED) return;

        address to = address(uint160(log_.topic2));
        uint256 amount = log_.data.length >= 32 ? abi.decode(log_.data, (uint256)) : 0;

        lastTxHash = log_.txHash;
        lastReactBlock = block.number;
        emit Seen(log_.txHash, to, amount);

        if (to == SAFE || trustedRecipients[to]) return; // 保险箱与常用收款地址跳过救援
        if (amount < threshold) return;

        bytes32 key = keccak256(abi.encode(log_.chainId, log_.txHash, log_.logIndex));
        if (seen[key]) return;
        seen[key] = true;

        if (alertOnly) {
            emit RiskAlert(log_.txHash, to, log_.logIndex, amount);
            return;
        }

        remaining -= 1;
        if (remaining == 0) {
            SYSTEM.unsubscribe(ORIGIN_CHAIN_ID, TOKEN, TRANSFER_TOPIC_0, uint256(uint160(PROTECTED)), REACTIVE_IGNORE, REACTIVE_IGNORE);
        }

        emit RescueRequested(log_.txHash, log_.logIndex, amount);
        // 第一个参数 address(0) 是占位，Callback Proxy 会替换成本合约地址
        bytes memory payload = abi.encodeWithSignature(
            "rescue(address,uint256,uint256)", address(0), log_.txHash, log_.logIndex
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: DEST_CHAIN_ID,
                recipient: guardian,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }
}
