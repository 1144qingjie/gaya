# 会员管理模块技术设计方案

## 1. 文档目标

本文用于明确 Gaya iOS 项目的会员管理模块设计，面向两类读者：

- 产品经理：理解会员套餐卖的是什么、用户看到什么、哪些规则已经确定。
- 开发实现：明确客户端、CloudBase 后端、StoreKit、积分结算和数据模型应如何落地。

本文基于当前已确认的业务决策，不包含具体价格和积分数值配置。

## 2. 已确认的业务决策

### 2.1 套餐形态

- 会员卖的是 `月卡 / 季卡订阅里的周期额度`，不是永久积分钱包。
- 月卡有效期 30 天，季卡有效期 90 天。
- 到期后，该周期剩余积分清零。
- 需要支持自动续费。

### 2.2 用户类型

- 免费用户：每天获得一笔免费积分，可用于消耗 token 的功能。
- 会员用户：购买月卡或季卡后，在对应周期内获得一笔套餐积分。
- 套餐到期后，用户自动回落为免费用户。

### 2.3 计费规则

- 所有涉及 token 消耗的功能，都要扣除积分。
- 不同功能即不同“商品”，即使都消耗 token，也可以配置不同积分单价。
- 不消耗 token 的功能，成本由平台承担，不扣积分。
- 自动触发的模型调用，只要消耗 token，也由用户承担。
- 文本类 / 图片类等能拿到真实 token 的能力，按真实 token 结算。
- 语音类能力按时长折算积分，一轮语音按“用户说话时长 + AI 回复时长”合并计算。

### 2.4 扣费时机

- 所有扣费请求都按“请求前预冻结、请求后结算”的方式处理。
- 中断、超时、空响应、重试，不扣积分。
- 成功请求只扣最终结算积分，多冻结的部分释放回账户。

### 2.5 架构分期

- 一期不强制把所有计费请求迁到后端统一代理。
- 二期再考虑“后端统一计费网关”。
- 一期先完成订阅、积分、冻结、结算、恢复购买、游客逻辑清理。

## 3. 面向产品的方案说明

### 3.1 这次会员模块卖的是什么

这次会员模块对外仍然可以叫“会员中心”，但本质上卖的是：

- 一个有时间有效期的订阅资格。
- 一份订阅周期内可消耗的积分额度。

因此：

- 用户买到的不是长期保存的虚拟货币。
- 用户买到的是“30 天 / 90 天内可用的 AI 使用额度”。
- 到期清零是因为额度属于订阅周期，不是因为平台回收用户的钱包余额。

### 3.2 用户看到的核心页面

会员中心页面建议展示以下信息：

- 当前身份：免费用户 / 月卡会员 / 季卡会员
- 当前套餐剩余积分
- 当前套餐总积分
- 到期时间
- 自动续费状态
- 积分消耗记录
- 套餐购买与恢复购买入口

### 3.3 用户规则

#### 免费用户

- 每天发放一笔免费积分。
- 可使用涉及 token 消耗的功能，直到当日免费积分耗尽。
- 免费积分用尽后，只能继续使用不消耗 token 的功能。

#### 月卡 / 季卡用户

- 套餐生效后，立刻获得该周期内的总积分。
- 套餐有效期内，所有计费功能优先消耗该套餐积分。
- 到期后未使用积分清零。
- 自动续费成功后，开启下一个周期，并发放新一轮积分。

### 3.4 商品化计费思路

系统里每一个会消耗 token 的能力，都视为一个独立商品。

例如：

- 文本聊天
- AI 洞察
- 图片理解首答
- 照片故事总结
- 记忆回廊自动总结
- 语音对话

这样做的目的有两个：

- 每个能力可单独定价。
- 即使 token 数相同，不同功能也能扣不同积分。

### 3.5 语音为什么按时长结算

当前项目的语音链路更适合按时长估算积分，而不是按实时返回 token 数精确结算。

产品上可以这样描述：

- 语音一轮按照“用户说话时长 + AI 回复时长”计算。
- 系统会把时长换算成预估 token，再折算成积分。
- 在会员中心说明“语音每分钟大约消耗多少积分”。

为了提升公平性，建议实际结算时按秒级折算，而不是粗暴按整分钟向上取整。

### 3.6 购买与恢复购买

#### 购买

- 用户在会员中心选择月卡或季卡。
- 通过 App Store 完成订阅购买。
- 购买成功后，套餐立即生效。

#### 自动续费

- 订阅使用 StoreKit 自动续费。
- 到期前由系统自动尝试续费。
- 续费成功后进入新的积分周期。

#### 恢复购买

