# Gaya - AI 伴侣

一款 iOS AI 伴侣应用，具有独特的视觉交互体验和智能记忆系统。

## 功能特性

### 核心功能
- **实时语音对话**：基于火山引擎端到端语音 API，实现自然的语音交互
- **智能记忆系统**：混合架构的对话记忆管理，让 AI 真正"记住"用户
- **记忆回廊（日记）**：按自然日自动总结用户与 AI 的交流内容，沉淀为第一人称日记列表
- **动态粒子效果**：使用 Metal 渲染的动态粒子聚簇，随 AI 语音波动
- **照片理解语音首答**：用户上传照片后，先由 Doubao 进行视觉理解，再注入语音会话触发 AI 2-3 句首答并语音播报
- **手机号登录体系**：支持本机号码一键登录（PNVS）与其他手机号验证码登录（PNVS）
- **会员前强制登录**：保留游客模式，点击会员入口时未登录用户先进入登录流程

### 视觉交互
- **深邃黑场**：应用启动时呈现纯黑背景
- **粒子效果**：粒子随 AI 语音输出实时波动，模拟数字生命的呼吸
- **交互引导**：简洁的文字提示引导用户进行语音交互
- **照片粒子化**：上传图片后生成可交互的粒子化图像，支持实时参数调节

## 技术架构

### 技术栈
- SwiftUI
- Metal（高性能图形渲染）
- 火山引擎实时语音 API（ASR + LLM + TTS）
- Doubao Seed API（Ark Responses，记忆调度/多模态预留）
- NaturalLanguage（本地文本嵌入）
- SQLite（向量存储）
- Vision（可选前景分割，自动回退全图）
- CloudBase（云函数 + 数据库）
- 阿里云号码认证 PNVS（本机号认证 + 短信验证码）
- iOS 17.0+

### 登录与会员门禁架构（新增）

```
游客态
  │
  ├─ 普通聊天/记忆体验：允许
  │
  └─ 点击会员计划
        │
        ▼
   AuthLoginFlowView（登录页）
        │
        ├─ 本机号码一键登录（PNVS token -> CloudBase 函数 -> 会话）
        └─ 其他手机号验证码登录（发送验证码 -> 校验 -> 会话）
        │
        ▼
   登录成功后回跳会员入口（本期会员支付链路预留）
```

- 后端落在 `backend/cloudbase/functions`，通过 CloudBase HTTP 云函数提供认证接口。
- 用户登录成功后，客户端会把本地记忆存储切换到该用户命名空间；游客态使用 `guest` 命名空间。
- 本期已接入验证码登录链路；本机号一键登录在客户端提供了 UI 和接口，仍需接入阿里云 iOS 一键登录 SDK 才可实际调用。

### 混合记忆系统架构

