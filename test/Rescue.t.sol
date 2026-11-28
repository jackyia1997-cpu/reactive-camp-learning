// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { MockSystem, MockProxy } from "./Camp.t.sol";
import { PracticeToken } from "../src/rescue/PracticeToken.sol";
import { GuardReactive } from "../src/rescue/GuardReactive.sol";
import { RescueGuardian } from "../src/rescue/RescueGuardian.sol";

/// @dev 本地跑通「被盗转出 → Lasna 判断 → Sepolia 救援」整条链路。
///      源链事件用 vm.recordLogs 抓真实的 Transfer 日志，再原样喂给 react()，和链上 Reactive 网络投递的结构一致。
contract RescueTest is Test {
    uint256 constant CHAIN = 11155111;
    uint256 constant THRESHOLD = 100 ether; // 100 PRAC
    uint256 constant LIMIT = 3;

    MockSystem system;
    MockProxy proxy;
    PracticeToken token;
    GuardReactive guard;
    RescueGuardian guardian;

    address protectedAddr = makeAddr("protected");
    address safeAddr = makeAddr("safe");
    address attacker = makeAddr("attacker");

    function setUp() public {
        MockSystem impl = new MockSystem();
        vm.etch(0x8888888888888888888888888888888888888888, address(impl).code);
        system = MockSystem(payable(0x8888888888888888888888888888888888888888));
        proxy = new MockProxy();

        vm.prank(protectedAddr);
        token = new PracticeToken(1000 ether);

        guard = new GuardReactive{ value: 1 ether }(CHAIN, address(token), protectedAddr, safeAddr, CHAIN, THRESHOLD, LIMIT);
        guardian = _newGuardian(1000 ether, 1000 ether);
        guard.setGuardian(address(guardian));

        vm.prank(protectedAddr);
        token.approve(address(guardian), 1000 ether);
    }

    function _newGuardian(uint256 maxPer, uint256 maxTotal) internal returns (RescueGuardian) {
        return new RescueGuardian{ value: 0.1 ether }(
            IPayable(payable(address(proxy))), address(guard), address(token), protectedAddr, safeAddr, maxPer, maxTotal
        );
    }

    /// 让 from 真的转一笔，抓到它的 Transfer 日志，转成 Reactive 的 LogRecord
    function _transferAndCapture(address from, address to, uint256 amount, uint256 txHash)
        internal
        returns (IReactive.LogRecord memory l)
    {
        vm.recordLogs();
        vm.prank(from);
        token.transfer(to, amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        l.chainId = CHAIN;
        l.contractAddress = logs[0].emitter;
        l.topic0 = uint256(logs[0].topics[0]);
        l.topic1 = uint256(logs[0].topics[1]);
        l.topic2 = uint256(logs[0].topics[2]);
        l.data = logs[0].data;
        l.opCode = 3;
        l.txHash = txHash;
        l.logIndex = 0;
        l.blockNumber = block.number;
    }

    function _react(IReactive.LogRecord memory l) internal {
        vm.prank(address(system));
        guard.react(l);
    }

    function _deliverLast() internal returns (bool ok) {
        ISystemContract.CallbackConfiguration_V_1_0 memory r = system.lastRequest();
        (ok,) = proxy.deliver(r.recipient, address(guard), r.payload);
    }

    function test_subscribesOnlyProtectedOutflow() public view {
        (uint256 c, address a, uint256 t0) = system.subs(0);
        assertEq(c, CHAIN);
        assertEq(a, address(token));
        assertEq(t0, guard.TRANSFER_TOPIC_0());
        assertEq(t0, uint256(keccak256("Transfer(address,address,uint256)")));
    }

    function test_fullLoop_theftTriggersRescue() public {
        IReactive.LogRecord memory l = _transferAndCapture(protectedAddr, attacker, 300 ether, 0xabc);
        _react(l);
        assertEq(system.requestCount(), 1);
        ISystemContract.CallbackConfiguration_V_1_0 memory r = system.lastRequest();
        assertEq(r.chainId, CHAIN);
        assertEq(r.recipient, address(guardian));

        assertTrue(_deliverLast());
        assertEq(token.balanceOf(attacker), 300 ether); // 已被偷走的救不回
        assertEq(token.balanceOf(safeAddr), 700 ether); // 剩下的全部搬走
        assertEq(token.balanceOf(protectedAddr), 0);
        assertEq(guardian.totalRescued(), 700 ether);
    }

    function test_belowThresholdIgnored() public {
        _react(_transferAndCapture(protectedAddr, attacker, 99 ether, 1));
        assertEq(system.requestCount(), 0);
        assertEq(guard.lastTxHash(), 1); // 看到了，但没求救
    }

    function test_transferToSafeIgnored_noLoop() public {
        // 救援本身就是 protected → safe 的 Transfer，不能再触发
        _react(_transferAndCapture(protectedAddr, safeAddr, 500 ether, 2));
        assertEq(system.requestCount(), 0);
    }

    function test_trustedRecipientCanBeAddedAndRemoved() public {
        guard.setTrustedRecipient(attacker, true);
        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 25));
        assertEq(system.requestCount(), 0);
        assertEq(guard.remaining(), LIMIT);

        guard.setTrustedRecipient(attacker, false);
        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 26));
        assertEq(system.requestCount(), 1);
    }

    function test_trustedRecipientChangeRequiresOwner() public {
        vm.prank(attacker);
        vm.expectRevert(GuardReactive.NotOwner.selector);
        guard.setTrustedRecipient(attacker, true);
    }

    event RiskAlert(uint256 indexed originTxHash, address indexed recipient, uint256 logIndex, uint256 amount);

    function test_alertOnlyRecordsAnEventWithoutMovingFunds() public {
        guard.setAlertOnly(true);
        IReactive.LogRecord memory event_ = _transferAndCapture(protectedAddr, attacker, 300 ether, 31);
        vm.expectEmit(true, true, false, true, address(guard));
        emit RiskAlert(31, attacker, 0, 300 ether);
        _react(event_);
        assertEq(system.requestCount(), 0);
        assertEq(guard.remaining(), LIMIT);
        assertEq(token.balanceOf(protectedAddr), 700 ether);
        assertEq(token.balanceOf(safeAddr), 0);
        guard.setAlertOnly(false);
        _react(event_);
        assertEq(system.requestCount(), 0);
        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 32));
        assertEq(system.requestCount(), 1);
    }

    function test_alertOnlySkipsTrustedRecipientsAndSmallTransfers() public {
        guard.setAlertOnly(true);
        guard.setTrustedRecipient(attacker, true);
        IReactive.LogRecord memory trustedLog = _transferAndCapture(protectedAddr, attacker, 100 ether, 33);
        IReactive.LogRecord memory smallLog = _transferAndCapture(protectedAddr, makeAddr("untrusted"), 99 ether, 34);
        vm.recordLogs();
        _react(trustedLog);
        _react(smallLog);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], keccak256("RiskAlert(uint256,address,uint256,uint256)"));
        }
    }

    function test_alertModeChangeRequiresOwner() public {
        vm.prank(attacker);
        vm.expectRevert(GuardReactive.NotOwner.selector);
        guard.setAlertOnly(true);
    }

    function test_sameEventTwice_onlyOneCallback() public {
        IReactive.LogRecord memory l = _transferAndCapture(protectedAddr, attacker, 300 ether, 3);
        _react(l);
        _react(l);
        assertEq(system.requestCount(), 1);
        assertEq(guard.remaining(), LIMIT - 1);
    }

    function test_guardianDedup_secondDeliveryMovesNothing() public {
        _react(_transferAndCapture(protectedAddr, attacker, 300 ether, 4));
        assertTrue(_deliverLast());
        // 给 protected 再塞点币，重复投递同一个回调也不能再搬
        vm.prank(safeAddr);
        token.transfer(protectedAddr, 100 ether);
        assertTrue(_deliverLast());
        assertEq(token.balanceOf(protectedAddr), 100 ether);
        assertEq(guardian.rescueCount(), 1);
    }

    function test_perRescueAndTotalCaps() public {
        guard = new GuardReactive{ value: 1 ether }(CHAIN, address(token), protectedAddr, safeAddr, CHAIN, THRESHOLD, LIMIT);
        // 重新部署一对合约后需重新绑定：guardian 的 _CALLBACK_SENDER 要等于新 guard
        guardian = new RescueGuardian{ value: 0.1 ether }(
            IPayable(payable(address(proxy))), address(guard), address(token), protectedAddr, safeAddr, 200 ether, 300 ether
        );
        guard.setGuardian(address(guardian));
        vm.prank(protectedAddr);
        token.approve(address(guardian), type(uint256).max);

        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 10));
        assertTrue(_deliverLast());
        assertEq(token.balanceOf(safeAddr), 200 ether); // 单次上限

        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 11));
        assertTrue(_deliverLast());
        assertEq(token.balanceOf(safeAddr), 300 ether); // 累计上限

        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 12));
        assertTrue(_deliverLast());
        assertEq(token.balanceOf(safeAddr), 300 ether); // 封顶不再搬
    }

    function test_onlyApprovedAmountMoves() public {
        vm.prank(protectedAddr);
        token.approve(address(guardian), 50 ether);
        _react(_transferAndCapture(protectedAddr, attacker, 300 ether, 5));
        assertTrue(_deliverLast());
        assertEq(token.balanceOf(safeAddr), 50 ether);
    }

    function test_guardianRejectsDirectCall() public {
        vm.prank(attacker);
        vm.expectRevert();
        guardian.rescue(address(guard), 1, 0);
    }

    function test_guardianRejectsOtherReactive() public {
        bytes memory payload = abi.encodeWithSignature("rescue(address,uint256,uint256)", address(0), 1, 0);
        (bool ok,) = proxy.deliver(address(guardian), address(0xBEEF), payload);
        assertFalse(ok);
        assertEq(token.balanceOf(safeAddr), 0);
    }

    function test_reactOnlySystem() public {
        IReactive.LogRecord memory l = _transferAndCapture(protectedAddr, attacker, 300 ether, 6);
        vm.expectRevert();
        guard.react(l);
    }

    function test_otherSenderIgnored() public {
        vm.prank(protectedAddr);
        token.transfer(attacker, 500 ether);
        _react(_transferAndCapture(attacker, safeAddr, 500 ether, 7)); // from 不是受保护地址
        assertEq(system.requestCount(), 0);
    }

    function test_pauseAndLimit() public {
        guard.setPaused(true);
        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 20));
        assertEq(system.requestCount(), 0);
        guard.setPaused(false);
        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 21));
        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 22));
        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 23));
        _react(_transferAndCapture(protectedAddr, attacker, 100 ether, 24)); // 次数用完
        assertEq(system.requestCount(), 3);
        assertEq(system.unsubscribeCount(), 1);
    }

    function test_onlyOwnerConfig() public {
        vm.prank(attacker);
        vm.expectRevert(GuardReactive.NotOwner.selector);
        guard.setGuardian(attacker);
    }
}
