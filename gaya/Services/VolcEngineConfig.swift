import Foundation

/// 火山引擎端到端语音大模型配置
struct VolcEngineConfig {
    // MARK: - 账号鉴权（火山引擎自定义 Header 方式）
    static let appId = "1088265138"
    static let accessKey = "2wESPPfpffW7eR2H2SlSzqvCnxy8rQPY"  // X-Api-Access-Key
    static let secretKey = "RxHLRdjjeICBzrR-HE3PrxZEdPuzoFH5"  // 备用
    
    // MARK: - 应用配置
    static let resourceId = "volc.speech.dialog"  // 固定值
    static let appKey = "PlgvMymc7f3tQnJ6"        // 固定值
    
    // MARK: - 音色配置（端到端 TTS Speaker）
    // 端到端模型可直接通过 tts.speaker 指定发音人（与官方 realtime demo 一致）
    
    /// 女性音色（备用）
    static let femaleVoiceId = "zh_female_vv_jupiter_bigtts"
    
    /// 男性音色（当前固定使用）
    static let maleVoiceId = "zh_male_yunzhou_jupiter_bigtts"
    
    /// 默认音色（首次对话/性别未识别时使用）
    static let defaultVoiceId = maleVoiceId
    
    // MARK: - WebSocket 配置
    static let wsURL = "wss://openspeech.bytedance.com/api/v3/realtime/dialogue"
    
    // MARK: - 输入音频配置
    static let inputSampleRate: Int = 16000
    static let inputChannels: Int = 1
    static let inputChunkSize: Int = 3200
    
    // MARK: - 输出音频配置
    static let outputSampleRate: Int = 24000
    static let outputChannels: Int = 1
    
    // MARK: - 联网搜索配置
    /// 是否启用火山引擎联网搜索功能
    /// 注意：需要账户开通联网搜索权限，否则会返回"联网服务暂时不可用"
    static let enableWebSearch: Bool = false

    // MARK: - 融合信息搜索（WebSearch）配置
    /// 融合信息搜索 API Key（来自“API Key 管理 - 融合信息搜索”）
    /// 若使用 API Key 接入，请填写此项
    static let webSearchApiKey: String = "wd2oUf7vvSlrv9iufl0uuD8jD0dtwlO8"

    /// 使用火山引擎统一 OpenAPI 的 AK/SK 鉴权
    /// 如果与你的语音服务 AK/SK 不同，请在此替换
    static let webSearchAccessKey: String = accessKey
    static let webSearchSecretKey: String = secretKey

    /// OpenAPI Endpoint & Service
    static let webSearchEndpoint: String = "https://mercury.volcengineapi.com"
    /// OpenAPI ServiceName（联网问答Agent 文档：volc_torchlight_api）
    static let webSearchService: String = "volc_torchlight_api"
    static let webSearchRegion: String = "cn-north-1"
    static let webSearchAction: String = "WebSearch"
    static let webSearchVersion: String = "2025-01-01"

    /// 默认搜索类型（根据查询内容可在运行时调整）
    /// 取值需与服务端定义一致，常见为 web/news
    static let webSearchDefaultType: String = "web"
}