```
┌──────────────────────────────────────────────────────────────────┐
│                      Path A (主路 - 实时对话)                      │
│  用户语音 ──► 火山引擎实时语音 API ──► AI 语音输出                  │
│              (ASR + LLM + TTS 一体化)                              │
└──────────────────────────────────────────────────────────────────┘
                              ▲
                              │ 注入相关记忆（system_role）
                              │
┌──────────────────────────────────────────────────────────────────┐
│                    Path B (监控路 - 混合检索)                      │
│                                                                    │
│  ASR 转写文本 ──► 混合检索策略 ──────────────────────────────────  │
│                        │                                           │
│          ┌─────────────┴─────────────┐                            │
│          ▼                           ▼                            │
│    本地向量检索                 Doubao 精排                        │
│    (NaturalLanguage)           (语义理解)                         │
│          │                           │                            │
│          └─────────────┬─────────────┘                            │
│                        ▼                                           │
│              相关记忆 + 上下文                                     │
└──────────────────────────────────────────────────────────────────┘
                              ▲
                              │ 图片理解注入（ChatTextQuery）
                              │
┌──────────────────────────────────────────────────────────────────┐
│                 Path C (照片理解 - 语音首答)                      │
│  用户上传照片 ─► Doubao 多模态理解 ─► 注入为用户文本输入          │
│                              └────► 火山引擎 LLM+TTS 语音首答     │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                     本地存储层                                     │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  JSON 持久化                                                │  │
│  │  用户画像 │ 短期记忆(5轮) │ 长期记忆(100条) │ 重要性评分      │  │
│  └────────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  SQLite 向量存储                                            │  │
│  │  文本嵌入向量 │ 余弦相似度检索 │ 语义搜索                     │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### system_role 上下文结构

```
┌─────────────────────────────────────────────────────────────┐
│                        system_role                          │
├─────────────────────────────────────────────────────────────┤
│  [固定] 角色设定 (~1500 字符)                                │
│         - Gaya 的核心身份和性格特质                          │
├─────────────────────────────────────────────────────────────┤
│  [固定] 用户画像 (~200 字符)                                 │
│         - 姓名、爱好、偏好、重要人物                         │
├─────────────────────────────────────────────────────────────┤
│  [固定] 最近 2 轮对话 (~500 字符)                            │
│         - 短期记忆中的最新对话                               │
├─────────────────────────────────────────────────────────────┤
│  [动态] Doubao 检索的相关记忆 (~500 字符)                    │
│         - 根据当前话题语义匹配                               │
│         - 可能为空（如果不需要）                             │
└─────────────────────────────────────────────────────────────┘
```

### 照片理解注入语音对话（新增实现）

#### 目标
- 上传成功后，AI 先对照片做较详细解读（2-3 句）并语音输出。
- 之后用户继续按住说话，可围绕该照片持续对话。
- 支持“关闭后重传/连续上传”，不锁死在首次上传照片。

#### 端到端链路
1. `ContentView` 选图成功后生成 `requestID`，并打开拍立得页面。
2. `PhotoEmotionCaptionService` 并行生成：
   - 拍立得短文案（10字内，UI 展示）
   - 对话注入文本（含场景/细节/氛围，供语音会话使用）
3. 优先提交对话注入文本：`VoiceService.submitPhotoUnderstandingAsUserInput(...)`。
4. `VoiceService` 自动保障连接与 Session：
   - 未连接则建连
   - 未建 Session 则建 Session
   - 已有 Session 则直接发 `ChatTextQuery`
5. 短文案结果稍后回写到拍立得 UI（不阻塞语音首答）。
6. 火山引擎按现有链路完成 LLM + TTS，AI 播报首答。
7. `saveConversationTurn()` 复用现有记忆逻辑：
   - 先进入短期记忆
   - 按重要性阈值晋升到长期记忆

#### 关闭/重传策略
- `ContentView` 使用 `requestID` 防串线：旧上传任务完成时若 `requestID` 已失效，结果直接丢弃。
- 关闭拍立得时调用 `VoiceService.clearPendingInjectedQueries(cancelInFlight: true)`，清理未发送任务并终止正在播报的图片注入首答。
- 重新上传会生成新的 `requestID`，并触发新的照片理解与语音首答流程。

### 记忆回廊（日记）实现

#### 功能定义
- 记忆回廊以“天”为粒度管理日记，每天一条总结。
- 总结内容来自当天用户与 AI 的真实对话（过滤系统注入文本 `isInjectedQuery`）。
- 日记要求第一人称叙述，突出情绪与关键事件，正文不超过 1000 字，标题不超过 10 字。

#### 调度与补偿
1. App 进入活跃态后，自动确保当天草稿任务存在（时间窗 `00:00:01-23:59:59`）。
2. 每轮真实对话在 `VoiceService.saveConversationTurn()` 内同步写入当天草稿。
3. 每天 `23:59:59` 触发封账，调用 Doubao 生成 `title + content`，入库到回廊列表。
4. 若 `23:59:59` 时 App 不活跃，则在下次回到 active 时自动补封账。
5. 当天没有任何对话时，跳过该天，不生成空日记。

#### 展示规则
- 回廊列表按创建时间顺序（升序）展示。
- 单条日记卡片宽度自适应屏幕，左右留白 10px，底部留白 20px。
- 卡片高度占屏幕约 60%，超出正文在卡片内滚动。
- 卡片采用“双画布”：顶部画布展示标题+日期，底部画布展示正文+底部占位按钮。

## 照片粒子化架构

### 管线概览
1. **图片预处理**：用户上传图片后进行归一化与降采样，必要时使用 Vision 生成前景蒙版，若前景占比过低则回退为全图蒙版。
2. **Compute 生成粒子**：Metal Compute Kernel 根据颜色纹理与蒙版，生成粒子的目标位置、深度、大小与颜色。
3. **实时渲染与动画**：Metal 顶点/片元着色器对粒子施加流场、离散、深度波与音频律动，并做加法混合。
4. **SwiftUI 控制层**：右侧控制面板实时调整粒子参数，拖拽手势驱动局部扰动（鼠标半径）。

### 可调参数
- Dispersion / Particle Size / Contrast
- Flow Speed / Flow Amplitude
- Depth Strength / Depth Wave
- Mouse Radius
- Color Shift Speed
- Audio Dance / Dance Strength

## 项目结构

```
gaya/
├── Podfile                 # CocoaPods 依赖（ATAuthSDK）
├── Pods/                   # CocoaPods 产物
├── gaya.xcworkspace/       # 使用该 workspace 打开并构建
├── gaya.xcodeproj/          # Xcode 项目文件
├── gaya/
│   ├── gayaApp.swift        # 应用入口
│   ├── AudioManager.swift   # 音频权限管理
│   │
│   ├── Services/            # 服务层
│   │   ├── VoiceService.swift         # 语音服务（火山引擎 API）
│   │   ├── VolcEngineConfig.swift     # 火山引擎配置
│   │   ├── MemoryStore.swift          # 本地分层记忆 + 记忆回廊存储/总结服务
│   │   ├── DeepSeekOrchestrator.swift # Doubao(Ark) 记忆调度服务
│   │   ├── PhotoEmotionCaptionService.swift # 照片短文案与对话注入文本生成
│   │   ├── LocalEmbedding.swift       # 本地文本嵌入模型
│   │   └── VectorStore.swift          # SQLite 向量存储
│   │
│   ├── Models/              # 数据模型
│   │   └── MemoryModels.swift         # 记忆系统 + 记忆回廊数据模型
│   │
│   ├── Views/               # 视图层
│   │   ├── ContentView.swift          # 主视图 + 记忆回廊页面
│   │   ├── VoiceInputControl.swift    # 语音输入复用组件（提示+按住说话）
│   │   ├── ParticleView.swift         # 粒子视图容器
│   │   └── ParticleRenderer.swift     # Metal 渲染器
│   │   ├── PhotoControlPanel.swift    # 照片粒子控制面板
│   │   ├── PhotoInteractionLayer.swift# 照片粒子交互层
│   │   └── PhotoParticleSettings.swift# 参数模型与映射
│   │
│   ├── Shaders/             # Metal 着色器
│   │   └── Shaders.metal              # 粒子渲染着色器
│   │
│   ├── Tests/               # 测试文件
│   │   └── MemorySystemTests.swift    # 记忆系统测试用例
│   │   └── PhotoParticleTests.swift   # 粒子参数映射测试
│   │
│   └── Assets.xcassets/     # 资源文件
│
├── backend/
│   └── cloudbase/            # 认证后端（云函数 + 配置说明）
│       ├── README.md
│       └── functions/
│           ├── auth_db_init/
│           ├── auth_onetap_login/
│           ├── auth_sms_send/
│           ├── auth_sms_verify/
│           ├── user_bootstrap/
│           └── common/
│
├── python3.7/               # Python 参考实现
│   ├── realtime_dialog_client.py  # 火山引擎 API 示例
│   └── config.py                  # API 配置示例
│
└── README.md                # 项目文档
```

## 记忆系统详解

### 分层记忆架构

| 记忆层级 | 容量 | 内容 | 特点 |
|---------|------|------|------|
| 短期记忆 | 5 轮 | 完整对话文本 | 始终包含在上下文中 |
| 长期记忆 | 100 条 | 重要对话（带评分） | 按需语义检索 |
| 用户画像 | 1 份 | 用户信息提取 | 始终包含，持久存储 |

### 重要性评分规则

- **情感关键词**（+0.15）：喜欢、讨厌、爱、恨、开心、难过...
- **个人信息**（+0.12）：我叫、我的、我妈、我朋友...
- **重要事件**（+0.20）：生日、住院、去世、结婚、毕业...
- **长对话**（+0.05~0.10）：超过 50/100 字的对话

### 向量检索系统

#### 本地文本嵌入 (LocalEmbedding)
- 使用 Apple NaturalLanguage 框架
- 支持中英文混合文本
- 生成 512 维词向量
- 完全离线运行，无网络依赖

#### SQLite 向量存储 (VectorStore)
- 基于 SQLite 的轻量级向量数据库
- 支持余弦相似度计算
- 自动索引管理
- 持久化存储在 Documents 目录

#### 混合检索策略
```
用户查询
    │
    ▼
