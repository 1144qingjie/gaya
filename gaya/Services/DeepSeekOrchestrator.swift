//
//  DeepSeekOrchestrator.swift
//  gaya
//
//  混合记忆系统 - AI 记忆调度服务
//  使用 Doubao(Ark Responses API) 进行智能记忆检索和信息提取
//

import Foundation

struct ArkTextResponse {
    let text: String
    let totalTokens: Int
}

/// Ark Responses API 输入内容（支持多模态）
enum ArkInputContent {
    case inputText(String)
    case inputImage(url: String)
    case inputVideo(url: String)
    case custom(type: String, payload: [String: Any])
    
    fileprivate var requestObject: [String: Any] {
        switch self {
        case .inputText(let text):
            return [
                "type": "input_text",
                "text": text
            ]
        case .inputImage(let url):
            return [
                "type": "input_image",
                "image_url": url
            ]
        case .inputVideo(let url):
            return [
                "type": "input_video",
                "video_url": url
            ]
        case .custom(let type, let payload):
            var content = payload
            content["type"] = type
            return content
        }
    }
}

/// Ark Responses API 输入消息
struct ArkInputMessage {
    let role: String
    let content: [ArkInputContent]
    
    fileprivate var requestObject: [String: Any] {
        [
            "role": role,
            "content": content.map { $0.requestObject }
        ]
    }
}

/// DeepSeek 记忆调度器
/// 负责：
/// 1. 判断当前对话是否需要历史记忆
/// 2. 语义检索相关记忆
/// 3. 从对话中提取关键信息
/// 4. 生成注入 system_role 的上下文
class DeepSeekOrchestrator {
    
    // MARK: - Singleton
    static let shared = DeepSeekOrchestrator()
    
    // MARK: - 配置
    private let apiKey: String
    private let baseURL: String
    private let model: String
    private let timeout: TimeInterval = 15
    private let defaultTemperature = 0.3
    private let defaultMaxOutputTokens = 500
    private let maxRetryAttempts = 3
    private let maxLengthRetryMaxOutputTokens = 1800
    private let maxLengthRetryStepTokens = 320
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 8.0
    
    // MARK: - 状态
    private var isProcessing = false
    private var lastProcessTime: Date?
    private let processingQueue = DispatchQueue(label: "com.gaya.ark.processing")
    
    // MARK: - 初始化
    private init() {
        let env = ProcessInfo.processInfo.environment
        let info = Bundle.main.infoDictionary
        
        // 优先级：环境变量 > Info.plist > 内置默认值
        apiKey = env["ARK_API_KEY"] ??
                 (info?["ARK_API_KEY"] as? String) ??
                 Secrets.arkApiKey
        baseURL = env["ARK_BASE_URL"] ??
                  (info?["ARK_BASE_URL"] as? String) ??
                  "https://ark.cn-beijing.volces.com/api/v3/responses"
        model = env["ARK_MODEL"] ??
                (info?["ARK_MODEL"] as? String) ??
                "doubao-seed-1-8-251228"
        
        print("🧠 Doubao(Ark) Orchestrator initialized - model: \(model)")
    }
    
    // MARK: - 公开接口
    
