# 亡羊补牢 项目方向卡

## 一句话

监听 Ethereum Sepolia 上受保护钱包转出指定 ERC-20 的事件。Lasna 上的守护合约判断单笔是否达到门槛、收款方是否为预设保险箱。如果满足救援条件，就请求 Sepolia 上的救援合约在授权和额度上限内，将钱包里剩下的代币转入保险箱。

## 赛道

赛道 2「Set It and Forget It」个人自动化。

## 目标用户和场景

目标用户是用自托管热钱包和链上应用交互、另有安全地址的个人。如果发现异常转出，常见做法是先打开钱包查看余额，再手动撤销可疑授权或转移剩余资产。这个项目让用户预先定好触发规则和保险箱，符合规则时自动转移剩余且已授权的代币。

## 最小 Demo

受保护钱包持有 1,000 PRAC，事前配置 100 PRAC 的单笔门槛和保险箱。模拟转出 300 PRAC 后，Lasna 请求救援，Sepolia 将剩余 700 PRAC 转入保险箱。这条链路已在测试网验证。

- [Sepolia 模拟转出 300 PRAC](https://sepolia.etherscan.io/tx/0xf0a62cfafe99eea50f1e8a71f53fd2d63e190d78bf4f0b6cba56bb3346155ae6)
- [Lasna 请求救援](https://lasna.reactscan.net/tx/0xa78b76179455576f62e465520fa21624159a1583c0bab2f6cd51a1d9c57fbc34)
- [Sepolia 保险箱收到 700 PRAC](https://sepolia.etherscan.io/tx/0x20aef9bf111b42f42ec9bac0daa9d5af79cf6ed008773dd3b90ba1318b51854e)

## 参赛方式

单人参赛。我负责选题、规则设计、测试网操作和演示，开发过程使用了 AI 编程工具辅助。
