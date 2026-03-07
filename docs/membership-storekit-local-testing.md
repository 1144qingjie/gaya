# Membership StoreKit 本地联调

本文用于本地调试 Gaya 会员订阅，重点覆盖：

- 月卡、季卡商品 ID
- 自动续费与恢复购买验证
- 如何把本地 `.storekit` 文件挂到工程 scheme
- 如何快速检查本地联调环境是否就绪

## 1. 本地测试商品

当前会员模块使用以下商品 ID：

- 月卡：`com.gaya.membership.monthly`
- 季卡：`com.gaya.membership.quarterly`

业务约束：

- 两个商品应放在同一个 `subscription group`
- 都是 `Auto-Renewable Subscription`
- 月卡周期 30 天，对应会员 `plan_id = monthly`
- 季卡周期 90 天，对应会员 `plan_id = quarterly`

## 2. 推荐的本地 StoreKit 配置

在 Xcode 中新建一个本地 StoreKit Configuration 文件，例如：

- `gaya/Resources/StoreKit/GayaMembership.storekit`

推荐建模：

- Subscription Group：`Gaya Membership`
- Product 1：`com.gaya.membership.monthly`
- Product 2：`com.gaya.membership.quarterly`

建议在本地测试时打开：

- 自动续费
- Accelerated renewal
- Billing retry / grace period 场景

## 3. 如何挂到工程

项目里已经补了共享 scheme：

- [gaya.xcscheme](/Users/zhaolu/gaya/gaya.xcodeproj/xcshareddata/xcschemes/gaya.xcscheme)
- StoreKit 占位目录：[README.md](/Users/zhaolu/gaya/gaya/Resources/StoreKit/README.md)

在 Xcode 中操作：

1. `Product > Scheme > Edit Scheme...`
2. 选择 `Run`
3. 在 `Options` 页签中选择 `StoreKit Configuration`
4. 指向本地的 `GayaMembership.storekit`
5. 保存 scheme

如果需要把 `.storekit` 文件也提交到仓库，请在 Xcode 中创建文件后，再把对应文件引用加入工程。

## 3.1 本地环境自检

可以先执行：

```bash
bash /Users/zhaolu/gaya/scripts/check_membership_local_env.sh
```

这个脚本会检查：

- `gaya` 共享 scheme 是否存在
- `Secrets.swift` 的 CloudBase URL 是否仍是占位值
- `gaya/Resources/StoreKit/` 下是否已经放入 `.storekit` 文件
- `gaya` shared scheme 是否已经挂上 StoreKit Configuration
- `xcodebuild` 是否能识别到 `gaya` scheme

## 4. 联调检查项

进入会员中心后，先看两处状态提示：

- 顶部摘要卡：
  - 如果显示“当前处于调试模拟购买”，说明 App 没有拿到真实 StoreKit 商品
  - 如果这时仍能购买，是因为 `DEBUG` 下保留了本地模拟购买兜底
- `订阅调试` 面板：
  - `商品状态` 应该从“未发现商品”切成“已就绪 2 个商品”
  - `计费模式` 应该从“Debug 模拟购买”切成“App Store 真实订阅”
  - `缺失商品` 应该变成 `无`

### 购买

- 免费用户登录
- 打开会员中心
- 月卡 / 季卡显示本地价格
- 点击购买后，后端收到 `/membership/purchase/sync`
- 会员身份切为对应套餐
- 周期积分桶发放成功

### 自动续期

- Accelerated renewal 到期后触发新交易
- App 前台唤醒后自动同步续期交易
- 后端新增新的周期积分桶
- 上一周期到期后积分清零

### 恢复购买

- 删除 App 或切换设备账号
- 登录另一个手机账户
- 点击 `恢复购买`
- 后端走 `/membership/restore/sync`
- 权益迁移成功，旧账户失去当前周期权益

### 管理订阅

- 会员中心点击 `管理订阅`
- 能跳转系统订阅管理页

## 4.1 Debug 模拟购买说明

当本地还没有 `.storekit` 配置时：

- 月卡 / 季卡仍可在 `DEBUG` 下使用“调试开通”按钮
- 这条链路仍会走会员后端的购买同步、积分发放、恢复购买和流水刷新
- `订阅调试` 面板会显示当前仍在使用 Debug 模拟模式

调试面板里新增了两个辅助操作：

- `刷新商品`：
  - 重新拉取一次 StoreKit 商品，适合你刚在 Xcode 挂好 `.storekit` 后立即验证
- `清空模拟订单`：
  - 只清理当前设备的本地模拟购买记录
  - 不会回滚云端已经生效的会员权益
  - 主要用于重复验证“恢复购买 / 自动续期来源缺失”这类本地场景

## 5. 当前代码入口

- StoreKit 商品加载与购买：[MembershipService.swift](/Users/zhaolu/gaya/gaya/Services/MembershipService.swift#L505)
- 购买 / 恢复购买：[MembershipService.swift](/Users/zhaolu/gaya/gaya/Services/MembershipService.swift#L901)
- 管理订阅入口：[MembershipService.swift](/Users/zhaolu/gaya/gaya/Services/MembershipService.swift#L1027)
- 前台自动同步订阅更新：[MembershipService.swift](/Users/zhaolu/gaya/gaya/Services/MembershipService.swift#L812)