    /// 处理用户输入，决定是否需要检索记忆并返回上下文
    /// - Parameters:
    ///   - userQuery: 用户当前的输入
    ///   - recentContext: 最近的对话上下文（可选）
    /// - Returns: 记忆调度结果，包含是否需要记忆、检索到的记忆、建议注入的上下文
    func processUserInput(
        userQuery: String,
        recentContext: String? = nil
    ) async -> MemoryOrchestratorResult {
        let startTime = Date()
        
        // 防止并发处理
        guard !isProcessing else {
            print("⚠️ Orchestrator is already processing, skipping...")
            return .empty
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // 1. 获取记忆摘要列表
        let memorySummaries = MemoryStore.shared.getMemorySummaries()
        
        // 如果没有任何记忆，直接返回
        guard !memorySummaries.isEmpty else {
            print("📝 No memories to search")
            return .empty
        }
        
        // 2. 调用模型进行记忆检索决策
        let retrievalResult = await retrieveRelevantMemories(
            userQuery: userQuery,
            memorySummaries: memorySummaries
        )
        
        // 3. 如果需要记忆，获取完整记忆内容
        var retrievedMemories: [Memory] = []
        if retrievalResult.needMemory && !retrievalResult.relevantMemoryIds.isEmpty {
            retrievedMemories = MemoryStore.shared.getMemories(byIds: retrievalResult.relevantMemoryIds)
            print("📚 Retrieved \(retrievedMemories.count) relevant memories")
        }
        
        // 4. 构建注入上下文
        let contextToInject = buildContextFromMemories(
            memories: retrievedMemories,
            reason: retrievalResult.reason
        )
        
        // 5. 异步提取用户信息（不阻塞主流程）
        Task {
            await extractAndSaveUserInfo(from: userQuery)
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        lastProcessTime = Date()
        
        print("🧠 Memory orchestration completed in \(String(format: "%.2f", processingTime))s")
        
        return MemoryOrchestratorResult(
            shouldRetrieve: retrievalResult.needMemory,
            retrievedMemories: retrievedMemories,
            extractedInfo: nil,  // 异步提取，不在这里返回
            contextToInject: contextToInject,
            processingTime: processingTime
        )
    }
    
    /// 分析对话并提取/更新用户信息
    /// 可以在对话结束后调用，用于更新用户画像
    func analyzeAndUpdateProfile(
        userText: String,
        aiText: String
    ) async {
        await extractAndSaveUserInfo(from: userText)
        
        // 分析情感并标记
        if let emotion = await analyzeEmotion(text: userText) {
            // 更新用户画像的情绪基线
            MemoryStore.shared.updateUserProfile { profile in
                profile.emotionalBaseline = emotion
            }
        }
    }
    
    // MARK: - 私有方法
    
    /// 调用大模型判断是否需要检索记忆
    private func retrieveRelevantMemories(
        userQuery: String,
        memorySummaries: [String]
    ) async -> MemoryRetrievalResult {
        
        let summariesText = memorySummaries.joined(separator: "\n")
        
        let prompt = """
        你是一个记忆检索助手。根据用户当前的输入，判断是否需要从记忆库中检索相关信息。

        【用户当前输入】
        \(userQuery)

        【记忆库内容摘要】
        \(summariesText)

        【任务】
        1. 判断用户当前的输入是否需要历史记忆来更好地回应（输出 true/false）
        2. 如果需要，返回最相关的记忆编号（最多3条）
        3. 简要说明为什么需要这些记忆

        【判断标准】
        - 需要记忆：用户提到之前聊过的话题、人物、事件；用户使用代词如"那个"、"之前说的"、"她/他"
        - 不需要记忆：简单问候、新话题、明确的独立问题

        【输出格式】(严格按照JSON格式)
        {"need_memory": true/false, "memory_ids": [数字列表], "reason": "原因说明"}

        请直接输出JSON，不要有其他内容：
        """
        
        guard let response = await callDoubaoTextAPI(
            prompt: prompt,
            feature: .memoryRetrieval
        ) else {
            print("❌ Retrieval model call failed")
            return .empty
        }
        
        // 解析响应
        return parseRetrievalResponse(response, memorySummaries: memorySummaries)
    }
    
    /// 解析模型的检索响应
    private func parseRetrievalResponse(
        _ response: String,
        memorySummaries: [String]
    ) -> MemoryRetrievalResult {
        // 尝试从响应中提取 JSON
        let cleanResponse = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanResponse.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("⚠️ Failed to parse retrieval response: \(response)")
            return .empty
        }
        
        let needMemory = json["need_memory"] as? Bool ?? false
        let memoryIdNumbers = json["memory_ids"] as? [Int] ?? []
        let reason = json["reason"] as? String
        
        // 将编号转换为 UUID
        // 编号格式: [1], [2], ... 对应 memorySummaries 的索引
        var relevantIds: [UUID] = []
        let allMemories = MemoryStore.shared.getRetrievalCandidates()
        
        for idNum in memoryIdNumbers {
            let index = idNum - 1  // 编号从 1 开始，索引从 0 开始
            if index >= 0 && index < allMemories.count {
                relevantIds.append(allMemories[index].id)
            }
        }
        
        return MemoryRetrievalResult(
            needMemory: needMemory,
            relevantMemoryIds: relevantIds,
            reason: reason,
            suggestedContext: nil
        )
    }
    
    /// 从检索到的记忆构建上下文
    private func buildContextFromMemories(
        memories: [Memory],
        reason: String?
    ) -> String {
        guard !memories.isEmpty else { return "" }
        
        var context = "【相关记忆】\n"
        
        if let reason = reason {
            context += "（检索原因：\(reason)）\n"
        }
        
        for memory in memories {
            let emotionStr = memory.emotionalTag?.emoji ?? ""
            context += "\(emotionStr) 用户曾说：\(memory.userText)\n"
            context += "   你回复：\(memory.aiText)\n"
        }
        
        context += "\n请基于这些记忆，给出更有上下文感的回应。\n"
        
        return context
    }
    
    /// 提取用户信息并保存（专业版）
    private func extractAndSaveUserInfo(from text: String) async {
        guard shouldUpdateUserProfile(from: text) else {
            print("📝 Skipping profile extraction (no self-disclosure): \(text.prefix(50))")
            return
        }
        
        let prompt = """
        你是一个专业的用户画像分析师。从以下用户对话中深度提取和推断用户信息。

        【用户说的话】
        \(text)

        【提取任务】
        请从对话中提取以下维度的信息（如果提到或可以推断）：

        1. **基础信息**
           - name: 姓名
           - age: 年龄（数字）
           - gender: 性别（男/女）
           - location: 地理位置 {country, province, city}
           - occupation: 职业
           - education: 教育背景

        2. **兴趣与偏好**
           - hobbies: 具体爱好（如：骑自行车、看电影）
           - interests: 兴趣领域（如：科技、艺术、运动）
           - preferences: 偏好设置 {key: value}（如：{"音乐": "爵士", "食物": "辣"})
           - dislikes: 不喜欢的事物

        3. **社交关系**
           - people: 重要人物 [{name, relationship, notes}]
           - relationship_status: 关系状态（单身/恋爱/已婚等）

        4. **生活状态**
           - lifestyle: 生活方式 {living_situation, daily_routine, lifestyle_type, habits}
           - work: 工作信息 {company, position, industry, work_style}
           - health: 健康信息 {general_health, exercise_habits, sleep_pattern, health_concerns}

        5. **心理特征**
           - personality_traits: 性格特质（如：外向、细心、乐观）
           - values: 价值观（如：家庭、自由、成就）
           - goals: 目标/愿望
           - communication_style: 沟通风格（如：直接、委婉、幽默）
           - emotion: 当前情感状态

        6. **行为模式**
           - conversation_topics: 常聊话题
           - active_time: 活跃时间模式（如果可推断）

        7. **其他信息**
           - facts: 重要事实
           - memorable_moments: 难忘时刻
           - concerns: 担忧/困扰
           - achievements: 成就/里程碑

        【提取原则】
        - 只提取明确提到或可以合理推断的信息
        - 不要编造信息
        - 对于不确定的信息，使用 null 或空列表
        - 尽量提取具体、有价值的信息

        【输出格式】(严格JSON)
        {
            "name": "姓名或null",
            "age": 数字或null,
            "gender": "男/女或null",
            "location": {"country": "...", "province": "...", "city": "..."} 或 null,
            "occupation": "职业或null",
            "education": "教育背景或null",
            "hobbies": ["爱好列表"],
            "interests": ["兴趣领域"],
            "preferences": {"key": "value"},
            "dislikes": ["不喜欢的事物"],
            "people": [{"name": "人名", "relationship": "关系", "notes": ["备注"]}],
            "relationship_status": "关系状态或null",
            "lifestyle": {"living_situation": "...", "daily_routine": "...", "lifestyle_type": "...", "habits": ["习惯"]} 或 null,
            "work": {"company": "...", "position": "...", "industry": "...", "work_style": "..."} 或 null,
            "health": {"general_health": "...", "exercise_habits": "...", "sleep_pattern": "...", "health_concerns": ["关注点"]} 或 null,
            "personality_traits": ["性格特质"],
            "values": ["价值观"],
            "goals": ["目标/愿望"],
            "communication_style": "沟通风格或null",
            "emotion": "情感状态或null",
            "conversation_topics": ["话题"],
            "active_time": "活跃时间或null",
            "facts": ["事实"],
            "memorable_moments": ["难忘时刻"],
            "concerns": ["担忧"],
            "achievements": ["成就"]
        }

        请直接输出JSON，不要其他文字：
        """
        
        guard let response = await callDoubaoTextAPI(
            prompt: prompt,
            feature: .memoryProfileExtraction
        ) else {
            return
        }
        
        // 解析并更新用户画像
        parseAndUpdateProfile(from: response, sourceText: text)
    }
    
    /// 解析提取结果并更新用户画像（专业版）
    private func parseAndUpdateProfile(from response: String, sourceText: String) {
        let cleanResponse = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanResponse.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("⚠️ Failed to parse profile response")
            return
        }
        
        let canUpdateName = isExplicitSelfDisclosure(sourceText, keywords: ["我叫", "我的名字", "我名字", "叫我"])
        let canUpdateAge = isExplicitSelfDisclosure(sourceText, keywords: ["我今年", "我岁"]) ||
            (sourceText.contains("岁") && sourceText.contains("我"))
        let canUpdateGender = isExplicitSelfDisclosure(sourceText, keywords: ["我是男", "我是女", "性别"])
        let canUpdateLocation = isExplicitSelfDisclosure(sourceText, keywords: ["我在", "我住", "我来自", "我这边", "我目前在"])
        let canUpdateOccupation = isExplicitSelfDisclosure(sourceText, keywords: ["我工作", "我从事", "我负责", "我上班"]) ||
            (sourceText.contains("我在") && sourceText.contains("公司"))
        let canUpdateEducation = isExplicitSelfDisclosure(sourceText, keywords: ["我毕业", "我在读", "我读", "我学", "学历"])
        let canUpdateHobbies = isExplicitSelfDisclosure(sourceText, keywords: ["我喜欢", "我爱好", "我的爱好", "我兴趣", "我感兴趣"])
        let canUpdateDislikes = isExplicitSelfDisclosure(sourceText, keywords: ["我不喜欢", "我讨厌", "我反感"])
        
        MemoryStore.shared.updateUserProfile { profile in
            var updates: [String] = []
            
            // ========== 基础信息 ==========
            if canUpdateName, let name = json["name"] as? String, !name.isEmpty, name != "null" {
                let isValidName = validateName(name)
                if isValidName && profile.name != name {
                    profile.name = name
                    updates.append("姓名: \(name)")
                }
            }
            
            if canUpdateAge, let age = json["age"] as? Int, age > 0 && age < 150 {
                if profile.age != age {
                    profile.age = age
                    updates.append("年龄: \(age)")
                }
            }
            
            if canUpdateGender, let genderStr = json["gender"] as? String, !genderStr.isEmpty, genderStr != "null" {
                if let gender = Gender(rawValue: genderStr), profile.gender != gender {
                    profile.gender = gender
                    updates.append("性别: \(genderStr)")
                }
            }
            
            if canUpdateLocation, let locationDict = json["location"] as? [String: String] {
                var location = LocationInfo()
                location.country = locationDict["country"]
                location.province = locationDict["province"]
                location.city = locationDict["city"]
                if location.city != nil || location.province != nil || location.country != nil {
                    profile.location = location
                    updates.append("位置: \(location.description)")
                }
            }
            
            if canUpdateOccupation, let occupation = json["occupation"] as? String, !occupation.isEmpty, occupation != "null" {
                if profile.occupation != occupation {
                    profile.occupation = occupation
                    updates.append("职业: \(occupation)")
                }
            }
            
            if canUpdateEducation, let education = json["education"] as? String, !education.isEmpty, education != "null" {
                if profile.education != education {
                    profile.education = education
                    updates.append("教育: \(education)")
                }
            }
            
            // ========== 兴趣与偏好 ==========
            if canUpdateHobbies, let hobbies = json["hobbies"] as? [String] {
                for hobby in hobbies where !hobby.isEmpty && !profile.hobbies.contains(hobby) {
                    profile.hobbies.append(hobby)
                }
                if !hobbies.isEmpty { updates.append("爱好+\(hobbies.count)") }
            }
            
            if canUpdateHobbies, let interests = json["interests"] as? [String] {
                for interest in interests where !interest.isEmpty && !profile.interests.contains(interest) {
                    profile.interests.append(interest)
                }
                if !interests.isEmpty { updates.append("兴趣+\(interests.count)") }
            }
            
            if canUpdateHobbies, let preferences = json["preferences"] as? [String: String] {
                for (key, value) in preferences where !key.isEmpty && !value.isEmpty {
                    profile.preferences[key] = value
                }
                if !preferences.isEmpty { updates.append("偏好+\(preferences.count)") }
            }
            
            if canUpdateDislikes, let dislikes = json["dislikes"] as? [String] {
                for dislike in dislikes where !dislike.isEmpty && !profile.dislikes.contains(dislike) {
                    profile.dislikes.append(dislike)
                }
                if !dislikes.isEmpty { updates.append("不喜欢+\(dislikes.count)") }
            }
            
            // ========== 社交关系 ==========
            if let people = json["people"] as? [[String: Any]] {
                for personDict in people {
                    if let relationship = personDict["relationship"] as? String, !relationship.isEmpty {
                        let name = personDict["name"] as? String ?? ""
                        let notes = personDict["notes"] as? [String] ?? []
                        
                        // 检查是否已存在相同关系的人
                        if let existingIndex = profile.importantPeople.firstIndex(where: { $0.relationship == relationship }) {
                            // 更新现有记录
                            profile.importantPeople[existingIndex].name = name.isEmpty ? profile.importantPeople[existingIndex].name : name
                            profile.importantPeople[existingIndex].notes.append(contentsOf: notes)
                        } else {
                            // 添加新记录
                            profile.importantPeople.append(PersonInfo(name: name, relationship: relationship, notes: notes))
                        }
                    }
                }
                if !people.isEmpty { updates.append("人物+\(people.count)") }
            }
            
            if let status = json["relationship_status"] as? String, !status.isEmpty, status != "null" {
                if profile.relationshipStatus != status {
                    profile.relationshipStatus = status
                    updates.append("关系状态: \(status)")
                }
            }
            
            // ========== 生活状态 ==========
            if let lifestyleDict = json["lifestyle"] as? [String: Any] {
                var lifestyle = LifestyleInfo()
                lifestyle.livingSituation = lifestyleDict["living_situation"] as? String
                lifestyle.dailyRoutine = lifestyleDict["daily_routine"] as? String
                lifestyle.lifestyleType = lifestyleDict["lifestyle_type"] as? String
                lifestyle.habits = lifestyleDict["habits"] as? [String] ?? []
                profile.lifestyle = lifestyle
                updates.append("生活方式")
            }
            
            if let workDict = json["work"] as? [String: Any] {
                var work = WorkInfo()
                work.company = workDict["company"] as? String
                work.position = workDict["position"] as? String
                work.industry = workDict["industry"] as? String
                work.workStyle = workDict["work_style"] as? String
                profile.workInfo = work
                updates.append("工作信息")
            }
            
            if let healthDict = json["health"] as? [String: Any] {
                var health = HealthInfo()
                health.generalHealth = healthDict["general_health"] as? String
                health.exerciseHabits = healthDict["exercise_habits"] as? String
                health.sleepPattern = healthDict["sleep_pattern"] as? String
                health.healthConcerns = healthDict["health_concerns"] as? [String] ?? []
                profile.healthInfo = health
                updates.append("健康信息")
            }
            
            // ========== 心理特征 ==========
            if let traits = json["personality_traits"] as? [String] {
                for trait in traits where !trait.isEmpty && !profile.personalityTraits.contains(trait) {
                    profile.personalityTraits.append(trait)
                }
                if !traits.isEmpty { updates.append("性格特质+\(traits.count)") }
            }
            
            if let values = json["values"] as? [String] {
                for value in values where !value.isEmpty && !profile.values.contains(value) {
                    profile.values.append(value)
                }
                if !values.isEmpty { updates.append("价值观+\(values.count)") }
            }
            
            if let goals = json["goals"] as? [String] {
                for goal in goals where !goal.isEmpty && !profile.goals.contains(goal) {
                    profile.goals.append(goal)
                }
                if !goals.isEmpty { updates.append("目标+\(goals.count)") }
            }
            
            if let style = json["communication_style"] as? String, !style.isEmpty, style != "null" {
                if profile.communicationStyle != style {
                    profile.communicationStyle = style
                    updates.append("沟通风格: \(style)")
                }
            }
            
            if let emotionStr = json["emotion"] as? String, !emotionStr.isEmpty, emotionStr != "null" {
                if let emotion = EmotionalTag.allCases.first(where: { $0.rawValue == emotionStr }) {
                    profile.emotionalBaseline = emotion
                    updates.append("情感: \(emotionStr)")
                }
            }
            
            // ========== 行为模式 ==========
            if let topics = json["conversation_topics"] as? [String] {
                for topic in topics where !topic.isEmpty && !profile.conversationTopics.contains(topic) {
                    profile.conversationTopics.append(topic)
                }
                if !topics.isEmpty { updates.append("话题+\(topics.count)") }
            }
            
            if let activeTime = json["active_time"] as? String, !activeTime.isEmpty, activeTime != "null" {
                if profile.activeTimePattern != activeTime {
                    profile.activeTimePattern = activeTime
                    updates.append("活跃时间: \(activeTime)")
                }
            }
            
            // ========== 其他信息 ==========
            if let facts = json["facts"] as? [String] {
                for fact in facts where !fact.isEmpty && !profile.facts.contains(fact) {
                    profile.facts.append(fact)
                    if profile.facts.count > 20 {
                        profile.facts.removeFirst()
                    }
                }
                if !facts.isEmpty { updates.append("事实+\(facts.count)") }
            }
            
            if let moments = json["memorable_moments"] as? [String] {
                for moment in moments where !moment.isEmpty && !profile.memorableMoments.contains(moment) {
                    profile.memorableMoments.append(moment)
                    if profile.memorableMoments.count > 10 {
                        profile.memorableMoments.removeFirst()
                    }
                }
                if !moments.isEmpty { updates.append("难忘时刻+\(moments.count)") }
            }
            
            if let concerns = json["concerns"] as? [String] {
                for concern in concerns where !concern.isEmpty && !profile.concerns.contains(concern) {
                    profile.concerns.append(concern)
                    if profile.concerns.count > 10 {
                        profile.concerns.removeFirst()
                    }
                }
                if !concerns.isEmpty { updates.append("关注+\(concerns.count)") }
            }
            
            if let achievements = json["achievements"] as? [String] {
                for achievement in achievements where !achievement.isEmpty && !profile.achievements.contains(achievement) {
                    profile.achievements.append(achievement)
                    if profile.achievements.count > 10 {
                        profile.achievements.removeFirst()
                    }
                }
                if !achievements.isEmpty { updates.append("成就+\(achievements.count)") }
            }
            
            // 更新完整度
            profile.calculateCompleteness()
            profile.lastUpdated = Date()
            
            if !updates.isEmpty {
                print("👤 Profile updated: \(updates.joined(separator: ", "))")
                print("📊 Profile completeness: \(String(format: "%.1f%%", profile.profileCompleteness * 100))")
            }
        }
    }
    
