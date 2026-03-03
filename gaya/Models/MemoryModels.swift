//
//  MemoryModels.swift
//  gaya
//
//  混合记忆系统 - 数据模型定义
//

import Foundation

// MARK: - 记忆条目
/// 单条记忆的数据结构
struct Memory: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let userText: String           // 用户说的话
    let aiText: String             // AI 的回复
    var summary: String?           // 摘要（用于长期记忆压缩）
    var emotionalTag: EmotionalTag? // 情感标签
    var topicTags: [String]        // 话题标签
    var importance: Float          // 重要性评分 0-1
    var accessCount: Int           // 被检索次数（用于衰减计算）
    var lastAccessTime: Date?      // 最后访问时间
    
    init(
        userText: String,
        aiText: String,
        summary: String? = nil,
        emotionalTag: EmotionalTag? = nil,
        topicTags: [String] = [],
        importance: Float = 0.5
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.userText = userText
        self.aiText = aiText
        self.summary = summary
        self.emotionalTag = emotionalTag
        self.topicTags = topicTags
        self.importance = importance
        self.accessCount = 0
        self.lastAccessTime = nil
    }
    
    /// 获取记忆的简短描述（用于展示和检索）
    var briefDescription: String {
        if let summary = summary, !summary.isEmpty {
            return summary
        }
        let maxLength = 100
        let userPart = userText.prefix(maxLength / 2)
        let aiPart = aiText.prefix(maxLength / 2)
        return "用户:\(userPart)... AI:\(aiPart)..."
    }
    
    /// 计算记忆的时效性权重（越新越重要）
    var recencyWeight: Float {
        let hoursSinceCreation = Date().timeIntervalSince(timestamp) / 3600
        // 24小时内权重为1，之后逐渐衰减
        return max(0.1, 1.0 - Float(hoursSinceCreation / 168)) // 一周后衰减到最低
    }
    
    /// 综合评分（重要性 × 时效性）
    var compositeScore: Float {
        return importance * recencyWeight
    }
}

// MARK: - 情感标签
enum EmotionalTag: String, Codable, CaseIterable {
    case happy = "开心"
    case sad = "难过"
    case anxious = "焦虑"
    case angry = "生气"
    case curious = "好奇"
    case grateful = "感激"
    case lonely = "孤独"
    case excited = "兴奋"
    case neutral = "平静"
    case supportive = "需要支持"
    
    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .sad: return "😢"
        case .anxious: return "😰"
        case .angry: return "😠"
        case .curious: return "🤔"
        case .grateful: return "🙏"
        case .lonely: return "😔"
        case .excited: return "🎉"
        case .neutral: return "😌"
        case .supportive: return "🤗"
        }
    }
}

// MARK: - 用户画像
/// 从对话中提取的用户信息（专业版）
struct UserProfile: Codable {
    // MARK: - 基础信息
    var name: String?                      // 用户姓名
    var gender: Gender?                    // 用户性别
    var age: Int?                          // 年龄
    var location: LocationInfo?            // 地理位置信息
    var occupation: String?                 // 职业
    var education: String?                  // 教育背景
    
    // MARK: - 兴趣与偏好
    var hobbies: [String]                  // 兴趣爱好
    var interests: [String]                // 兴趣领域（更广泛）
    var preferences: [String: String]      // 偏好设置 (如: ["音乐": "爵士", "食物": "辣"])
    var dislikes: [String]                 // 不喜欢的事物
    
    // MARK: - 社交关系
    var importantPeople: [PersonInfo]      // 重要人物
    var relationshipStatus: String?        // 关系状态（单身/恋爱/已婚等）
    
    // MARK: - 生活状态
    var lifestyle: LifestyleInfo?          // 生活方式
    var workInfo: WorkInfo?                // 工作信息
    var healthInfo: HealthInfo?           // 健康信息
    