┌─────────────────┐
│  本地向量检索    │ ◄── 快速、离线
└────────┬────────┘
         │
    相似度判断
         │
    ┌────┴────┐
    │         │
    ▼         ▼
 高置信度   低置信度
 (>0.7)    (<0.7)
    │         │
    ▼         ▼
 直接使用   Doubao 精排
    │         │
    └────┬────┘
         │
         ▼
    返回最相关记忆
```

### Doubao 记忆调度

Doubao 作为"记忆调度员"负责：
1. **精排候选记忆**：对向量检索结果进行语义精排
2. **判断是否需要检索**：分析用户输入是否涉及历史话题
3. **信息提取**：从对话中提取用户姓名、爱好、重要人物等
4. **情感分析**：识别用户当前的情绪状态

### 快速检查规则

在调用 Doubao API 前，先进行本地快速判断：
- 包含指代词（那个、之前、她、他）→ 需要检索
- 包含延续词（然后呢、后来、接着）→ 需要检索
- 简单问候（你好、早上好）→ 不需要检索

## 开发说明

### 环境要求
- Xcode 15.0+
- iOS 17.0+
- 有效的火山引擎 API 密钥
- 有效的 Ark API 密钥
- CloudBase 云开发环境（用于认证云函数与数据库）
- 阿里云 PNVS 开通（号码认证服务 + 短信验证码能力）

### 配置步骤

1. 在 `VolcEngineConfig.swift` 中配置火山引擎 API：
```swift
static let appId = "your_app_id"
static let accessKey = "your_access_key"
static let resourceId = "your_resource_id"
```

2. 在 `DeepSeekOrchestrator.swift` 中配置 Doubao/Ark API（支持环境变量或 Info.plist）：
```swift
// 环境变量优先：ARK_API_KEY / ARK_MODEL / ARK_BASE_URL
// 或在 Info.plist 中配置同名字段
```

3. 部署 CloudBase 认证后端（目录：`backend/cloudbase`）：
```bash
cd backend/cloudbase
cp .env.deploy.example .env.deploy
# 编辑 .env.deploy，填入腾讯云与阿里云密钥
npm install
npm run deps:functions
npm run deploy
npm run init:db
npm run smoke:auth
```
- `TCB_ENV` 填：`gaya-cloudbase-6gq8izg8eeafd22b`
- `.env.deploy` 里补充 `AUTH_API_BASE_URL=https://你的-cloudbase-http-域名`（用于 `npm run smoke:auth`）
- `npm run deploy` 会自动部署函数并绑定 HTTP 路由：
  - `auth/onetap/login`
  - `auth/sms/send`
  - `auth/sms/verify`
  - `user/bootstrap`
