# Reactive Builder Camp 学习仓库｜钱包被盗自动救援（测试网演示）

ETHPanda × LXDAO Reactive Builder Camp 学员仓库。赛道 2「Set It and Forget It」，对应官方场景 2「钱包守护」。
**只在测试网（Ethereum Sepolia + Reactive Lasna）演示，只用没有价值的练习币，仓库里没有任何私钥或助记词。**

## 一句话

Sepolia 上我的地址一旦有「异常转出」，Lasna 上的 Reactive 合约马上发现，并让 Sepolia 上的救援合约把**剩下的、事先授权过的**练习币搬到我写死的安全地址。

```
Sepolia  PracticeToken.Transfer(from = 我, to = 小偷, 300 PRAC)      ① 被盗
           │  Reactive 网络只把「from = 我」的 Transfer 送过来（订阅 topic1 = 我的地址）
           ▼
Lasna    GuardReactive.react(log)                                     ② 判断
           转出 >= 100 PRAC 且收款方不是安全地址？没处理过这笔？ → 请求回调
           │  Callback Proxy 投递
           ▼
Sepolia  RescueGuardian.rescue(...)                                   ③ 救援
           transferFrom(我 → 安全地址, 剩余 700 PRAC)
```

## 大白话：它能做什么、不能做什么

- 能：在没人盯着电脑的情况下，发现大额转出后自动把剩下的币转走。
- 不能：已经被转走的那一笔救不回来；也不保证一定抢在小偷前面（小偷可能先把剩下的也转走，或撤销授权）。
- 前提：我事先 `approve` 给救援合约一个**有上限**的额度。这不是把币交出去，是开了一张「最多只能转到安全地址、最多 N 个」的提款单。
- 只覆盖订阅的这一种 ERC-20，不覆盖原生 ETH。
- 这是学习演示，不是能上主网的被盗保险。

## 三个合约

| 合约 | 链 | 作用 |
|---|---|---|
| `src/rescue/PracticeToken.sol` | Sepolia | 练习币 PRAC，部署时给我 1000 个 |
| `src/rescue/GuardReactive.sol` | Lasna | 哨兵：只订阅「PRAC 从我地址转出」；判断后请求回调 |
| `src/rescue/RescueGuardian.sol` | Sepolia | 搬运工：收到回调后把剩余 PRAC 搬到安全地址 |

### 安全设计（对应营地 11/25「加保护」）

1. **只在该触发时触发**：订阅层只听 `from = 我`；`react()` 里再判断：金额 ≥ 阈值（默认 100 PRAC）、收款方不是安全地址（否则救援自己的转账会无限循环）。不满足用 `return`，不用 `revert`（revert 也收费）。
2. **同一件事不做两次**：哨兵用 `(chainId, txHash, logIndex)` 去重；搬运工也用 `(txHash, logIndex)` 再去重一次。
3. **金额上限**：单次上限 `MAX_PER_RESCUE`、累计上限 `MAX_TOTAL`，再加上 approve 额度，三道取最小。
4. **两道门卫**：`onlyServiceProvider`（只认 Sepolia Callback Proxy）+ `onlyCallbackSender`（只认我部署的那个哨兵）。去向 `SAFE` 是 immutable，谁都改不了。
5. **防烧钱**：最多处理 `RESCUE_LIMIT` 次（默认 3），用完自动退订；可以 `setPaused(true)` 随时停。

## 本地测试（不用钱包、不花币）

```bash
bash go.sh setup      # 下载依赖 + forge test
```

22 个测试全部通过：营地模板 8 个 + 救援 14 个（被盗触发救援、低于阈值不触发、转给安全地址不触发、同一事件两次只回调一次、重复投递不重复搬、单次/累计上限、只搬 approve 的额度、冒充调用被拒、非受保护地址转出不触发、暂停与次数上限、只有 owner 能改配置）。

## 上链复现

前提：装好 Foundry；`cast wallet import camp --interactive` 导入**测试专用**钱包；地址上有 Sepolia ETH 和 lREACT；MetaMask 里另建一个账户当安全地址。

```bash
bash go.sh three     # 营地必做：跨链回调三步走（模板 CampOrigin → CampReactive → CampCallback）
bash go.sh rescue    # 本项目：部署 + 假装被盗 + 自动救援
bash go.sh proof     # 打印所有合约地址和交易链接
```

脚本会依次部署、把地址记进 `deployments.env`（只有公开地址），并等链上出现 Lasna 的 react 交易和 Sepolia 的回调交易，最后生成 `PROOF.md`。

## 链上证据（演示后填写）

| 步骤 | 链接 |
|---|---|
| ① Sepolia 假装被盗（转 300 PRAC 给 0x…dEaD） | 待填 |
| ② Lasna GuardReactive 判断异常并请求回调 | 待填 |
| ③ Sepolia RescueGuardian 把剩余 700 PRAC 搬到安全地址 | 待填 |
| GuardReactive 合约 | 待填 |
| RescueGuardian 合约 | 待填 |
| PracticeToken 合约 | 待填 |

跨链回调三步走（营地必做）：

| 步骤 | 链接 |
|---|---|
| ① Sepolia Ping | 待填 |
| ② Lasna react() | 待填 |
| ③ Sepolia 回调 Handled | 待填 |

## 网络与地址（2026-11-18 对照官方文档核对）

| 项 | 值 | 来源 |
|---|---|---|
| Lasna RPC / chainId | `https://lasna-rpc.rnk.dev/` / 5318007 | https://dev.reactive.network/reactive-mainnet |
| Lasna 浏览器 | https://lasna.reactscan.net/ | 同上 |
| 系统合约 | `0x8888888888888888888888888888888888888888` | 同上 |
| Sepolia chainId | 11155111 | https://dev.reactive.network/origins-and-destinations |
| Sepolia Callback Proxy | `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` | 同上 |
| lREACT 水龙头（Sepolia） | `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`，1 ETH → 100 lREACT，单笔 ≤ 5 ETH | https://dev.reactive.network/reactive-mainnet |

## 致谢与 AI 使用说明

- `src/Camp*.sol`、`test/Camp.t.sol` 来自营地模板 https://github.com/ethpanda-org/reactive-builder-camp （starter），未改动；`script/ThreeStep.s.sol` 改自模板部署脚本（改用 keystore 签名、调小预付金额）。
- 依赖：reactive-lib-omni v0.1.0、forge-std v1.17.0。
- 救援合约、测试、`go.sh` 由 AI 编程助手生成初稿。验证方式：本地 22 个 Foundry 测试；本地双 anvil 链 + 模拟 Reactive 投递的端到端演练（三步走和救援均跑通，余额 0 / 700 / 300 符合预期）；最终以上方 Sepolia / Lasna 真实交易为准。

## 安全

- 只用测试网和新建的测试钱包；私钥只存在本机 Foundry 加密 keystore 里，不进仓库、不进打卡、不发给任何人或 AI。
- 不要把这个合约用在真实资产上。