    // MARK: - 心理特征
    var personalityTraits: [String]        // 性格特质
    var values: [String]                   // 价值观
    var goals: [String]                    // 目标/愿望
    var emotionalBaseline: EmotionalTag?   // 情绪基线
    var communicationStyle: String?        // 沟通风格
    
    // MARK: - 行为模式
    var conversationTopics: [String]       // 常聊话题
    var activeTimePattern: String?         // 活跃时间模式
    
    // MARK: - 其他信息
    var facts: [String]                    // 关于用户的事实
    var memorableMoments: [String]          // 难忘时刻
    var concerns: [String]                 // 担忧/困扰
    var achievements: [String]             // 成就/里程碑
    
    // MARK: - 元数据
    var lastUpdated: Date                  // 最后更新时间
    var profileCompleteness: Float          // 画像完整度 0-1
    var confidenceScores: [String: Float]  // 各字段的置信度
    
    init() {
        self.hobbies = []
        self.interests = []
        self.preferences = [:]
        self.dislikes = []
        self.importantPeople = []
        self.personalityTraits = []
        self.values = []
        self.goals = []
        self.conversationTopics = []
        self.facts = []
        self.memorableMoments = []
        self.concerns = []
        self.achievements = []
        self.lastUpdated = Date()
        self.profileCompleteness = 0.0
        self.confidenceScores = [:]
    }
    
    var isEmpty: Bool {
        return name == nil && hobbies.isEmpty && preferences.isEmpty && facts.isEmpty &&
               interests.isEmpty && personalityTraits.isEmpty && goals.isEmpty
    }
    
    /// 计算画像完整度
    mutating func calculateCompleteness() {
        var filledFields = 0
        var totalFields = 0
        
        // 基础信息
        totalFields += 6
        if name != nil { filledFields += 1 }
        if gender != nil { filledFields += 1 }
        if age != nil { filledFields += 1 }
        if location != nil { filledFields += 1 }
        if occupation != nil { filledFields += 1 }
        if education != nil { filledFields += 1 }
        
        // 兴趣与偏好
        totalFields += 4
        if !hobbies.isEmpty { filledFields += 1 }
        if !interests.isEmpty { filledFields += 1 }
        if !preferences.isEmpty { filledFields += 1 }
        if !dislikes.isEmpty { filledFields += 1 }
        
        // 社交关系
        totalFields += 2
        if !importantPeople.isEmpty { filledFields += 1 }
        if relationshipStatus != nil { filledFields += 1 }
        
        // 生活状态
        totalFields += 3
        if lifestyle != nil { filledFields += 1 }
        if workInfo != nil { filledFields += 1 }
        if healthInfo != nil { filledFields += 1 }
        
        // 心理特征
        totalFields += 5
        if !personalityTraits.isEmpty { filledFields += 1 }
        if !values.isEmpty { filledFields += 1 }
        if !goals.isEmpty { filledFields += 1 }
        if emotionalBaseline != nil { filledFields += 1 }
        if communicationStyle != nil { filledFields += 1 }
        
        profileCompleteness = Float(filledFields) / Float(totalFields)
    }
    