    /// 验证名字是否有效
    private func validateName(_ name: String) -> Bool {
        // 需要排除的词（这些不是名字）
        let excludeWords = [
            "一个", "一名", "一位", "某个", "那个", "这个", "什么", "谁", "哪个",
            "字", "名字", "名", "知道", "记得", "忘了", "说", "讲", "告诉",
            "什么名", "叫什么", "啥名", "哪位", "怎么", "如何", "null", "NULL"
        ]
        
        // 不应该出现在名字中的字符
        let invalidChars = ["？", "?", "！", "!", "。", "，", ",", "、", "；", ";", " "]
        
        let containsInvalidChar = invalidChars.contains { name.contains($0) }
        let isExcludedWord = excludeWords.contains(name)
        let containsExcludedWord = excludeWords.contains { name.contains($0) }
        
        let isValid = !name.isEmpty &&
                      name.count >= 2 &&
                      name.count <= 6 &&
                      !isExcludedWord &&
                      !containsExcludedWord &&
                      !containsInvalidChar &&
                      !name.contains("是") &&
                      !name.contains("的")
        
        return isValid
    }

    /// 判断是否应该更新用户画像（需要明确自我披露）
    private func shouldUpdateUserProfile(from text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        // 明确自我披露关键词
        let selfDisclosureKeywords = [
            "我叫", "我的名字", "我名字", "叫我",
            "我今年", "我岁", "我已经",
            "我是", "性别",
            "我在", "我住", "我来自", "我这边", "我目前在",
            "我工作", "我上班", "我从事", "我负责",
            "我毕业", "我在读", "我读", "我学", "学历",
            "我喜欢", "我爱好", "我的爱好", "我兴趣", "我感兴趣",
            "我不喜欢", "我讨厌", "我反感",
            "我的目标", "我希望", "我想", "我担心", "我困扰"
        ]
        
        if selfDisclosureKeywords.contains(where: { trimmed.contains($0) }) {
            return true
        }
        
        // 非自我披露问题，直接跳过画像更新
        return false
    }
    
