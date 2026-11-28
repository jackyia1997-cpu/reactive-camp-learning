# 训练营模板三步走实测

这是训练营 starter 模板的测试记录。项目本身的救援链路与保险箱到账记录见 [README 的链上证据](../README.md#链上证据)。

| 步骤 | 交易 |
|---|---|
| ① Sepolia 发出 Ping | [源交易](https://sepolia.etherscan.io/tx/0x8f39d22cc0cead2f77fc173e52f03ce9b55dd6a532f99e3c231ba474cf2c654e) |
| ② Lasna 调用 `react()` 并请求回调 | [Reactive 交易](https://lasna.reactscan.net/tx/0x48f94ec18d55ea8a4fc517482c80951e4ef1bc909e2ee666fdc340e6cdad96cc) |
| ③ Sepolia 执行回调并记录 `Handled` | [回调交易](https://sepolia.etherscan.io/tx/0xb4ffe2adae1b383fbe39ebbb600677e72895716ec56f1c866771f1536963c9a3) |

[模板手动复现步骤](../docs/RUNBOOK-三步走.md)