    /// 转换为自然语言描述（用于 system_role）- 专业版
    func toNaturalLanguage() -> String {
        var sections: [String] = []
        
        // 1. 基础身份信息
        var identityParts: [String] = []
        if let name = name {
            identityParts.append("名字是\(name)")
        }
        if let age = age {
            identityParts.append("\(age)岁")
        }
        if let gender = gender {
            identityParts.append("性别\(gender.rawValue)")
        }
        if let occupation = occupation {
            identityParts.append("职业是\(occupation)")
        }
        if let location = location {
            identityParts.append("在\(location.city ?? location.country ?? "")")
        }
        if !identityParts.isEmpty {
            sections.append("【基础信息】\(identityParts.joined(separator: "，"))")
        }
        
        // 2. 兴趣与偏好
        var interestParts: [String] = []
        if !hobbies.isEmpty {
            interestParts.append("爱好：\(hobbies.joined(separator: "、"))")
        }
        if !interests.isEmpty {
            interestParts.append("感兴趣：\(interests.joined(separator: "、"))")
        }
        if !preferences.isEmpty {
            let prefStrings = preferences.map { "\($0.key)：\($0.value)" }
            interestParts.append("偏好：\(prefStrings.joined(separator: "，"))")
        }
        if !dislikes.isEmpty {
            interestParts.append("不喜欢：\(dislikes.joined(separator: "、"))")
        }
        if !interestParts.isEmpty {
            sections.append("【兴趣偏好】\(interestParts.joined(separator: "；"))")
        }
        
        // 3. 性格与价值观
        var personalityParts: [String] = []
        if !personalityTraits.isEmpty {
            personalityParts.append("性格特点：\(personalityTraits.joined(separator: "、"))")
        }
        if !values.isEmpty {
            personalityParts.append("价值观：\(values.joined(separator: "、"))")
        }
        if let style = communicationStyle {
            personalityParts.append("沟通风格：\(style)")
        }
        if !personalityParts.isEmpty {
            sections.append("【性格特征】\(personalityParts.joined(separator: "；"))")
        }
        
        // 4. 目标与愿望
        if !goals.isEmpty {
            sections.append("【目标愿望】\(goals.joined(separator: "；"))")
        }
        
        // 5. 重要人物
        if !importantPeople.isEmpty {
            let peopleStrings = importantPeople.prefix(5).map { $0.description }
            sections.append("【重要人物】\(peopleStrings.joined(separator: "；"))")
        }
        
        // 6. 生活状态
        var lifeParts: [String] = []
        if let lifestyle = lifestyle {
            lifeParts.append(lifestyle.description)
        }
        if let work = workInfo {
            lifeParts.append(work.description)
        }
        if !lifeParts.isEmpty {
            sections.append("【生活状态】\(lifeParts.joined(separator: "；"))")
        }
        
        // 7. 重要事实与记忆
        if !facts.isEmpty {
            sections.append("【重要事实】\(facts.prefix(5).joined(separator: "；"))")
        }
        if !memorableMoments.isEmpty {
            sections.append("【难忘时刻】\(memorableMoments.prefix(3).joined(separator: "；"))")
        }
        
        // 8. 当前关注
        if !concerns.isEmpty {
            sections.append("【当前关注】\(concerns.prefix(3).joined(separator: "；"))")
        }
        
        return sections.isEmpty ? "" : sections.joined(separator: "\n\n")
    }
}

// MARK: - 地理位置信息
struct LocationInfo: Codable {
    var country: String?
    var province: String?
    var city: String?
    var district: String?
    
    init(country: String? = nil, province: String? = nil, city: String? = nil, district: String? = nil) {
        self.country = country
        self.province = province
        self.city = city
        self.district = district
    }
    
    var description: String {
        var parts: [String] = []
        if let city = city { parts.append(city) }
        if let province = province, province != city { parts.append(province) }
        if let country = country { parts.append(country) }
        return parts.joined(separator: "，")
    }
}

// MARK: - 生活方式信息
struct LifestyleInfo: Codable {
    var livingSituation: String?           // 居住情况（独居/合租/与家人等）
    var dailyRoutine: String?              // 日常作息
    var lifestyleType: String?             // 生活方式类型（忙碌/悠闲/规律等）
    var habits: [String]                    // 生活习惯
    
    init(livingSituation: String? = nil, dailyRoutine: String? = nil, lifestyleType: String? = nil, habits: [String] = []) {
        self.livingSituation = livingSituation
        self.dailyRoutine = dailyRoutine
        self.lifestyleType = lifestyleType
        self.habits = habits
    }
    