    /// 判断文本是否包含明确自我披露
    private func isExplicitSelfDisclosure(_ text: String, keywords: [String]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if keywords.contains(where: { trimmed.contains($0) }) {
            return true
        }
        return false
    }
    
    /// 分析文本的情感
    private func analyzeEmotion(text: String) async -> EmotionalTag? {
        let prompt = """
        分析以下文本的情感状态，从以下选项中选择最匹配的一个：
        开心、难过、焦虑、生气、好奇、感激、孤独、兴奋、平静、需要支持

        【文本】
        \(text)

        请只输出一个情感词：
        """
        
        guard let response = await callDoubaoTextAPI(
            prompt: prompt,
            feature: .memoryEmotionAnalysis
        ) else {
            return nil
        }
        
        let emotion = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return EmotionalTag.allCases.first { $0.rawValue == emotion }
    }
    
    /// 公开的 API 调用方法（供其他模块使用，向后兼容旧命名）
    func callDeepSeekAPI(prompt: String) async -> String? {
        return await callDoubaoTextAPI(prompt: prompt)
    }
    
    /// 新接口：调用 Doubao 文本能力（Ark Responses API）
    func callDoubaoTextAPI(
        prompt: String,
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        feature: MembershipFeatureKey? = nil
    ) async -> String? {
        let result = await callDoubaoTextResult(
            prompt: prompt,
            temperature: temperature,
            maxOutputTokens: maxOutputTokens,
            feature: feature
        )
        return result?.text
    }

