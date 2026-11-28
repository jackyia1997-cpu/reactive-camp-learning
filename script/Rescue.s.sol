// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// 钱包救援演示的部署脚本。签名用 `--account camp`（Foundry 加密 keystore）。
// 推荐用 `bash go.sh rescue` 一键跑。

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { PracticeToken } from "../src/rescue/PracticeToken.sol";
import { GuardReactive } from "../src/rescue/GuardReactive.sol";
import { RescueGuardian } from "../src/rescue/RescueGuardian.sol";

/// R1 Sepolia：发 1000 PRAC 练习币给自己（受保护地址 = 部署者）
contract DeployToken is Script {
    function run() external {
        vm.startBroadcast();
        PracticeToken t = new PracticeToken(1000 ether);
        vm.stopBroadcast();
        console.log("TOKEN_ADDR=%s", address(t));
    }
}

/// R2 Lasna：部署哨兵，只听「PRAC 从我地址转出」
contract DeployGuard is Script {
    function run() external {
        uint256 chain = vm.envOr("ORIGIN_CHAIN_ID", uint256(11155111));
        address token = vm.envAddress("TOKEN_ADDR");
        address protectedAddr = vm.envAddress("ME");
        address safe = vm.envAddress("SAFE_ADDR");
        uint256 threshold = vm.envOr("RESCUE_THRESHOLD", uint256(100 ether)); // 单笔转出 >= 100 PRAC 视为异常
        uint256 limit = vm.envOr("RESCUE_LIMIT", uint256(3));
        uint256 fund = vm.envOr("REACTIVE_FUND", uint256(0.3 ether));

        vm.startBroadcast();
        GuardReactive g = new GuardReactive{ value: fund }(chain, token, protectedAddr, safe, chain, threshold, limit);
        vm.stopBroadcast();
        console.log("GUARD_ADDR=%s", address(g));
    }
}

/// R3 Sepolia：部署搬运工 + 给它 approve 限额（同一脚本两笔交易）
contract DeployGuardian is Script {
    function run() external {
        address proxy = vm.envOr("CALLBACK_PROXY", address(0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4));
        address guard = vm.envAddress("GUARD_ADDR");
        address token = vm.envAddress("TOKEN_ADDR");
        address protectedAddr = vm.envAddress("ME");
        address safe = vm.envAddress("SAFE_ADDR");
        uint256 maxPer = vm.envOr("MAX_PER_RESCUE", uint256(1000 ether));
        uint256 maxTotal = vm.envOr("MAX_TOTAL", uint256(1000 ether));
        uint256 allowanceCap = vm.envOr("APPROVE_AMOUNT", uint256(1000 ether));
        uint256 fund = vm.envOr("CALLBACK_FUND", uint256(0.005 ether));

        vm.startBroadcast();
        RescueGuardian gd = new RescueGuardian{ value: fund }(
            IPayable(payable(proxy)), guard, token, protectedAddr, safe, maxPer, maxTotal
        );
        PracticeToken(token).approve(address(gd), allowanceCap);
        vm.stopBroadcast();
        console.log("GUARDIAN_ADDR=%s", address(gd));
    }
}

/// R4 Lasna：把搬运工地址告诉哨兵
contract SetGuardian is Script {
    function run() external {
        vm.startBroadcast();
        GuardReactive(payable(vm.envAddress("GUARD_ADDR"))).setGuardian(vm.envAddress("GUARDIAN_ADDR"));
        vm.stopBroadcast();
        console.log("guardian set");
    }
}

/// R5 Sepolia：假装被盗——从受保护地址转 300 PRAC 给「攻击者」（默认 0x…dEaD 黑洞地址）
contract FakeTheft is Script {
    function run() external {
        address thief = vm.envOr("THIEF_ADDR", address(0x000000000000000000000000000000000000dEaD));
        uint256 amount = vm.envOr("THEFT_AMOUNT", uint256(300 ether));
        vm.startBroadcast();
        PracticeToken(vm.envAddress("TOKEN_ADDR")).transfer(thief, amount);
        vm.stopBroadcast();
        console.log("stolen %s PRAC-wei to %s", amount, thief);
    }
}
