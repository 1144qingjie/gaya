# CloudBase 认证后端（阿里云 PNVS）

本目录是手机号登录后端实现，运行在 CloudBase 云函数。

## 目标

- 支持本机号码一键登录（PNVS 一键登录 token 换号）
- 支持其他手机号验证码登录（发送码 + 校验）
- 未注册手机号首次验证通过后自动创建用户
- 返回 App 会话令牌（access_token / refresh_token）

## 云函数清单

- `auth_db_init`: 初始化认证相关数据库集合（仅运维调用，不绑定 HTTP 路由）
- `auth_onetap_login`: 校验 PNVS 一键登录 token 并登录
- `auth_sms_send`: 发送短信验证码
- `auth_sms_verify`: 校验验证码并登录
- `user_bootstrap`: 更新用户昵称（可选）

## 数据库集合

- `app_users`: 用户主表
- `phone_identities`: 手机号哈希映射
- `auth_challenges`: 验证码会话
- `auth_rate_limits`: 发送频控

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
5. 初始化认证数据库集合（自动创建 4 个集合）：
   - `npm run init:db`
6. 配置 `.env.deploy` 的 `AUTH_API_BASE_URL`，例如：`https://<envid>-<appid>.ap-shanghai.app.tcloudbase.com`
7. 运行联调自检：
   - `npm run smoke:auth`

> 部署脚本位置：`scripts/deploy_cloudbase.sh`。  
> 数据库初始化脚本：`scripts/init_auth_db.sh`。  
> 联调自测脚本：`scripts/smoke_auth_http.sh`。  
> 函数配置文件：`cloudbaserc.json`（包含函数配置与环境变量映射）。

## 数据权限建议

- 认证集合（`app_users`、`phone_identities`、`auth_challenges`、`auth_rate_limits`）建议设置为仅云函数可读写。
- 客户端不要直连这 4 个集合，统一走 HTTP 云函数接口。

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

## 当前阶段说明

- 本期主用链路是“其他手机号 + 验证码登录”。
- 一键登录后端已准备好，客户端还需要接入阿里云 iOS 一键登录 SDK 才能真正拿到 `one_tap_token`。