    func callDoubaoTextResult(
        prompt: String,
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        feature: MembershipFeatureKey? = nil
    ) async -> ArkTextResponse? {
        let message = ArkInputMessage(
            role: "user",
            content: [.inputText(prompt)]
        )

        let resolvedTemperature = temperature ?? defaultTemperature
        let resolvedMaxOutputTokens = maxOutputTokens ?? defaultMaxOutputTokens
        
        return await callArkResponses(
            messages: [message],
            temperature: resolvedTemperature,
            maxOutputTokens: resolvedMaxOutputTokens,
            feature: feature
        )
    }
    
    /// 新接口：调用 Doubao 多模态能力（文本/图片/视频）
    func callDoubaoAPI(
        messages: [ArkInputMessage],
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        feature: MembershipFeatureKey? = nil
    ) async -> String? {
        let result = await callDoubaoAPIResult(
            messages: messages,
            temperature: temperature,
            maxOutputTokens: maxOutputTokens,
            feature: feature
        )
        return result?.text
    }

    func callDoubaoAPIResult(
        messages: [ArkInputMessage],
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        feature: MembershipFeatureKey? = nil
    ) async -> ArkTextResponse? {
        return await callArkResponses(
            messages: messages,
            temperature: temperature,
            maxOutputTokens: maxOutputTokens,
            feature: feature
        )
    }

    /// 调用 Ark Responses API（统一底层）
    private func callArkResponses(
        messages: [ArkInputMessage],
        temperature: Double?,
        maxOutputTokens: Int?,
        feature: MembershipFeatureKey? = nil
    ) async -> ArkTextResponse? {
        guard let url = URL(string: baseURL) else {
            print("❌ Invalid Ark URL")
            return nil
        }

        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ Empty Ark API key")
            return nil
        }

