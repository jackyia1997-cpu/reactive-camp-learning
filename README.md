# 亡羊补牢 v1.0

一笔异常转账已经发生，钱包里剩下的币怎么办？

「亡羊补牢」这个项目做的是这一步。你事先选好要保护的代币、转出门槛和保险箱地址。之后，只要有一笔转出符合规则，Reactive 就会请求救援，把钱包里剩余且已授权的代币转到保险箱。

我们用 1,000 个 PRAC 练习币跑了一次。模拟转出 300 个后，剩下的 **700 个进了保险箱**。[查看到账交易](https://sepolia.etherscan.io/tx/0x20aef9bf111b42f42ec9bac0daa9d5af79cf6ed008773dd3b90ba1318b51854e)

Reactive Builder Camp 项目，赛道 2「Set It and Forget It」。

## 一次救援怎么发生

```
Sepolia 钱包转出 300 PRAC
  ↓
Lasna 收到转账事件，检查门槛和收款方是否为风险地址，发出救援请求
  ↓
Sepolia 的救援合约把剩余 700 PRAC 转入保险箱
```

用户先通过 `approve` 给救援合约设置额度。救援发生时，合约按**当时的剩余余额**计算可转金额，收款地址固定为部署时选定的保险箱。每份配置对应一种 ERC-20。已经转出的 300 PRAC 留在原收款地址。

## 三个合约

| 合约 | 链 | 作用 |
|---|---|---|
| `src/rescue/PracticeToken.sol` | Sepolia | 发行演示用的 PRAC |
| `src/rescue/GuardReactive.sol` | Lasna | 用 `topic1` 过滤付款地址，判断转出是否达到门槛 |
| `src/rescue/RescueGuardian.sol` | Sepolia | 核验回调并将符合额度的代币转入保险箱 |

### 怎么防止误触发和重复转账

1. **按规则触发。** 只看受保护钱包转出的指定代币。低于门槛或转给保险箱时跳过。新版也会跳过用户设置的可信收款地址。
2. **同一件事只做一次。** Lasna 用链 ID、交易哈希和日志序号识别每条源事件。Sepolia 的救援合约也会核对交易哈希和日志序号，避免重复执行。
3. **设金额上限。** 实际金额取钱包剩余余额、剩余授权、单次上限和累计剩余额度中的最小值。
4. **核对回调来源。** 救援合约先认 Sepolia 官方回调代理，再认绑定的 Lasna 守护合约。
5. **可以暂停。** 钱包可主动暂停保护。救援请求有次数上限，默认三次，用完自动退订。

## 本地测试（不用钱包、不花币）

```bash
bash go.sh setup      # 下载依赖 + forge test
```

本机最新版 27 个测试全部通过：营地模板 8 个 + 救援 19 个（被盗触发救援、低于阈值不触发、转给安全地址不触发、同一事件两次只回调一次、重复投递不重复搬、单次/累计上限、只搬 approve 的额度、冒充调用被拒、非受保护地址转出不触发、暂停与次数上限、只有 owner 能改配置）。

## 本机开发进度

新版测试网页支持连接钱包、逐步部署、限额授权和查看链上记录。新版守护合约增加了可信收款地址和仅提醒模式。仅提醒把符合规则的转出记录到 Lasna，保留钱包余额和救援次数。以上新功能已经过本地测试，测试网链上证据对应已部署的自动救援版本。

### 在本机打开测试网页

安装 Node.js 22 后，在仓库根目录运行 `node web/server.mjs`，打开终端显示的本机地址。点击「查看已跑通的测试网案例」即可查看链上的 700 PRAC 到账记录。新建保护时可选择最多 1–5 次救援。用新钱包从网页完整部署和触发救援还待测试网验收。

[测试网页使用说明](web/使用说明.md)

## 上链复现

前提：装好 Foundry；`cast wallet import camp --interactive` 导入**测试专用**钱包；地址上有 Sepolia ETH 和 lREACT；MetaMask 里另建一个账户当安全地址。

```bash
bash go.sh three     # 营地必做：跨链回调三步走（模板 CampOrigin → CampReactive → CampCallback）
bash go.sh rescue    # 本项目：部署 + 模拟转出 + 自动救援
bash go.sh proof     # 打印所有合约地址和交易链接
```

脚本会依次部署、把地址记进 `deployments.env`（只有公开地址），并等链上出现 Lasna 的 react 交易和 Sepolia 的回调交易，最后生成 `PROOF.md`。

## 链上证据

测试网救援已跑通。Sepolia 模拟转出 300 PRAC 后，Lasna 发出救援请求，Sepolia 回调把仍在钱包里的 700 PRAC 转入预设保险箱。

| 步骤 | 链接 |
|---|---|
| ① Sepolia 模拟转出 300 PRAC | [源交易](https://sepolia.etherscan.io/tx/0xf0a62cfafe99eea50f1e8a71f53fd2d63e190d78bf4f0b6cba56bb3346155ae6) |
| ② Lasna 请求救援 | [Reactive 交易](https://lasna.reactscan.net/tx/0xa78b76179455576f62e465520fa21624159a1583c0bab2f6cd51a1d9c57fbc34) |
| ③ Sepolia 救援回调，保险箱收到 700 PRAC | [到账交易](https://sepolia.etherscan.io/tx/0x20aef9bf111b42f42ec9bac0daa9d5af79cf6ed008773dd3b90ba1318b51854e) |
| GuardReactive | [Lasna 合约](https://lasna.reactscan.net/address/0x9630a56afa3cd9ea410064c442ec59f472bbff64) |
| RescueGuardian | [Sepolia 合约](https://sepolia.etherscan.io/address/0x842e030365aad60d021f4e20ed02ea55180e2066) |
| PracticeToken | [Sepolia 练习币](https://sepolia.etherscan.io/address/0x978fe8c66dcc5288bd62ce340d110404f13f9ca5) |

### 训练营模板三步走

| 步骤 | 链接 |
|---|---|
| ① Sepolia Ping | [源交易](https://sepolia.etherscan.io/tx/0x8f39d22cc0cead2f77fc173e52f03ce9b55dd6a532f99e3c231ba474cf2c654e) |
| ② Lasna react() | [Reactive 交易](https://lasna.reactscan.net/tx/0x48f94ec18d55ea8a4fc517482c80951e4ef1bc909e2ee666fdc340e6cdad96cc) |
| ③ Sepolia 回调 Handled | [回调交易](https://sepolia.etherscan.io/tx/0xb4ffe2adae1b383fbe39ebbb600677e72895716ec56f1c866771f1536963c9a3) |

## 网络与地址（2026-11-18 对照官方文档核对）

| 项 | 值 | 来源 |
|---|---|---|
| Lasna RPC / chainId | `https://lasna-rpc.rnk.dev/` / 5318007 | https://dev.reactive.network/reactive-mainnet |
| Lasna 浏览器 | https://lasna.reactscan.net/ | 同上 |
| 系统合约 | `0x8888888888888888888888888888888888888888` | 同上 |
| Sepolia chainId | 11155111 | https://dev.reactive.network/origins-and-destinations |
| Sepolia Callback Proxy | `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` | 同上 |
| lREACT 水龙头（Sepolia） | `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`，1 ETH → 100 lREACT，单笔 ≤ 5 ETH | https://dev.reactive.network/reactive-mainnet |

## 训练营作业

- [用例拆解卡](notes/d1-use-case.md)
- [项目方向卡](notes/project-direction.md)
- [Lasna 费用笔记](notes/lasna-fees.md)
- [救援测试代码](test/Rescue.t.sol)

根目录的 `Rescue.t.sol` 保留此前已提交的作业链接。运行 Foundry 时使用 `test/` 下的当前测试。

## 致谢与 AI 使用说明

- `src/Camp*.sol`、`test/Camp.t.sol` 来自营地模板 https://github.com/ethpanda-org/reactive-builder-camp （starter），未改动。`script/ThreeStep.s.sol` 改自模板部署脚本，使用 keystore 签名，并调小预付金额。
- 依赖为 reactive-lib-omni v0.1.0 和 forge-std v1.17.0。
- 救援合约、测试和 `go.sh` 由 AI 编程助手生成初稿。验证包括本机最新版的 27 项 Foundry 测试、本地双 Anvil 链演练，以及上方的 Sepolia 和 Lasna 交易。

## 出问题怎么办

**合约经费用完。** 钱包里的 PRAC 是等待救援的代币。自动执行要另付手续费，Lasna 守护合约用 lREACT，Sepolia 救援合约用 Sepolia ETH。即使钱包里还剩 PRAC，任一侧的合约也可能因为欠费停下来。

恢复时先查合约欠费和预存余额。Lasna 经费不足，就通过系统合约的 `depositTo(GuardReactive 地址)` 充值 lREACT。Sepolia 经费不足，就通过回调代理的 `depositTo(RescueGuardian 地址)` 充值 Sepolia ETH。充值先抵欠费，余款存作执行经费。确认恢复后，用新的测试事件验证。救援次数用完属于另一种情况，订阅已经结束，需要重新配置一套保护。[Reactive 排错指南](https://dev.reactive.network/debugging)

**回调到了，保险箱没收到币。** 先看回调交易里有没有 `Rescued` 和代币 `Transfer`。外层交易显示成功时，回调代理也可能记了一条 `CallbackFailure`。我们第一次演示就是执行所获的 Gas 不够，保险箱余额还是 0。后来把回调 Gas 上限从 50 万调到 100 万，重新部署并用新的测试转出验证，保险箱收到 700 PRAC。[首次回调记录](https://sepolia.etherscan.io/tx/0x24870b2135c52f778e149ee02aed2505dafec267566e78d386563684f3075c2c)

去重管的是**同一条链上事件被送来两次**。当前版本已处理过的源事件会被跳过，因此修好后用新的练习转出验证。失败的回调仍可能产生手续费。[回调费用说明](https://dev.reactive.network/callback-contracts#paying-for-callbacks)

## 使用范围

目前在 Ethereum Sepolia 和 Reactive Lasna 上验证，复现时使用测试钱包与练习代币。