- `npm run init:db` 会自动初始化认证所需集合：`app_users`、`phone_identities`、`auth_challenges`、`auth_rate_limits`
- 若接口访问返回 `HTTPSERVICE_NONACTIVATED`，需在 CloudBase 控制台开启 HTTP 服务；若提示 `OperationDenied.FreePackageDenied`，需升级到支持 HTTP 网关的套餐。

4. 在 iOS 端 `Info.plist`（或 Target 的自定义 Info）中配置认证接口地址：
```xml
<key>AUTH_API_BASE_URL</key>
<string>https://你的-cloudbase-http-域名</string>
<key>AUTH_SMS_SEND_PATH</key>
<string>/auth/sms/send</string>
<key>AUTH_SMS_VERIFY_PATH</key>
<string>/auth/sms/verify</string>
<key>AUTH_ONETAP_LOGIN_PATH</key>
<string>/auth/onetap/login</string>
```

5. 安装 iOS 依赖并通过 workspace 构建：
```bash
pod install
xcodebuild -workspace gaya.xcworkspace -scheme gaya -configuration Debug build
```

6. 一键登录 SDK 接入说明：
- 当前项目已通过 CocoaPods 集成 `ATAuthSDK`。
- 若点击“一键登录”仍提示 SDK 未接入，请确认执行过 `pod install`，并且是从 `gaya.xcworkspace` 打开的工程。
- 当前接入的 `ATAuthSDK` 方案不再强制依赖 `ALIYUN_PNVS_AUTH_SDK_INFO`；如你后续切换到需显式初始化串的 SDK 版本，再补该键位即可。
- 若构建报 `Sandbox: bash(...) deny file-write-create Pods/resources-to-copy-gaya.txt`，执行 `pod install` 后重开工程；`Podfile` 已自动设置 `ENABLE_USER_SCRIPT_SANDBOXING = NO`。