        var currentMaxOutputTokens = maxOutputTokens
        let hold: MembershipHoldReceipt?
        if let feature {
            do {
                hold = try await MembershipBillingCoordinator.shared.createHold(
                    feature: feature,
                    payload: [
                        "model": model,
                        "gateway": "ark"
                    ]
                )
            } catch {
                await MainActor.run {
                    MembershipStore.shared.blockingMessage = error.localizedDescription
                }
                print("❌ Membership hold create failed for \(feature.rawValue): \(error.localizedDescription)")
                return nil
            }
        } else {
            hold = nil
        }

        func releaseHoldIfNeeded(reason: String) async {
            guard let hold else { return }
            await MembershipBillingCoordinator.shared.releaseHold(hold, reason: reason)
        }

        for attempt in 1...maxRetryAttempts {
            var body: [String: Any] = [
                "model": model,
                "input": messages.map { $0.requestObject }
            ]

            if let temperature = temperature {
                body["temperature"] = temperature
            }
            if let currentMaxOutputTokens {
                body["max_output_tokens"] = currentMaxOutputTokens
            }

            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                print("❌ Failed to serialize Ark request")
                await releaseHoldIfNeeded(reason: "serialize_failed")
                return nil
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = timeout
            request.httpBody = httpBody

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    if attempt < maxRetryAttempts {
                        let delay = retryDelaySeconds(forAttempt: attempt, retryAfter: nil)
                        print("⚠️ Ark response type invalid, retrying in \(String(format: "%.2f", delay))s (\(attempt)/\(maxRetryAttempts))")
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    print("❌ Invalid response type")
                    await releaseHoldIfNeeded(reason: "invalid_response")
                    return nil
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    if shouldRetry(statusCode: httpResponse.statusCode), attempt < maxRetryAttempts {
                        let retryAfter = retryAfterSeconds(from: httpResponse)
                        let delay = retryDelaySeconds(forAttempt: attempt, retryAfter: retryAfter)
                        print("⚠️ Ark API transient error \(httpResponse.statusCode), retrying in \(String(format: "%.2f", delay))s (\(attempt)/\(maxRetryAttempts))")
                        if let errorText = String(data: data, encoding: .utf8) {
                            print("   Error: \(errorText)")
                        }
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }

                    print("❌ Ark API error: \(httpResponse.statusCode)")
                    if let errorText = String(data: data, encoding: .utf8) {
                        print("   Error: \(errorText)")
                    }
                    await releaseHoldIfNeeded(reason: "http_error")
                    return nil
                }

                let extraction = extractTextAndUsage(from: data)
                if let totalTokens = extraction.totalTokens {
                    print("📊 Doubao usage: \(totalTokens) tokens")
                }

                if let text = extraction.text, !text.isEmpty {
                    let settledTokens = extraction.totalTokens ?? estimateTotalTokens(
                        messages: messages,
                        responseText: text,
                        maxOutputTokens: currentMaxOutputTokens
                    )
                    if let hold {
                        await MembershipBillingCoordinator.shared.commitHold(
                            hold,
                            usage: MembershipOperationUsage(totalTokens: settledTokens, billableSeconds: nil),
                            payload: [
                                "model": model,
                                "feature": feature?.rawValue ?? ""
                            ]
                        )
                    }
                    return ArkTextResponse(text: text, totalTokens: settledTokens)
                }

                let incompleteReason = extractIncompleteReason(from: data)
                if incompleteReason == "length",
                   attempt < maxRetryAttempts,
                   let expandedMaxOutputTokens = expandedMaxOutputTokens(from: currentMaxOutputTokens) {
                    let delay = retryDelaySeconds(forAttempt: attempt, retryAfter: nil)
                    print("⚠️ Ark response incomplete(length) with no text, retrying in \(String(format: "%.2f", delay))s (\(attempt)/\(maxRetryAttempts)); max_output_tokens \(currentMaxOutputTokens ?? 0) -> \(expandedMaxOutputTokens)")
                    currentMaxOutputTokens = expandedMaxOutputTokens
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                if let raw = String(data: data, encoding: .utf8) {
                    print("⚠️ Ark response contains no text payload: \(raw)")
                }
                await releaseHoldIfNeeded(reason: "empty_response")
                return nil
            } catch {
                if shouldRetry(networkError: error), attempt < maxRetryAttempts {
                    let delay = retryDelaySeconds(forAttempt: attempt, retryAfter: nil)
                    print("⚠️ Ark API call transient failure: \(error.localizedDescription), retrying in \(String(format: "%.2f", delay))s (\(attempt)/\(maxRetryAttempts))")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                print("❌ Ark API call failed: \(error)")
                await releaseHoldIfNeeded(reason: "network_error")
                return nil
            }
        }

        await releaseHoldIfNeeded(reason: "retry_exhausted")
        return nil
    }

    private func estimateTotalTokens(
        messages: [ArkInputMessage],
        responseText: String,
        maxOutputTokens: Int?
    ) -> Int {
        let inputChars = messages.reduce(0) { partialResult, message in
            partialResult + message.content.reduce(0) { partial, content in
                switch content {
                case .inputText(let text):
                    return partial + text.count
                case .inputImage(let url), .inputVideo(let url):
                    return partial + min(url.count / 12, 240)
                case .custom(_, let payload):
                    return partial + payload.description.count / 4
                }
            }
        }

        let estimatedInputTokens = max(1, Int(Double(inputChars) * 0.8))
        let estimatedOutputTokens = max(responseText.count, maxOutputTokens.map { min($0, max(responseText.count, 1) * 2) } ?? responseText.count)
        return estimatedInputTokens + estimatedOutputTokens
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        switch statusCode {
        case 408, 425, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    private func shouldRetry(networkError: Error) -> Bool {
        guard let urlError = networkError as? URLError else {
            return false
        }

        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(value), seconds > 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }

        return nil
    }

    private func retryDelaySeconds(forAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            return min(maxRetryDelay, retryAfter)
        }

        let exponent = pow(2.0, Double(max(0, attempt - 1)))
        let baseDelay = min(maxRetryDelay, baseRetryDelay * exponent)
        let jitter = Double.random(in: 0...0.35)
        return min(maxRetryDelay, baseDelay + jitter)
    }

