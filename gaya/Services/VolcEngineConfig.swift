import Foundation

/// 火山引擎端到端语音大模型配置
struct VolcEngineConfig {
    // MARK: - 账号鉴权（火山引擎自定义 Header 方式）
    static let appId = Secrets.volcAppId
    static let accessKey = Secrets.volcAccessKey
    static let secretKey = Secrets.volcSecretKey
    
    // MARK: - 应用配置
    static let resourceId = "volc.speech.dialog"
    static let appKey = Secrets.volcAppKey
    
    // MARK: - 音色配置（端到端 TTS Speaker）
    
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
    /// 注意：需要账户开通联网搜索权限，否则会返回"联网服务暂时不可用"
    static let enableWebSearch: Bool = false

    // MARK: - 融合信息搜索（WebSearch）配置
    static let webSearchApiKey: String = Secrets.volcWebSearchApiKey

    static let webSearchAccessKey: String = accessKey
    static let webSearchSecretKey: String = secretKey

    /// OpenAPI Endpoint & Service
    static let webSearchEndpoint: String = "https://mercury.volcengineapi.com"
    static let webSearchService: String = "volc_torchlight_api"
    static let webSearchRegion: String = "cn-north-1"
    static let webSearchAction: String = "WebSearch"
    static let webSearchVersion: String = "2025-01-01"

    static let webSearchDefaultType: String = "web"
}
