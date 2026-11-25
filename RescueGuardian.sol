// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function transferFrom(address, address, uint256) external returns (bool);
}

/// @title RescueGuardian — 钱包守护的「搬运工」（部署在 Sepolia，和代币同一条链）
/// @notice 收到 GuardReactive 的回调后，把受保护地址里「还剩的、已 approve 给本合约的」PRAC 搬到写死的安全地址。
/// @dev    两道门：onlyServiceProvider（必须是 Sepolia Callback Proxy 调的）+ onlyCallbackSender（必须来自指定的 GuardReactive）。
///         去向写死 SAFE，任何人都改不了。单次和累计都有上限；同一事件只救一次。
contract RescueGuardian is AbstractCallback {
    error TransferFromFailed();

    IERC20Like public immutable TOKEN;
    address public immutable PROTECTED;
    address public immutable SAFE;
    uint256 public immutable MAX_PER_RESCUE;
    uint256 public immutable MAX_TOTAL;

    uint256 public totalRescued;
    uint256 public rescueCount;
    mapping(bytes32 => bool) public handled;

    event Rescued(uint256 indexed originTxHash, uint256 logIndex, uint256 amount, uint256 totalRescued);
    event RescueSkipped(uint256 indexed originTxHash, uint256 logIndex, string reason);

    constructor(
        IPayable proxy_,
        address reactive_,
        address token_,
        address protected_,
        address safe_,
        uint256 maxPerRescue_,
        uint256 maxTotal_
    ) payable AbstractCallback(proxy_, reactive_) {
        TOKEN = IERC20Like(token_);
        PROTECTED = protected_;
        SAFE = safe_;
        MAX_PER_RESCUE = maxPerRescue_;
        MAX_TOTAL = maxTotal_;
    }

    function rescue(address reactive_, uint256 originTxHash_, uint256 logIndex_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        bytes32 key = keccak256(abi.encode(originTxHash_, logIndex_));
        if (handled[key]) {
            emit RescueSkipped(originTxHash_, logIndex_, "duplicate");
            return;
        }
        handled[key] = true;

        uint256 amount = _min(TOKEN.balanceOf(PROTECTED), TOKEN.allowance(PROTECTED, address(this)));
        amount = _min(amount, MAX_PER_RESCUE);
        amount = _min(amount, MAX_TOTAL - totalRescued);
        if (amount == 0) {
            emit RescueSkipped(originTxHash_, logIndex_, "nothing to move");
            return;
        }

        totalRescued += amount;
        rescueCount += 1;
        emit Rescued(originTxHash_, logIndex_, amount, totalRescued);
        if (!TOKEN.transferFrom(PROTECTED, SAFE, amount)) revert TransferFromFailed();
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
