# WealthKeeper · 个人财富管家

录入一次持仓与交易，自动拉取行情，计算收益、分红、手续费与资产占比。  
**不做荐股、买卖建议、价格预测。**

## 快速开始（iPhone）

```bash
open WealthKeeper.xcodeproj
```

在 Xcode 选择 Development Team → 模拟器或真机运行。详见 [iOS 实现说明](docs/ios-setup.md)。

## 核心价值

| 用户只做一次 | App 自动完成 |
|---|---|
| 录入持仓 / 买卖 / 分红 / 费用 | 日终价、净值、汇率 |
| （后续）标记存款 / 理财账户 | 每日盈亏、累计收益、资产占比 |

## 文档索引

- [产品愿景与边界](docs/product-vision.md)
- [行情数据评估](docs/market-data-assessment.md)
- [架构与本地存储](docs/architecture.md)
- [明确不做](docs/non-goals.md)
- [MVP 范围](docs/mvp-scope.md)
- [决策记录](docs/decisions.md)
- [iOS 实现说明](docs/ios-setup.md)

## 技术路线（已确认）

- **客户端**：原生 iOS（SwiftUI），先服务 iPhone
- **本地库**：SwiftData（持仓、买卖、分红、手续费、设置）
- **行情**：日终收盘价 / 基金净值 / 汇率 / 分红拆股；客户端直连
- **后端**：无业务后端

## 状态

- [x] 项目建立
- [x] 数据与架构评估
- [x] MVP 定义
- [x] 技术栈确认（SwiftUI）
- [x] 数据模型定稿
- [x] 开始实现（本地账本 + 行情刷新 + 资产页）
