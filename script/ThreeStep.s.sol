// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// 改自营地模板 starter/script/Deploy.s.sol（ethpanda-org/reactive-builder-camp）：
// 1) vm.startBroadcast() 不再读 PRIVATE_KEY，签名交给 `--account camp`（Foundry 加密 keystore），私钥不落盘明文；
// 2) 默认预付金额调小，省测试币。合约本身与模板一致。
// 推荐用 `bash go.sh three` 一键跑，不用手敲下面这些命令。

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { CampOrigin } from "../src/CampOrigin.sol";
import { CampReactive } from "../src/CampReactive.sol";
import { CampCallback } from "../src/CampCallback.sol";

/// ① Sepolia：部署事件源
contract DeployOrigin is Script {
    function run() external {
        vm.startBroadcast();
        CampOrigin o = new CampOrigin();
        vm.stopBroadcast();
        console.log("ORIGIN_ADDR=%s", address(o));
    }
}

/// ② Lasna：部署 Reactive 合约（预付 lREACT）
contract DeployReactive is Script {
    function run() external {
        uint256 originChain = vm.envOr("ORIGIN_CHAIN_ID", uint256(11155111));
        uint256 destChain = vm.envOr("DEST_CHAIN_ID", uint256(11155111));
        address originAddr = vm.envAddress("ORIGIN_ADDR");
        uint256 threshold = vm.envOr("THRESHOLD", uint256(100));
        uint256 limit = vm.envOr("LIMIT", uint256(5));
        uint256 fund = vm.envOr("REACTIVE_FUND", uint256(0.3 ether)); // 0.3 lREACT
        uint256 topic0 = uint256(keccak256("Ping(address,uint256)"));

        vm.startBroadcast();
        CampReactive r = new CampReactive{ value: fund }(originChain, originAddr, topic0, destChain, threshold, limit);
        vm.stopBroadcast();
        console.log("REACTIVE_ADDR=%s", address(r));
    }
}

/// ③ Sepolia：部署回调合约（带 ETH 付回调 gas）
contract DeployCallback is Script {
    function run() external {
        address proxy = vm.envOr("CALLBACK_PROXY", address(0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4));
        address reactive = vm.envAddress("REACTIVE_ADDR");
        uint256 fund = vm.envOr("CALLBACK_FUND", uint256(0.005 ether));

        vm.startBroadcast();
        CampCallback c = new CampCallback{ value: fund }(IPayable(payable(proxy)), reactive);
        vm.stopBroadcast();
        console.log("CALLBACK_ADDR=%s", address(c));
    }
}

/// ④ Lasna：把回调合约地址告诉 Reactive 合约
contract SetRecipient is Script {
    function run() external {
        vm.startBroadcast();
        CampReactive(payable(vm.envAddress("REACTIVE_ADDR"))).setRecipient(vm.envAddress("CALLBACK_ADDR"));
        vm.stopBroadcast();
        console.log("recipient set");
    }
}

/// ⑤ Sepolia：触发事件（value >= threshold 才回调）
contract Ping is Script {
    function run() external {
        uint256 value = vm.envOr("PING_VALUE", uint256(500));
        vm.startBroadcast();
        CampOrigin(vm.envAddress("ORIGIN_ADDR")).ping(value);
        vm.stopBroadcast();
        console.log("pinged with value %s", value);
    }
}