- 用户可以在新设备或新手机号账号中恢复购买。
- 当前方案允许把权益迁移到另一个手机账户。
- 恢复成功后，旧账户立即失去当前订阅权益，剩余周期积分迁移到新账户。

### 3.7 失败补偿

用户可以理解为：

- 发起请求时系统先预留一部分积分。
- 如果请求失败，这部分积分会自动退回。
- 只有真正成功的内容，才会扣除积分。

## 4. 一期技术方案

### 4.1 范围

一期目标：

- 接入月卡 / 季卡 StoreKit 订阅
- 建立会员资料、周期积分、冻结、提交、释放能力
- 完成文本类、图片类、语音类计费接入
- 支持恢复购买和权益迁移
- 去掉游客模式相关逻辑

一期暂不做：

- 所有模型请求后端统一代理
- 后端统一真实成本计量
- 复杂运营后台

### 4.2 当前代码现状与改造方向

当前代码中与本方案直接相关的现状：

- 会员入口仍是占位按钮，位于 `gaya/Views/ContentView.swift`
- `AuthService` 仍嵌在 `ContentView.swift` 中，后续应抽离为独立服务
- 文本链路 `DeepSeekOrchestrator` 可读取真实 token usage
- 语音链路 `VoiceService` 仍是客户端直连火山 WebSocket
- 记忆与记忆回廊仍保留 `guest` 命名空间逻辑

对应改造方向：

- 抽出独立的 `Membership` 领域层
- 保留一期“客户端直连模型 + 后端管理积分”的折中形态
- 二期再升级为“后端统一网关 + 后端统一结算”

### 4.3 总体架构

一期采用“三层式”结构：

- iOS 客户端：负责登录态、StoreKit、功能门禁、发起冻结 / 提交 / 释放
- CloudBase 会员后端：负责套餐、订阅状态、周期积分、积分流水、冻结单
- 第三方模型服务：一期仍由客户端直接调用

工作方式：

1. 客户端先向后端创建冻结单
2. 冻结成功后，客户端再调用模型服务
3. 成功则提交结算，失败则释放冻结

### 4.4 核心领域模型

#### 会员套餐 `MembershipPlan`

- `planId`
- `name`
- `durationDays`
- `includedPoints`
- `appleProductId`
- `autoRenewable`
- `enabled`

#### 订阅实例 `MembershipSubscription`

- `subscriptionId`
- `uid`
- `planId`
- `status`
- `startedAt`
- `expiresAt`
- `autoRenewStatus`
- `originalTransactionId`
- `latestTransactionId`
- `boundAppleAccountHash`

#### 周期积分桶 `QuotaBucket`

- `bucketId`
- `uid`
- `bucketType`：`free_daily` / `plan_period`
- `planId`
- `totalPoints`
- `frozenPoints`
- `usedPoints`
- `remainingPoints`
- `startsAt`
- `expiresAt`
- `status`

#### 冻结单 `PointsHold`

- `holdId`
- `uid`
- `featureKey`
- `requestId`
- `holdPoints`
- `status`：`active` / `committed` / `released` / `expired`
- `createdAt`
- `expiresAt`
- `payload`

#### 计费商品 `FeatureCatalogItem`

- `featureKey`
- `name`
- `settlementMode`：`token_actual` / `duration_estimate`
- `unitSize`
- `pointsPerUnit`
- `preHoldStrategy`
- `preHoldPoints`
- `enabled`
- `autoTriggerCharge`

#### 流水 `PointsLedger`

- `ledgerId`
- `uid`
- `bucketId`
- `featureKey`
- `bizType`：`grant` / `freeze` / `commit` / `release` / `expire` / `renew`
- `pointsDelta`
- `requestId`
- `createdAt`
- `payload`

### 4.5 数据库集合设计

CloudBase 建议新增以下集合：

- `membership_plans`
- `membership_subscriptions`
- `membership_quota_buckets`
- `membership_points_holds`
- `membership_points_ledger`
- `membership_feature_catalog`
- `membership_binding_history`

索引建议：

- `membership_subscriptions.uid + status`
- `membership_subscriptions.original_transaction_id`
- `membership_quota_buckets.uid + status + expires_at`
- `membership_points_holds.uid + request_id`
- `membership_points_ledger.uid + created_at`
- `membership_feature_catalog.feature_key`

### 4.6 积分与套餐规则

#### 免费积分

- 免费用户每天生成一个 `free_daily` 桶
- 到次日失效
- 若用户当日已成为会员，默认不再发免费积分

说明：这里采用“会员有效期内不叠加免费日积分”的默认规则，避免定价口径混乱。若后续产品希望叠加，可通过配置开放。

#### 套餐积分

- 用户购买月卡或季卡后，生成一个 `plan_period` 桶
- 生命周期与订阅周期一致
- 到期后剩余积分自动清零并写入 `expire` 流水