    var description: String {
        var parts: [String] = []
        if let situation = livingSituation { parts.append("居住：\(situation)") }
        if let routine = dailyRoutine { parts.append("作息：\(routine)") }
        if let type = lifestyleType { parts.append("生活方式：\(type)") }
        if !habits.isEmpty { parts.append("习惯：\(habits.joined(separator: "、"))") }
        return parts.joined(separator: "；")
    }
}

// MARK: - 工作信息
struct WorkInfo: Codable {
    var company: String?                   // 公司/组织
    var position: String?                  // 职位
    var industry: String?                  // 行业
    var workStyle: String?                 // 工作风格
    var workSatisfaction: String?          // 工作满意度
    
    init(company: String? = nil, position: String? = nil, industry: String? = nil, workStyle: String? = nil, workSatisfaction: String? = nil) {
        self.company = company
        self.position = position
        self.industry = industry
        self.workStyle = workStyle
        self.workSatisfaction = workSatisfaction
    }
    
    var description: String {
        var parts: [String] = []
        if let position = position { parts.append("职位：\(position)") }
        if let company = company { parts.append("公司：\(company)") }
        if let industry = industry { parts.append("行业：\(industry)") }
        if let style = workStyle { parts.append("工作风格：\(style)") }
        return parts.joined(separator: "；")
    }
}

// MARK: - 健康信息
struct HealthInfo: Codable {
    var generalHealth: String?              // 总体健康状况
    var exerciseHabits: String?            // 运动习惯
    var sleepPattern: String?              // 睡眠模式
    var healthConcerns: [String]           // 健康关注点
    
    init(generalHealth: String? = nil, exerciseHabits: String? = nil, sleepPattern: String? = nil, healthConcerns: [String] = []) {
        self.generalHealth = generalHealth
        self.exerciseHabits = exerciseHabits
        self.sleepPattern = sleepPattern
        self.healthConcerns = healthConcerns
    }
    
    var description: String {
        var parts: [String] = []
        if let health = generalHealth { parts.append("健康状况：\(health)") }
        if let exercise = exerciseHabits { parts.append("运动：\(exercise)") }
        if let sleep = sleepPattern { parts.append("睡眠：\(sleep)") }
        if !healthConcerns.isEmpty { parts.append("关注：\(healthConcerns.joined(separator: "、"))") }
        return parts.joined(separator: "；")
    }
}

// MARK: - 性别
enum Gender: String, Codable {
    case male = "男"
    case female = "女"
    case unknown = "未知"
}

// MARK: - 重要人物信息
struct PersonInfo: Codable {
    var name: String
    var relationship: String  // 如: "母亲", "朋友", "同事"
    var notes: [String]       // 关于此人的备注
    
    var description: String {
        var desc = "\(name)(\(relationship))"
        if !notes.isEmpty {
            desc += " - \(notes.first ?? "")"
        }
        return desc
    }
}

// MARK: - 记忆检索结果
struct MemoryRetrievalResult: Codable {
    let needMemory: Bool           // 是否需要记忆
    let relevantMemoryIds: [UUID]  // 相关记忆的 ID
    let reason: String?            // 检索原因说明
    let suggestedContext: String?  // 建议注入的上下文
    
    static let empty = MemoryRetrievalResult(
        needMemory: false,
        relevantMemoryIds: [],
        reason: nil,
        suggestedContext: nil
    )
}

// MARK: - 记忆存储数据（用于持久化）
struct MemoryStorageData: Codable {
    var shortTermMemory: [Memory]
    var longTermMemory: [Memory]
    var userProfile: UserProfile
    var lastSaveTime: Date
    var version: Int  // 数据版本，用于迁移
    
    static let currentVersion = 1
    
    init() {
        self.shortTermMemory = []
        self.longTermMemory = []
        self.userProfile = UserProfile()
        self.lastSaveTime = Date()
        self.version = Self.currentVersion
    }
    