### 测试记忆系统

在开发阶段，可以调用测试方法验证记忆系统：

```swift
// 运行所有测试
Task {
    await MemorySystemTests.shared.runAllTests()
}

// 模拟对话场景
Task {
    await MemorySystemTests.shared.simulateConversationScenario()
}

// 查看当前记忆状态
MemorySystemTests.shared.printMemoryStatus()
```

### 认证链路自测清单

1. 游客启动 App，不登录，确认可以正常对话与记忆。
2. 点击“会员计划”，确认会弹出登录页（而非直接进入会员页）。
3. 在验证码登录页输入手机号，获取验证码并登录：
- 未注册手机号应自动注册并登录。
- 已注册手机号应直接登录并刷新最近登录时间。
4. 登录成功后，重启 App，确认会话状态可恢复（过期会话会自动回退游客态）。
5. 不同账号分别登录，确认本地记忆文件按命名空间隔离（`gaya_memory_<namespace>.json` / `gaya_vectors_<namespace>.sqlite` / `gaya_memory_corridor_<namespace>.json`）。

## 视觉效果

- 3000 个粒子组成的动态聚簇
- 粒子随 AI 语音实时波动
- 有机的"呼吸"效果 + 液态表面湍流
- 颜色从平静蓝到活跃粉的渐变

## 更新日志

### v1.4.3 - 修复 iOS 兼容模式导致的页面变形

**问题现象**：粒子球体被压缩变形、中心区域过度明亮，UI 布局比例异常。

**根因分析**：

项目的 `project.pbxproj` 在初始化时由脚本生成（UID 为顺序递增的 `A1000001...` 格式，而非 Xcode 原生随机 hex），遗漏了关键配置项 `INFOPLIST_KEY_UILaunchScreen_Generation = YES`。

缺少此配置后，iOS 将 app 运行在 **320×480 兼容模式**（iPhone 4 分辨率），然后放大填充全屏。导致：
- `UIScreen.main.bounds` 返回 320×480 而非设备真实分辨率（如 iPhone 17 的 ≈393×852）
- Metal 渲染区域被压缩至实际屏幕的约 1/4，粒子在更小空间内叠加导致中心过亮
- 所有 SwiftUI 布局计算基于错误的屏幕尺寸，UI 比例变形

**诊断关键**：通过在 `ParticleRenderer.draw(in:)` 中添加一次性日志，捕获到：
```
viewport=(960.0, 1440.0) bounds=(320.0, 480.0) screen=(320.0, 480.0) native=(960.0, 1440.0) scale=3.0
```
`screen` 与 `native / scale` 不匹配（应为 320×480 × 3 = 960×1440 但真机屏幕并非 320×480），确认了兼容模式问题。

同时 Xcode 构建时一直存在对应警告：
```
warning: A launch configuration or launch storyboard or xib must be provided unless the app requires full screen.
```

