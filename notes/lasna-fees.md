读懂 Lasna 执行费用

2026-11-28，使用 Foundry 的 cast 读取 Lasna 系统合约。查询开始时的区块为 9466150。

## 三条查询和输出

```text
$ cast call 0x8888888888888888888888888888888888888888 "_gasPriceCoeffPer1000()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
1000

$ cast call 0x8888888888888888888888888888888888888888 "_extraGas()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
100000 [1e5]

$ cast call 0x8888888888888888888888888888888888888888 "_maxChargeGas()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
50000 [5e4]
```

## 一次 react 的费用怎么算

我把这笔费用看成「实际工作量加一个固定起步量」，再乘上 Gas 单价和系统系数。计费用的 Gas 单价取交易 Gas 价格和区块基础 Gas 价格中较高的那个。

```text
费用 = Gas 单价 × (_gasPriceCoeffPer1000 ÷ 1000) × (实际消耗 Gas + _extraGas)
```

这次查到的系数是 1，固定附加是 100,000 Gas。比如实际消耗 50,000 Gas，就按 150,000 Gas 乘以单价，再乘以 1。Lasna 用 lREACT 结算。`_maxChargeGas` 是系统调用合约的 `pay()` 时可使用的 Gas 上限，管收款过程。

## balance reserves 和 debt 有什么区别

- **balance** 是守护合约自己地址里的 lREACT 余额。系统收款时，合约可以用这里的钱付账。
- **reserves** 是预存在 Lasna 系统合约、记在守护合约名下的手续费。收费先用这笔预存。
- **debt** 是已经产生、还没结清的手续费。系统收到新事件时先查欠费，所以只要欠费大于零，就暂停给这个合约执行 `react()`，避免欠费继续增加。用系统合约的 `depositTo(守护合约地址)` 充值会先还欠费，再把余款加进预存。

## react 回滚还收费吗

会。回滚撤销的是合约这次写入的状态，执行过程中消耗的 Gas 仍按规则收费。我的守护合约用订阅条件先限定代币和付款地址。收到低于门槛或转给保险箱的正常事件时，函数用 `return` 提前结束。提前结束仍可能产生执行费，所以还要靠精确订阅和救援次数上限减少浪费。

参考 [Reactive 计费与系统合约](https://dev.reactive.network/economy) 和 [Reactive 排错指南](https://dev.reactive.network/debugging#reverting-react)。