    private func expandedMaxOutputTokens(from current: Int?) -> Int? {
        guard let current, current > 0 else { return nil }
        guard current < maxLengthRetryMaxOutputTokens else { return nil }

        let expanded = min(
            maxLengthRetryMaxOutputTokens,
            max(
                current + maxLengthRetryStepTokens,
                Int(Double(current) * 1.6)
            )
        )
        return expanded > current ? expanded : nil
    }

    private func extractIncompleteReason(from data: Data) -> String? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let json = jsonObject as? [String: Any] else {
            return nil
        }

        if let details = json["incomplete_details"] as? [String: Any],
           let reason = details["reason"] as? String,
           !reason.isEmpty {
            return reason
        }

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                if let details = item["incomplete_details"] as? [String: Any],
                   let reason = details["reason"] as? String,
                   !reason.isEmpty {
                    return reason
                }
            }
        }

        return nil
    }
    
    /// 兼容不同响应格式，提取文本与 token 使用量
    private func extractTextAndUsage(from data: Data) -> (text: String?, totalTokens: Int?) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let json = jsonObject as? [String: Any] else {
            return (nil, nil)
        }
        
        let totalTokens = extractTotalTokens(from: json)
        
        if let outputText = json["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (outputText, totalTokens)
        }
        
        if let output = json["output"] as? [[String: Any]] {
            let texts = extractTextsFromOutput(output)
            if !texts.isEmpty {
                return (texts.joined(separator: "\n"), totalTokens)
            }
        }
        
        if let choices = json["choices"] as? [[String: Any]] {
            let texts = extractTextsFromChoices(choices)
            if !texts.isEmpty {
                return (texts.joined(separator: "\n"), totalTokens)
            }
        }
        
        return (nil, totalTokens)
    }
    
    private func extractTextsFromOutput(_ output: [[String: Any]]) -> [String] {
        var texts: [String] = []
        
        for item in output {
            if let contentItems = item["content"] as? [[String: Any]] {
                for content in contentItems {
                    if let text = extractTextValue(from: content) {
                        texts.append(text)
                    }
                }
            }
        }
        
        return texts
    }
    
    private func extractTextsFromChoices(_ choices: [[String: Any]]) -> [String] {
        var texts: [String] = []
        
        for choice in choices {
            guard let message = choice["message"] as? [String: Any] else { continue }
            
            if let content = message["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(content)
                continue
            }
            
            if let contentArray = message["content"] as? [[String: Any]] {
                for item in contentArray {
                    if let text = extractTextValue(from: item) {
                        texts.append(text)
                    }
                }
            }
        }
        
        return texts
    }
    
    private func extractTextValue(from content: [String: Any]) -> String? {
        if let text = content["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        
        if let outputText = content["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }
        
        if let textDict = content["text"] as? [String: Any],
           let value = textDict["value"] as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        
        return nil
    }
    
    private func extractTotalTokens(from json: [String: Any]) -> Int? {
        guard let usage = json["usage"] as? [String: Any] else {
            return nil
        }
        
        if let total = intValue(usage["total_tokens"]) {
            return total
        }
        
        let inputTokens = intValue(usage["input_tokens"]) ?? intValue(usage["prompt_tokens"])
        let outputTokens = intValue(usage["output_tokens"]) ?? intValue(usage["completion_tokens"])
        
        switch (inputTokens, outputTokens) {
        case let (input?, output?):
            return input + output
        case let (input?, nil):
            return input
        case let (nil, output?):
            return output
        default:
            return nil
        }
    }
    
    private func intValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let doubleValue = value as? Double {
            return Int(doubleValue)
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }
}

// MARK: - 混合检索策略
extension DeepSeekOrchestrator {
    
    /// 混合检索：结合向量检索和大模型智能调度
    /// 策略：
    /// 1. 首先进行本地向量检索，获取候选记忆
    /// 2. 如果向量检索结果相似度很高（>0.7），直接使用
    /// 3. 如果相似度较低或结果不理想，调用大模型进行精排
    /// - Parameters:
    ///   - query: 用户查询
    ///   - useDeepSeekFallback: 是否在向量检索不理想时使用模型精排
    /// - Returns: 混合检索结果
    func hybridRetrieval(
        query: String,
        useDeepSeekFallback: Bool = true
    ) async -> HybridRetrievalResult {
        let startTime = Date()
        
        // 1. 首先尝试本地向量检索
        let vectorResults = MemoryStore.shared.semanticSearchWithScores(
            query: query,
            topK: 5,
            threshold: 0.2  // 较低阈值，获取更多候选
        )
        
        // 分析向量检索结果质量
        let highConfidenceResults = vectorResults.filter { $0.similarity > 0.7 }
        let mediumConfidenceResults = vectorResults.filter { $0.similarity > 0.4 && $0.similarity <= 0.7 }
        
        print("🔍 Vector search results: \(vectorResults.count) total, \(highConfidenceResults.count) high confidence, \(mediumConfidenceResults.count) medium")
        
        // 2. 决定检索策略
        var finalMemories: [Memory] = []
        var retrievalMethod: RetrievalMethod = .vectorOnly
        var confidence: Float = 0.0
        
        if !highConfidenceResults.isEmpty {
            // 高置信度结果，直接使用向量检索
            finalMemories = highConfidenceResults.prefix(3).map { $0.memory }
            confidence = highConfidenceResults.first?.similarity ?? 0.0
            retrievalMethod = .vectorOnly
            print("✅ Using high confidence vector results (similarity: \(confidence))")
            
        } else if !mediumConfidenceResults.isEmpty {
            // 中等置信度，可能需要 DeepSeek 精排
            if useDeepSeekFallback && mediumConfidenceResults.count >= 2 {
                // 调用模型进行精排
                let candidateMemories = mediumConfidenceResults.map { $0.memory }
                if let rerankedMemories = await rerankWithDeepSeek(
                    query: query,
                    candidates: candidateMemories
                ) {
                    finalMemories = rerankedMemories
                    retrievalMethod = .hybrid
                    confidence = 0.6  // 混合方法的估计置信度
                    print("🔄 Model reranking completed")
                } else {
                    // 模型精排失败，使用向量结果
                    finalMemories = mediumConfidenceResults.prefix(3).map { $0.memory }
                    confidence = mediumConfidenceResults.first?.similarity ?? 0.0
                    retrievalMethod = .vectorOnly
                }
            } else {
                // 不使用模型精排，直接使用向量结果
                finalMemories = mediumConfidenceResults.prefix(3).map { $0.memory }
                confidence = mediumConfidenceResults.first?.similarity ?? 0.0
                retrievalMethod = .vectorOnly
            }
            
        } else if useDeepSeekFallback {
            // 向量检索没有好结果，完全依赖大模型
            let fullResult = await processUserInput(userQuery: query)
            if fullResult.shouldRetrieve {
                finalMemories = fullResult.retrievedMemories
                retrievalMethod = .deepSeekOnly
                confidence = 0.5  // 纯大模型检索的估计置信度
                print("🧠 Using model-only retrieval")
            }
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return HybridRetrievalResult(
            memories: finalMemories,
            method: retrievalMethod,
            confidence: confidence,
            processingTime: processingTime
        )
    }
    
    /// 使用大模型对向量检索候选进行精排
    private func rerankWithDeepSeek(
        query: String,
        candidates: [Memory]
    ) async -> [Memory]? {
        guard !candidates.isEmpty else { return nil }
        
        // 构建候选列表
        let candidateText = candidates.enumerated().map { idx, memory in
            "[\(idx + 1)] 用户说：\(memory.userText)  AI回：\(memory.aiText)"
        }.joined(separator: "\n")
        
        let prompt = """
        用户当前问题：\(query)
        
        候选记忆：
        \(candidateText)
        
        请从候选中选出与用户问题最相关的记忆，按相关性排序。
        只输出编号列表，如：[1, 3]（最相关在前）
        如果都不相关，输出：[]
        """
        
        guard let response = await callDoubaoTextAPI(
            prompt: prompt,
            feature: .memoryRetrieval
        ) else {
            return nil
        }
        
        // 解析响应
        let cleanResponse = response
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 提取数字列表
        var indices: [Int] = []
        let pattern = "\\[(\\d+(?:,\\s*\\d+)*)\\]"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: cleanResponse, range: NSRange(cleanResponse.startIndex..., in: cleanResponse)),
           let range = Range(match.range(at: 1), in: cleanResponse) {
            let numbersStr = String(cleanResponse[range])
            indices = numbersStr.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
        
        // 按索引返回记忆
        var result: [Memory] = []
        for idx in indices {
            let arrayIdx = idx - 1
            if arrayIdx >= 0 && arrayIdx < candidates.count {
                result.append(candidates[arrayIdx])
            }
        }
        
        return result.isEmpty ? nil : result
    }
}

// MARK: - 混合检索结果
struct HybridRetrievalResult {
    let memories: [Memory]
    let method: RetrievalMethod
    let confidence: Float
    let processingTime: TimeInterval
    
    var isEmpty: Bool { memories.isEmpty }
    
    /// 构建上下文字符串
    func buildContext() -> String {
        guard !memories.isEmpty else { return "" }
        
        var context = "【相关历史对话】\n"
        for memory in memories {
            let emotionStr = memory.emotionalTag?.emoji ?? ""
            context += "\(emotionStr) 用户曾说：\(memory.userText)\n"
            if !memory.aiText.isEmpty {
                context += "   你回复了：\(memory.aiText)\n"
            }
        }
        return context
    }
}

/// 检索方法类型
enum RetrievalMethod: String {
    case vectorOnly = "向量检索"
    case deepSeekOnly = "大模型检索"
    case hybrid = "混合检索"
}

// MARK: - 便捷扩展
extension DeepSeekOrchestrator {
    
    /// 快速检查是否可能需要记忆（本地预判，避免不必要的 API 调用）
    func quickCheckNeedMemory(query: String) -> Bool {
        // 包含指代词，可能需要记忆
        let referenceWords = ["那个", "之前", "上次", "刚才", "她", "他", "它", "这件事", "那件事"]
        for word in referenceWords {
            if query.contains(word) {
                return true
            }
        }
        
        // 包含延续词，可能需要记忆
        let continuationWords = ["然后呢", "后来", "接着", "所以", "结果"]
        for word in continuationWords {
            if query.contains(word) {
                return true
            }
        }
        
        // 简单问候，不需要记忆
        let greetings = ["你好", "早上好", "晚上好", "嗨", "hello", "hi"]
        for greeting in greetings {
            if query.lowercased().hasPrefix(greeting) && query.count < 10 {
                return false
            }
        }
        
        // 默认：有一定记忆量时启用检索
        let stats = MemoryStore.shared.getStatistics()
        return stats.shortTermCount >= 2 || stats.longTermCount >= 3
    }
    
    /// 获取调度器状态
    var status: String {
        let stats = MemoryStore.shared.getStatistics()
        let lastTime = lastProcessTime?.description ?? "never"
        return """
        🧠 Doubao(Ark) Orchestrator Status:
        - Processing: \(isProcessing)
        - Last process: \(lastTime)
        - Memory store: \(stats.shortTermCount) short-term, \(stats.longTermCount) long-term
        """
    }
}