    init(shortTermMemory: [Memory], longTermMemory: [Memory], userProfile: UserProfile, lastSaveTime: Date, version: Int) {
        self.shortTermMemory = shortTermMemory
        self.longTermMemory = longTermMemory
        self.userProfile = userProfile
        self.lastSaveTime = lastSaveTime
        self.version = version
    }
}

// MARK: - Ark Responses API 响应
struct ArkResponsesResponse: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let createdAt: Int?
    let status: String?
    let model: String?
    let output: [ArkOutputItem]?
    let outputText: String?
    let choices: [ArkChoice]?
    let usage: ArkUsage?
    
    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case createdAt = "created_at"
        case status
        case model
        case output
        case outputText = "output_text"
        case choices
        case usage
    }
    
    struct ArkOutputItem: Codable {
        let type: String?
        let role: String?
        let content: [ArkOutputContent]?
    }
    
    struct ArkOutputContent: Codable {
        let type: String?
        let text: String?
    }
    
    struct ArkChoice: Codable {
        let index: Int?
        let message: ArkMessage?
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }
    
    struct ArkMessage: Codable {
        let role: String?
        let content: String?
    }
    
    struct ArkUsage: Codable {
        let inputTokens: Int?
        let outputTokens: Int?
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - 记忆调度结果
struct MemoryOrchestratorResult {
    let shouldRetrieve: Bool
    let retrievedMemories: [Memory]
    let extractedInfo: ExtractedInfo?
    let contextToInject: String
    let processingTime: TimeInterval
    
    struct ExtractedInfo {
        var userNameMentioned: String?
        var emotionalState: EmotionalTag?
        var topicsDiscussed: [String]
        var importantFacts: [String]
        var peopleReferences: [PersonInfo]
    }
    
    static let empty = MemoryOrchestratorResult(
        shouldRetrieve: false,
        retrievedMemories: [],
        extractedInfo: nil,
        contextToInject: "",
        processingTime: 0
    )
}

// MARK: - 记忆回廊（日记）模型
struct DiaryTurn: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let userText: String
    let aiText: String

    init(timestamp: Date = Date(), userText: String, aiText: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.userText = userText
        self.aiText = aiText
    }
}

struct MemoryCorridorDraft: Codable, Identifiable {
    let id: UUID
    let dateString: String          // YYYY-MM-DD
    let windowStart: Date           // 当日 00:00:01
    let windowEnd: Date             // 当日 23:59:59
    let createdAt: Date
    var updatedAt: Date
    var turns: [DiaryTurn]

    init(
        dateString: String,
        windowStart: Date,
        windowEnd: Date,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.dateString = dateString
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.turns = []
    }

    var hasConversation: Bool {
        turns.contains { turn in
            !turn.userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !turn.aiText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct MemoryCorridorEntry: Codable, Identifiable {
    let id: UUID
    let title: String               // <= 10 字
    let dateString: String          // YYYY-MM-DD
    let content: String             // <= 1000 字
    let createdAt: Date
    let sourceTurnCount: Int

    init(
        title: String,
        dateString: String,
        content: String,
        createdAt: Date,
        sourceTurnCount: Int
    ) {
        self.id = UUID()
        self.title = String(title.prefix(10))
        self.dateString = dateString
        self.content = String(content.prefix(1000))
        self.createdAt = createdAt
        self.sourceTurnCount = sourceTurnCount
    }
}

struct MemoryCorridorStorageData: Codable {
    var entries: [MemoryCorridorEntry]
    var currentDraft: MemoryCorridorDraft?
    var lastSaveTime: Date
    var version: Int

    static let currentVersion = 1

    init(
        entries: [MemoryCorridorEntry] = [],
        currentDraft: MemoryCorridorDraft? = nil,
        lastSaveTime: Date = Date(),
        version: Int = MemoryCorridorStorageData.currentVersion
    ) {
        self.entries = entries
        self.currentDraft = currentDraft
        self.lastSaveTime = lastSaveTime
        self.version = version
    }
}