#### 优先级

- 若存在有效 `plan_period` 桶，则优先使用套餐积分
- 否则使用免费积分

### 4.7 计费公式

#### 文本 / 图片 / 洞察类：真实 token 结算

统一公式：

```text
billableUnits = ceil(actualTokens / unitSize)
actualPoints = billableUnits * pointsPerUnit
```

示例：

- 文本聊天：`unitSize = 100 token`，`pointsPerUnit = 1`
- AI 洞察：`unitSize = 100 token`，`pointsPerUnit = 2`

说明：

- 相同 token 数，不同商品可配置不同 `pointsPerUnit`
- 这样就实现了“不同商品单价不同”

#### 语音类：按时长估算结算

统一公式：

```text
billableSeconds = userSpeakSeconds + aiSpeakSeconds
actualPoints = ceil(billableSeconds * pointsPerMinute / 60)
```

说明：

- 产品层展示为“每分钟约 X 积分”
- 系统内部按秒折算，更公平
- 一轮语音定义为“用户一次完整说话 + AI 一次完整回复”

### 4.8 预冻结与最终结算

#### 创建冻结单

客户端在真正发起模型请求前，先调用后端创建冻结单。

冻结策略：

- 文本类：按该商品的预估最大扣费额度冻结
- 图片类：按该商品的预估最大扣费额度冻结
- 语音类：按 1 分钟标准额度冻结，若一轮语音配置更高可单独配置

#### 成功提交

请求成功后：

- 文本类提交真实 token
- 语音类提交真实时长
- 后端计算实际积分
- 只扣实际积分，释放多余冻结

#### 失败释放

以下情况一律释放冻结，不扣积分：

- 中断
- 超时
- 空响应
- 手动取消
- 重试失败

#### 冻结单兜底释放

为防止客户端崩溃导致冻结无法释放：

- 冻结单设置短 TTL
- 后端定时扫描过期冻结单
- 自动释放并写 `release` 流水

### 4.9 自动触发任务的计费规则

自动触发类调用，例如：

- 记忆回廊自动总结
- 照片故事自动生成
- 其他系统后台触发但实际消耗 token 的能力

统一规则：

- 先创建冻结单
- 成功则结算
- 失败则释放
- 与用户主动触发没有结算差异

区别只在于 `payload.triggerSource = automatic`

### 4.10 恢复购买与权益迁移

#### 基本规则

- `originalTransactionId` 是订阅根标识
- 同一时刻，一个订阅只绑定到一个 `uid`
- 恢复购买时允许迁移到另一个手机号账号

#### 迁移策略

恢复购买流程命中已绑定其他账户时：

1. 后端校验 Apple 交易有效
2. 将当前订阅绑定从旧 `uid` 迁移到新 `uid`
3. 未过期的订阅周期与剩余积分一起迁移
4. 旧账户即时失去当前周期权益
5. 写入 `membership_binding_history`

这样可满足“恢复购买时权益允许迁移至另一个手机账户”的业务要求。

### 4.11 StoreKit 方案

采用 `Auto-Renewable Subscription`：

- 月卡：1 个月订阅产品
- 季卡：3 个月订阅产品

建议：

- 放在同一个 subscription group
- 这样可支持标准化的升级、降级、续费管理

建议产品 ID：

- `com.gaya.membership.monthly`
- `com.gaya.membership.quarterly`

### 4.12 后端接口设计

建议新增以下 CloudBase HTTP 函数：

- `membership_profile_get`
- `membership_products_list`
- `membership_purchase_sync`
- `membership_restore_sync`
- `membership_hold_create`
- `membership_hold_commit`
- `membership_hold_release`
- `membership_ledger_list`

#### `membership_profile_get`

返回：

- 当前用户身份
- 当前订阅状态
- 当前有效积分桶
- 剩余积分
- 到期时间
- 自动续费状态

#### `membership_purchase_sync`

用途：

- 上报 StoreKit 交易
- 校验交易
- 创建或续订订阅
- 发放套餐周期积分

#### `membership_restore_sync`

用途：

- 恢复购买
- 处理权益迁移
- 刷新当前账号订阅状态

#### `membership_hold_create`

入参：

- `featureKey`
- `requestId`
- `estimatedPoints`
- `payload`

返回：

- `holdId`
- `holdPoints`
- `expiresAt`

#### `membership_hold_commit`

入参：

- `holdId`
- `requestId`
- `actualUsage`
- `actualPoints`
- `payload`

说明：

- 文本类由后端根据 `actualUsage.totalTokens` 算积分
- 语音类由后端根据 `actualUsage.billableSeconds` 算积分

#### `membership_hold_release`

