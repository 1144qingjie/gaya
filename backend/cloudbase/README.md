# CloudBase 认证与会员后端（阿里云 PNVS）

本目录包含手机号登录与会员积分后端实现，运行在 CloudBase 云函数。

## 目标

- 支持本机号码一键登录（PNVS 一键登录 token 换号）
- 支持其他手机号验证码登录（发送码 + 校验）
- 未注册手机号首次验证通过后自动创建用户
- 返回 App 会话令牌（access_token / refresh_token）
- 支持会员套餐、积分冻结、积分结算、恢复购买

## 云函数清单

- `auth_db_init`: 初始化认证相关数据库集合（仅运维调用，不绑定 HTTP 路由）
- `auth_onetap_login`: 校验 PNVS 一键登录 token 并登录
- `auth_sms_send`: 发送短信验证码
- `auth_sms_verify`: 校验验证码并登录
- `user_bootstrap`: 更新用户昵称（可选）
- `membership_products_list`: 获取会员套餐与计费配置
- `membership_profile_get`: 获取当前用户会员资料与积分
- `membership_purchase_sync`: 同步月卡 / 季卡购买结果
- `membership_restore_sync`: 恢复购买并迁移权益
- `membership_hold_create`: 创建积分冻结单
- `membership_hold_commit`: 成功后提交积分结算
- `membership_hold_release`: 失败 / 中断后释放冻结
- `membership_ledger_list`: 获取积分流水

## 数据库集合

- `app_users`: 用户主表
- `phone_identities`: 手机号哈希映射
- `auth_challenges`: 验证码会话
- `auth_rate_limits`: 发送频控
- `membership_subscriptions`: 会员订阅实例
- `membership_quota_buckets`: 周期积分桶 / 每日免费积分桶
- `membership_points_holds`: 积分冻结单
- `membership_points_ledger`: 积分流水
- `membership_binding_history`: 恢复购买迁移记录

## 环境变量

参考 `functions/.env.example` 和 `.env.deploy.example`：

- `TCB_ENV`
- `APP_JWT_SECRET`
- `ACCESS_TOKEN_EXPIRES_IN`
- `REFRESH_TOKEN_EXPIRES_IN`
- `ALIYUN_ACCESS_KEY_ID`
- `ALIYUN_ACCESS_KEY_SECRET`
- `PNVS_SMS_SIGN_NAME`
- `PNVS_SMS_TEMPLATE_CODE`
- `TENCENTCLOUD_SECRETID`（仅本地部署脚本使用）
- `TENCENTCLOUD_SECRETKEY`（仅本地部署脚本使用）

## 部署步骤（个人开发者版）

1. 在 CloudBase 控制台创建环境（本项目环境 ID：`gaya-cloudbase-6gq8izg8eeafd22b`）。
2. 复制环境变量模板：
   - `cp .env.deploy.example .env.deploy`
   - 在 `.env.deploy` 中填好腾讯云和阿里云密钥。
3. 安装函数依赖（本地）：
   - `npm run deps:functions`
4. 一键部署函数并绑定 HTTP 路由：
   - `npm run deploy`
5. 初始化数据库集合（自动创建认证与会员集合）：
   - `npm run init:db`
6. 配置 `.env.deploy` 的 `AUTH_API_BASE_URL`，例如：`https://<envid>-<appid>.ap-shanghai.app.tcloudbase.com`
7. 运行联调自检：
   - `npm run smoke:auth`
   - `npm run smoke:membership`

> 部署脚本位置：`scripts/deploy_cloudbase.sh`。  
> 数据库初始化脚本：`scripts/init_auth_db.sh`。  
> 联调自测脚本：`scripts/smoke_auth_http.sh`、`scripts/smoke_membership_http.sh`。  
> 函数配置文件：`cloudbaserc.json`（包含函数配置与环境变量映射）。

## 数据权限建议

- 认证集合（`app_users`、`phone_identities`、`auth_challenges`、`auth_rate_limits`）建议设置为仅云函数可读写。
- 会员集合（`membership_subscriptions`、`membership_quota_buckets`、`membership_points_holds`、`membership_points_ledger`、`membership_binding_history`）建议设置为仅云函数可读写。
- 客户端不要直连以上集合，统一走 HTTP 云函数接口。

## 常见问题

### 返回 `HTTPSERVICE_NONACTIVATED`

如果访问 `https://<env>.ap-xxx.app.tcloudbase.com/...` 返回：

```json
{"code":"HTTPSERVICE_NONACTIVATED"}
```

说明环境的 HTTP 访问服务未启用。  
命令 `tcb service switch -e <envId>` 若提示 `OperationDenied.FreePackageDenied`，表示当前套餐不支持开启 HTTP 服务，需要升级到支持 HTTP 网关的套餐后再开启。

## 请求约定

- Header 必填：`x-device-id`
- Body 必填：`agreement_accepted = true`
- 统一响应结构：

```json
{
  "code": 0,
  "message": "ok",
  "data": {}
}
```

## 接口

### POST `/auth/onetap/login`

```json
{
  "one_tap_token": "string",
  "nickname": "string",
  "agreement_accepted": true
}
```

### POST `/auth/sms/send`

```json
{
  "phone_number": "13800138000",
  "agreement_accepted": true
}
```

返回：

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "challenge_id": "uuid",
    "resend_after_seconds": 60,
    "expire_after_seconds": 600
  }
}
```

### POST `/auth/sms/verify`

```json
{
  "phone_number": "13800138000",
  "verify_code": "123456",
  "challenge_id": "uuid",
  "nickname": "",
  "agreement_accepted": true
}
```

登录成功后返回 `user + session`，结构与 `/auth/onetap/login` 一致。

## 会员联调说明

- `membership_products_list` 为公开接口，不要求登录，可用于 App 首屏拉取套餐与功能计费配置。
- 其他会员接口都要求 `Authorization: Bearer <access_token>`。
- 当前套餐与功能计费配置使用函数内置虚拟值，目的是优先跑通会员业务闭环：
  - 月卡：30 天，3600 积分
  - 季卡：90 天，12000 积分
  - 免费用户：每日 80 积分
- `npm run smoke:membership` 会自动：
  - 预置两个联调用户
  - 获取免费积分资料
  - 走一轮冻结 / 释放
  - 走一轮购买月卡
  - 走一轮冻结 / 提交
  - 校验积分流水
  - 校验恢复购买后的权益迁移

## 当前阶段说明

- 本期主用链路是“其他手机号 + 验证码登录”。
- 一键登录后端已准备好，客户端还需要接入阿里云 iOS 一键登录 SDK 才能真正拿到 `one_tap_token`。