**修复方案**：在 `project.pbxproj` 的 Debug 和 Release buildSettings 中补齐：
```
INFOPLIST_KEY_UILaunchScreen_Generation = YES;
INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationLandscapeLeft ...";
```

**经验总结**：
1. 不要让 AI/脚本整体重新生成 `project.pbxproj`，应在 Xcode GUI 中操作或做精确局部修改
2. 重大项目结构变更后必须在**真机**上全新安装验证（模拟器对 LaunchScreen 要求较松）
3. 关注并消除所有 Xcode 构建警告，尤其涉及 `launch`、`safe area`、`interface orientation` 的

### v1.4.2 - 认证数据库自动初始化与联调脚本
- ✅ 新增 `auth_db_init` 云函数（自动初始化 `app_users` / `phone_identities` / `auth_challenges` / `auth_rate_limits`）
- ✅ 新增 `npm run init:db` 一键初始化数据库集合
- ✅ 新增 `npm run smoke:auth` HTTP 路由联调自检脚本
- ✅ 修复 CloudBase 路由部署脚本的路径兼容问题，避免 `Path already exists` 脏路由阻塞

### v1.4.1 - CloudBase 自动化部署与阿里云一键登录 SDK 接入
- ✅ 新增 `backend/cloudbase/cloudbaserc.json` 与一键部署脚本（`npm run deploy`）
- ✅ 支持通过 `.env.deploy` 注入云函数环境变量与密钥
- ✅ iOS 新增阿里云一键登录 SDK Provider（`TXCommonHandler` 接入）
- ✅ 在 Xcode Build Settings 中补齐认证相关 Info.plist 键位（含 `ALIYUN_PNVS_AUTH_SDK_INFO`）

### v1.4.0 - CloudBase 认证后端与手机号登录接入
- ✅ 新增 CloudBase 认证后端骨架（`auth_sms_send` / `auth_sms_verify` / `auth_onetap_login` / `user_bootstrap`）
- ✅ 接入阿里云 PNVS 服务调用封装（本机号认证 + 短信验证码）
- ✅ iOS 新增登录全屏页（本机号一键登录 + 其他手机号验证码登录），UI 对齐设计稿风格
- ✅ 新增“游客可用、会员前强制登录”门禁逻辑
- ✅ 本地记忆/向量库/记忆回廊按登录用户命名空间隔离

### v1.3.1 - 语音输入组件复用与页面控件统一
- ✅ 新增 `VoiceInputControl` 复用组件，封装语音提示文案 + 按住说话按钮，后续可全项目统一调整
- ✅ 初始粒子页与拍立得页统一复用该组件，语音输入在 Y 轴高度保持一致
- ✅ 粒子页“选择照片”按钮调整到右上角，并由长条样式改为圆角方形 icon
- ✅ 拍立得页“保存”按钮调整到右上角，位置与 icon 样式与“选择照片”保持统一

### v1.3.0 - Doubao API 替换与多模态预埋
- ✅ 记忆调度 API 由 DeepSeek 切换为 Doubao Seed (`doubao-seed-1-8-251228`)
- ✅ 底层请求切换到 Ark Responses (`/api/v3/responses`)
- ✅ 保持原有记忆存储架构（短期/长期/用户画像/向量库）不变
- ✅ 新增多模态输入结构预留（文本/图片 URL/视频 URL）

### v1.2.0 - 向量检索增强
- ✅ 实现本地文本嵌入（NaturalLanguage）
- ✅ SQLite 向量存储和检索
- ✅ 混合检索策略（向量 + DeepSeek）
- ✅ 余弦相似度语义搜索
- ✅ 完善测试用例

### v1.1.0 - 混合记忆系统
- ✅ 实现分层记忆存储（短期/长期/用户画像）
- ✅ 集成 DeepSeek 智能记忆调度
- ✅ 本地 JSON 持久化存储
- ✅ 自动用户信息提取
- ✅ 重要性评分和记忆整合

### v1.0.0 - 基础功能
- ✅ 火山引擎实时语音对话
- ✅ Metal 粒子效果渲染
- ✅ 性别识别和音色切换
- ✅ 基础对话上下文管理

## License

MIT License