入参：

- `holdId`
- `requestId`
- `reason`

### 4.13 iOS 客户端模块设计

建议新增目录：

```text
gaya/
  Membership/
    Models/
    Services/
    Views/
```

建议新增核心对象：

- `MembershipStore`
- `MembershipAPI`
- `MembershipFeatureCatalog`
- `MembershipPricingEngine`
- `StoreKitMembershipService`
- `MembershipGate`

#### `MembershipStore`

职责：

- 拉取会员资料
- 持有当前套餐状态
- 持有剩余积分
- 处理购买成功后的刷新

#### `MembershipAPI`

职责：

- 调用后端会员函数
- 创建冻结单
- 提交结算
- 释放冻结

#### `MembershipPricingEngine`

职责：

- 读取商品计费配置
- 计算文本类积分
- 计算语音类积分
- 产出预冻结额度

#### `StoreKitMembershipService`

职责：

- 拉取月卡 / 季卡商品
- 发起购买
- 监听续费与交易更新
- 恢复购买
- 同步购买给后端

#### `MembershipGate`

职责：

- 在功能发起前判断是否有可用积分
- 在积分不足时展示会员中心或购买弹层

### 4.14 各能力的接入方式

#### 文本聊天

- 发起前：创建冻结单
- 成功后：读取真实 token 并提交
- 失败后：释放冻结

#### AI 洞察 / 图片理解 / 自动总结

- 接入方式与文本类一致
- 仅商品配置不同

#### 语音对话

- 一轮开始前：创建冻结单
- 一轮结束后：上报用户说话秒数与 AI 播放秒数
- 成功结算实际积分
- 失败释放冻结

### 4.15 去掉游客模式

本次会员模块应同步移除项目中的游客模式语义：

- 去掉游客相关文案
- 去掉 `guest` 命名空间作为产品概念
- 未登录用户只处于“待登录”状态
- 登录后才进入正常产品流转

说明：

- 底层实现上可以暂时保留 `guest` 作为异常兜底命名空间
- 但对外产品逻辑、文案和页面行为不再出现“游客可体验”

### 4.16 审核与测试支持

由于产品不再提供游客模式，会员模块落地时需要同步考虑审核与测试：

- App Store 审核需要可稳定进入产品主流程
- 若审核环境无法使用一键登录或短信登录，需要准备测试账号方案
- 内部测试需要支持购买成功、续费、恢复购买、迁移绑定、冻结释放等链路验证

## 5. 二期方向

二期目标是把所有计费型请求统一收敛到后端：

- 后端统一代理模型调用
- 后端统一拿真实 usage
- 客户端不再直连第三方模型
- 积分体系从“可信业务规则”升级为“可信技术管控”

## 6. 开发落地计划

### 阶段 1：数据与接口

- 新增会员相关集合
- 新增会员相关云函数
- 完成冻结 / 提交 / 释放闭环

### 阶段 2：StoreKit 与会员中心

- 接入月卡 / 季卡商品
- 完成会员中心页面
- 完成购买、续费、恢复购买

### 阶段 3：计费接入

- 接入文本类功能
- 接入图片类功能
- 接入语音类按时长结算

### 阶段 4：逻辑清理

- 去掉游客文案
- 去掉游客产品流
- 把认证与会员状态解耦

## 7. 已知风险与限制

- 一期仍允许客户端直连模型，存在被绕过风险
- 语音按时长估算与真实成本之间会有偏差
- 恢复购买允许跨手机号迁移，会带来共享 Apple ID 的风险
- 客户端异常退出时，积分会短暂处于冻结状态，依赖后端 TTL 自动回收

## 8. 待配置参数表

以下参数仍需产品给出具体值：

- 免费用户每日积分
- 月卡总积分
- 季卡总积分
- 各商品的 `unitSize`
- 各商品的 `pointsPerUnit`
- 各商品的 `preHoldPoints`
- 语音每分钟展示积分
- 是否允许会员有效期内继续领取免费日积分

## 9. 结论

本方案把会员模块定义为：

- 一个基于 App Store 自动续费订阅的周期额度系统
- 一个支持免费积分、套餐积分、冻结、结算、恢复购买、权益迁移的计费系统
- 一个可以在一期先上线业务规则、二期再提升技术可信度的实现路径

这满足当前已经敲定的产品方向，也与现有代码结构具备可衔接性。

## 10. 参考资料

- Apple App Review Guidelines  
  https://developer.apple.com/app-store/review/guidelines/
- Apple In-App Purchase Types  
  https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types/
- 火山端到端实时语音大模型接入  
  https://www.volcengine.com/docs/6348/1902994
- 火山语音计费说明  
  https://www.volcengine.com/docs/6561/1359370
