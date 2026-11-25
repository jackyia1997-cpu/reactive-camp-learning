# 跨链回调三步走｜手动版命令（go.sh 出问题时用）

前提：`cast wallet import camp --interactive` 已导入测试钱包；`bash go.sh setup` 已通过。每条 forge 命令都会要 keystore 密码。

```bash
export ME=0x你的测试地址
export SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
export LASNA_RPC_URL=https://lasna-rpc.rnk.dev/
S="--broadcast --account camp --sender $ME"

# ① Sepolia：事件源
forge script script/ThreeStep.s.sol:DeployOrigin   --rpc-url $SEPOLIA_RPC_URL $S
export ORIGIN_ADDR=0x...      # 抄上一步输出的 ORIGIN_ADDR=

# ② Lasna：Reactive 合约（预付 0.3 lREACT）
forge script script/ThreeStep.s.sol:DeployReactive --rpc-url $LASNA_RPC_URL $S
export REACTIVE_ADDR=0x...

# ③ Sepolia：回调合约（带 0.005 ETH 付回调 gas；Proxy 默认 0xAa14…23b4）
forge script script/ThreeStep.s.sol:DeployCallback --rpc-url $SEPOLIA_RPC_URL $S
export CALLBACK_ADDR=0x...

# ④ Lasna：绑定回调地址
forge script script/ThreeStep.s.sol:SetRecipient   --rpc-url $LASNA_RPC_URL $S

# ⑤ Sepolia：触发（value=500 ≥ 阈值 100）
forge script script/ThreeStep.s.sol:Ping           --rpc-url $SEPOLIA_RPC_URL $S
```

## 三笔交易去哪找

| # | 是什么 | 去哪看 |
|---|---|---|
| ① | Ping 交易 | ⑤ 的输出里 `Hash:`，或 https://sepolia.etherscan.io/address/$ORIGIN_ADDR |
| ② | Lasna 上 react() 交易 | https://lasna.reactscan.net/address/$REACTIVE_ADDR 的交易列表；或 `cast logs --rpc-url $LASNA_RPC_URL --address $REACTIVE_ADDR --from-block <⑤之前的块> $(cast keccak "CallbackRequested(uint256,address,uint256)")` |
| ③ | Sepolia 回调交易 | https://sepolia.etherscan.io/address/$CALLBACK_ADDR 的 Internal Txns / Events；或 `cast call $CALLBACK_ADDR 'count()(uint256)' --rpc-url $SEPOLIA_RPC_URL` 变成 1 |

一般 10–60 秒内三笔都出现。

## 排错

| 现象 | 处理 |
|---|---|
| `insufficient funds` | Sepolia ETH 或 lREACT 不够：`bash go.sh check` 看余额 |
| Lasna 上 `lastReactBlock` 一直 0 | 订阅没对上：ORIGIN_ADDR 抄错了，重做 ②③④ |
| react 有了、回调没来 | `cast call -r $LASNA_RPC_URL 0x8888888888888888888888888888888888888888 'debt(address)(uint256)' $REACTIVE_ADDR` 大于 0 → 给合约转 lREACT；回调合约 ETH 不够 → 给 CALLBACK_ADDR 转 0.005 Sepolia ETH |
| 回调 revert `CallbackNotAuthorized` | ③ 的 REACTIVE_ADDR 填错，重做 ③④ |
| `Keystore ... not found` | 先 `cast wallet import camp --interactive` |
