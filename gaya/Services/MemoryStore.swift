//
//  MemoryStore.swift
//  gaya
//
//  混合记忆系统 - 本地分层记忆存储
//  实现短期记忆、长期记忆的管理和持久化
//

import Foundation
import Combine

/// 本地记忆存储管理器
/// 采用分层记忆架构：短期记忆（完整）+ 长期记忆（精选/摘要）
class MemoryStore {
    
    // MARK: - Singleton
    static let shared = MemoryStore()
    
    // MARK: - 配置参数
    private let shortTermLimit = 5          // 短期记忆最多保留 5 轮对话
    private let longTermLimit = 100         // 长期记忆最多保留 100 条
    private let importanceThreshold: Float = 0.6  // 转入长期记忆的重要性阈值
    private let photoInjectionPrefix = "我刚上传了一张新照片。先给你这张照片的画面信息："
    private let photoInjectionInstruction = "请你先用2到3句口语化中文回应你观察到的内容"
    
    // MARK: - 记忆存储
    private var shortTermMemory: [Memory] = []   // 短期记忆（最近对话，完整保留）
    private var longTermMemory: [Memory] = []    // 长期记忆（重要记忆，可能带摘要）
    private var userProfile: UserProfile = UserProfile()  // 用户画像
    
    // MARK: - 持久化
    private var storageURL: URL
    private var currentNamespace: String = "local"
    private let saveQueue = DispatchQueue(label: "com.gaya.memoryStore.save")
    private var isDirty = false  // 标记是否需要保存
    
    // MARK: - 向量存储（语义检索）
    private let vectorStore = VectorStore.shared
    private var isVectorSearchEnabled = true  // 是否启用向量检索
    
    // MARK: - 初始化
    private init() {
        storageURL = Self.makeStorageURL(namespace: currentNamespace)
        vectorStore.switchNamespace(currentNamespace)
        loadFromDisk()
        
        // 定期自动保存
        startAutoSave()
        
        // 同步已有记忆到向量存储
        syncExistingMemoriesToVectorStore()
    }

    private static func makeStorageURL(namespace: String) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sanitized = sanitizeNamespace(namespace)
        return documentsPath.appendingPathComponent("gaya_memory_\(sanitized).json")
    }

    private static func sanitizeNamespace(_ namespace: String) -> String {
        let trimmed = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        return filtered.isEmpty ? "local" : filtered
    }
    
    // MARK: - 公开接口
    
    /// 添加新的对话记忆
    /// - Parameters:
    ///   - userText: 用户说的话
    ///   - aiText: AI 的回复
    ///   - emotionalTag: 情感标签（可选，由 DeepSeek 分析）
    ///   - topicTags: 话题标签（可选）
    func addMemory(
        userText: String,
        aiText: String,
        emotionalTag: EmotionalTag? = nil,
        topicTags: [String] = []
    ) {
        let importance = calculateImportance(userText: userText, aiText: aiText)
        
        let memory = Memory(
            userText: userText,
            aiText: aiText,
            emotionalTag: emotionalTag,
            topicTags: topicTags,
            importance: importance
        )
        
        // 添加到短期记忆
        shortTermMemory.append(memory)
        print("📝 Added to short-term memory: \(memory.briefDescription)")
        
        // 同时存储到向量数据库（用于语义检索）
        if isVectorSearchEnabled {
            storeMemoryVector(memory)
        }
        
        // 检查短期记忆是否溢出
        if shortTermMemory.count > shortTermLimit {
            promoteToLongTermIfNeeded()
        }
        
        // 从对话中提取用户信息
        extractUserInfo(from: userText)
        
        isDirty = true
    }
    
    /// 存储记忆的向量表示
    private func storeMemoryVector(_ memory: Memory) {
        // 组合用户输入和 AI 回复作为完整上下文
        let fullText = "用户:\(memory.userText) AI:\(memory.aiText)"
        let vectorId = "vec_\(memory.id.uuidString)"
        
        vectorStore.store(
            id: vectorId,
            memoryId: memory.id.uuidString,
            text: fullText
        )
    }
    
    /// 获取短期记忆（最近对话）
    func getShortTermMemories() -> [Memory] {
        return shortTermMemory
    }
    
    /// 获取长期记忆（按重要性排序）
    func getLongTermMemories(limit: Int? = nil) -> [Memory] {
        let sorted = longTermMemory.sorted { $0.compositeScore > $1.compositeScore }
        if let limit = limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }
    
    /// 根据 ID 获取记忆
    func getMemory(byId id: UUID) -> Memory? {
        if let memory = shortTermMemory.first(where: { $0.id == id }) {
            return memory
        }
        return longTermMemory.first(where: { $0.id == id })
    }
    
    /// 根据 ID 列表获取记忆
    func getMemories(byIds ids: [UUID]) -> [Memory] {
        var results: [Memory] = []
        for id in ids {
            if let memory = getMemory(byId: id) {
                results.append(memory)
            }
        }
        return results
    }
    
    /// 获取用户画像
    func getUserProfile() -> UserProfile {
        return userProfile
    }
    
    /// 更新用户画像
    func updateUserProfile(_ update: (inout UserProfile) -> Void) {
        update(&userProfile)
        userProfile.lastUpdated = Date()
        isDirty = true
        print("👤 User profile updated")
    }

    /// 切换记忆命名空间（本地/用户）
    func switchNamespace(_ namespace: String) {
        let normalized = Self.sanitizeNamespace(namespace)
        guard normalized != currentNamespace else { return }

        saveQueue.sync {
            persistToDiskIfNeeded()
        }

        shortTermMemory.removeAll()
        longTermMemory.removeAll()
        userProfile = UserProfile()
        isDirty = false

        currentNamespace = normalized
        storageURL = Self.makeStorageURL(namespace: normalized)

        vectorStore.switchNamespace(normalized)
        loadFromDisk()
        syncExistingMemoriesToVectorStore()

        print("🗂️ Memory namespace switched to: \(normalized)")
    }

    func getCurrentNamespace() -> String {
        currentNamespace
    }
    
    /// 获取所有记忆的摘要列表（用于 DeepSeek 检索）
    func getMemorySummaries() -> [String] {
        var summaries: [String] = []

        let shortTermCandidates = shortTermMemory.filter(shouldIncludeInGeneralConversation)

        // 短期记忆
        for (index, memory) in shortTermCandidates.enumerated() {
            summaries.append("[\(index + 1)] [短期] \(memory.briefDescription)")
        }

        // 长期记忆（按重要性排序）
        let sortedLongTerm = longTermMemory
            .filter(shouldIncludeInGeneralConversation)
            .sorted { $0.compositeScore > $1.compositeScore }

        for (index, memory) in sortedLongTerm.prefix(20).enumerated() {
            let emotionStr = memory.emotionalTag?.emoji ?? ""
            summaries.append("[\(shortTermCandidates.count + index + 1)] [长期] \(emotionStr) \(memory.briefDescription)")
        }

        return summaries
    }

    /// 获取用于记忆检索编号映射的候选列表（顺序需与 getMemorySummaries 一致）
    func getRetrievalCandidates(maxLongTerm: Int = 20) -> [Memory] {
        let shortTermCandidates = shortTermMemory.filter(shouldIncludeInGeneralConversation)
        let longTermCandidates = longTermMemory
            .filter(shouldIncludeInGeneralConversation)
            .sorted { $0.compositeScore > $1.compositeScore }

        return shortTermCandidates + Array(longTermCandidates.prefix(maxLongTerm))
    }
    
    // MARK: - 语义检索（向量搜索）
    
    /// 语义搜索相关记忆
    /// - Parameters:
    ///   - query: 查询文本
    ///   - topK: 返回前 K 个结果
    ///   - threshold: 相似度阈值
    /// - Returns: 按相似度排序的记忆列表
    func semanticSearch(query: String, topK: Int = 5, threshold: Float = 0.3) -> [Memory] {
        guard isVectorSearchEnabled else {
            print("⚠️ Vector search is disabled")
            return []
        }
        
        // 使用向量存储进行语义搜索
        let searchResults = vectorStore.search(query: query, topK: topK, threshold: threshold)
        
        // 将搜索结果转换为 Memory 对象
        var memories: [Memory] = []
        for result in searchResults {
            if let uuid = UUID(uuidString: result.memoryId),
               let memory = getMemory(byId: uuid),
               shouldIncludeInGeneralConversation(memory) {
                memories.append(memory)
            }
        }
        
        print("🔍 Semantic search for '\(query.prefix(30))...': found \(memories.count) results")
        return memories
    }
    
    /// 语义搜索并返回详细结果（包含相似度分数）
    func semanticSearchWithScores(query: String, topK: Int = 5, threshold: Float = 0.3) -> [(memory: Memory, similarity: Float)] {
        guard isVectorSearchEnabled else { return [] }
        
        let searchResults = vectorStore.search(query: query, topK: topK, threshold: threshold)
        
        var results: [(Memory, Float)] = []
        for result in searchResults {
            if let uuid = UUID(uuidString: result.memoryId),
               let memory = getMemory(byId: uuid),
               shouldIncludeInGeneralConversation(memory) {
                results.append((memory, result.similarity))
            }
        }
        
        return results
    }
    
    /// 启用/禁用向量搜索
    func setVectorSearchEnabled(_ enabled: Bool) {
        isVectorSearchEnabled = enabled
        print("🔍 Vector search \(enabled ? "enabled" : "disabled")")
    }
    
    /// 同步已有记忆到向量存储
    private func syncExistingMemoriesToVectorStore() {
        let totalMemories = shortTermMemory.count + longTermMemory.count
        guard totalMemories > 0 else { return }
        
        print("🔄 Syncing \(totalMemories) memories to vector store...")
        
        var syncedCount = 0
        
        // 同步短期记忆
        for memory in shortTermMemory {
            storeMemoryVector(memory)
            syncedCount += 1
        }
        
        // 同步长期记忆
        for memory in longTermMemory {
            storeMemoryVector(memory)
            syncedCount += 1
        }
        
        print("✅ Synced \(syncedCount) memories to vector store")
    }
    
    /// 重建向量索引（清除并重新同步）
    func rebuildVectorIndex() {
        print("🔄 Rebuilding vector index...")
        vectorStore.clearAll()
        syncExistingMemoriesToVectorStore()
        print("✅ Vector index rebuilt")
    }
    
    /// 构建基础上下文（始终包含的部分）
    /// 包括：用户画像 + 最近 N 轮短期记忆
    func buildBaseContext(recentTurns: Int = 2) -> String {
        var context = ""
        
        // 1. 用户画像
        let profileText = userProfile.toNaturalLanguage()
        if !profileText.isEmpty {
            context += "【关于用户】\n\(profileText)\n\n"
        }
        
        // 2. 最近对话（短期记忆的最后几轮）
        let recentMemories = Array(
            shortTermMemory
                .filter(shouldIncludeInGeneralConversation)
                .suffix(recentTurns)
        )
        if !recentMemories.isEmpty {
            context += "【最近对话】\n"
            for memory in recentMemories {
                context += "用户：\(memory.userText)\n"
                context += "Gaya：\(memory.aiText)\n"
            }
            context += "\n"
        }
        
        return context
    }
    
    /// 清空所有记忆
    func clearAllMemory() {
        shortTermMemory.removeAll()
        longTermMemory.removeAll()
        userProfile = UserProfile()
        vectorStore.clearAll()
        isDirty = true
        saveToDisk()
        print("🗑️ All memory cleared")
    }
    
    /// 清空短期记忆（保留长期记忆和用户画像）
    func clearShortTermMemory() {
        shortTermMemory.removeAll()
        isDirty = true
        print("🗑️ Short-term memory cleared")
    }
    
    /// 获取记忆统计信息
    func getStatistics() -> MemoryStatistics {
        return MemoryStatistics(
            shortTermCount: shortTermMemory.count,
            longTermCount: longTermMemory.count,
            userProfileFilled: !userProfile.isEmpty,
            totalMemorySize: calculateStorageSize(),
            lastSaveTime: getLastSaveTime()
        )
    }
    
    // MARK: - 私有方法
    
    /// 计算记忆的重要性评分
    private func calculateImportance(userText: String, aiText: String) -> Float {
        var score: Float = 0.5
        
        // 情感关键词（高权重）
        let emotionalKeywords = [
            "喜欢", "讨厌", "爱", "恨", "开心", "难过", "生气", "害怕",
            "担心", "期待", "感谢", "抱歉", "想念", "怀念", "后悔"
        ]
        for keyword in emotionalKeywords {
            if userText.contains(keyword) {
                score += 0.15
            }
        }
        
        // 个人信息关键词（中高权重）
        let personalKeywords = [
            "我是", "我叫", "我的", "我住", "我工作", "我喜欢", "我讨厌",
            "我妈", "我爸", "我家", "我朋友", "我男朋友", "我女朋友", "我老公", "我老婆"
        ]
        for keyword in personalKeywords {
            if userText.contains(keyword) {
                score += 0.12
            }
        }
        
        // 重要事件关键词（高权重）
        let eventKeywords = [
            "生日", "纪念日", "结婚", "离婚", "怀孕", "生病", "住院",
            "去世", "分手", "升职", "辞职", "毕业", "入学"
        ]
        for keyword in eventKeywords {
            if userText.contains(keyword) {
                score += 0.2
            }
        }
        
        // 长对话可能更重要
        if userText.count > 50 {
            score += 0.05
        }
        if userText.count > 100 {
            score += 0.05
        }
        
        // AI 回复较长，可能是重要话题
        if aiText.count > 100 {
            score += 0.05
        }
        
        return min(score, 1.0)
    }

    private func isPhotoInjectedConversation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return trimmed.hasPrefix(photoInjectionPrefix) ||
               trimmed.contains(photoInjectionInstruction)
    }

    private func shouldIncludeInGeneralConversation(_ memory: Memory) -> Bool {
        return !isPhotoInjectedConversation(memory.userText)
    }
    
    /// 将重要的短期记忆提升到长期记忆
    private func promoteToLongTermIfNeeded() {
        guard shortTermMemory.count > shortTermLimit else { return }
        
        // 移除最旧的记忆
        let oldest = shortTermMemory.removeFirst()
        
        // 如果重要性达到阈值，转入长期记忆
        if oldest.importance >= importanceThreshold {
            longTermMemory.append(oldest)
            print("📤 Promoted to long-term memory (importance: \(oldest.importance))")
            
            // 如果长期记忆超限，移除最不重要的
            if longTermMemory.count > longTermLimit {
                consolidateLongTermMemory()
            }
        } else {
            print("🗑️ Discarded low-importance memory (importance: \(oldest.importance))")
        }
    }
    
    /// 整合长期记忆（移除低分记忆）
    private func consolidateLongTermMemory() {
        // 按综合评分排序，保留高分的
        longTermMemory.sort { $0.compositeScore > $1.compositeScore }
        
        // 移除超出限制的部分
        while longTermMemory.count > longTermLimit {
            let removed = longTermMemory.removeLast()
            print("🗑️ Removed low-score long-term memory: \(removed.briefDescription)")
        }
    }
    
    /// 从用户对话中提取信息
    private func extractUserInfo(from text: String) {
        let nameBefore = userProfile.name
        let hobbyCountBefore = userProfile.hobbies.count
        let peopleCountBefore = userProfile.importantPeople.count
        let factsCountBefore = userProfile.facts.count
        
        // 提取姓名（异步，不阻塞主流程）
        Task {
            await extractName(from: text)
        }
        
        // 提取兴趣爱好
        extractHobbies(from: text)
        
        // 提取重要人物
        extractPeopleInfo(from: text)
        
        // 提取事实信息
        extractFacts(from: text)
        
        // 检查是否有任何信息变化
        let nameChanged = (nameBefore != userProfile.name)
        let hobbiesChanged = (userProfile.hobbies.count > hobbyCountBefore)
        let peopleChanged = (userProfile.importantPeople.count > peopleCountBefore)
        let factsChanged = (userProfile.facts.count > factsCountBefore)
        
        let hasChange = nameChanged || hobbiesChanged || peopleChanged || factsChanged
        
        if hasChange {
            var changes: [String] = []
            if nameChanged { changes.append("姓名: \(userProfile.name ?? "nil")") }
            if hobbiesChanged { changes.append("爱好+\(userProfile.hobbies.count - hobbyCountBefore)") }
            if peopleChanged { changes.append("人物+\(userProfile.importantPeople.count - peopleCountBefore)") }
            if factsChanged { changes.append("事实+\(userProfile.facts.count - factsCountBefore)") }
            
            print("👤 Profile updated: \(changes.joined(separator: ", "))")
            isDirty = true
            
            // 姓名变化是最重要的，立即保存
            if nameChanged {
                print("💾 Name changed - saving immediately!")
                saveToDisk()
            }
        }
    }
    
    /// 智能姓名提取（混合方案：规则预筛选 + LLM 精确判断）
    private func extractName(from text: String) async {
        // ========== 步骤 1: 快速规则预检 ==========
        // 检查是否可能包含姓名声明
        let nameDeclarationKeywords = ["我叫", "名字是", "名字叫", "叫我", "我名"]
        let mayContainName = nameDeclarationKeywords.contains { text.contains($0) }
        
        guard mayContainName else {
            // 不包含姓名声明关键词，直接返回
            return
        }
        
        // ========== 步骤 2: 排除明显的询问句 ==========
        let questionIndicators = ["吗", "呢", "？", "?", "什么", "叫什么", "知道", "记得", "忘了", "你知"]
        let isLikelyQuestion = questionIndicators.contains { text.contains($0) }
        
        // ========== 步骤 3: 明确的声明句，使用正则快速提取 ==========
        if !isLikelyQuestion {
            // 明确的声明句，直接使用正则提取
            if let name = extractNameByRegex(from: text) {
                updateNameIfValid(name)
                return
            }
        }
        
        // ========== 步骤 4: 不确定的情况，调用 LLM 精确判断 ==========
        // 如果可能是询问句，或者正则提取失败，调用 LLM 判断
        if let result = await askLLMToExtractName(from: text) {
            if result.intent == "declare_name", let name = result.extractedName {
                updateNameIfValid(name)
            } else {
                print("👤 LLM determined: \(result.intent), confidence: \(String(format: "%.2f", result.confidence))")
            }
        }
    }
    
    /// 使用正则表达式快速提取姓名（用于明确的声明句）
    private func extractNameByRegex(from text: String) -> String? {
        // 明确的姓名声明模式（高优先级，要求后面紧跟名字）
        let explicitNamePatterns = [
            "我叫([\\u4e00-\\u9fa5a-zA-Z]{2,6})(?:[，。！,.]|$|\\s)",    // 我叫 + 2-6个中文或字母 + 结尾/标点
            "我的名字(?:是|叫)([\\u4e00-\\u9fa5a-zA-Z]{2,6})",          // 我的名字是/叫 + 名字
            "叫我([\\u4e00-\\u9fa5a-zA-Z]{2,6})(?:[，。！,.]|$|\\s)",    // 叫我 + 名字 + 结尾/标点
            "我(?:的)?名字?(?:是|叫)([\\u4e00-\\u9fa5a-zA-Z]{2,6})"     // 我名字是/叫 + 名字（是|叫 必须存在）
        ]
        
        for pattern in explicitNamePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                var name = String(text[range]).trimmingCharacters(in: .whitespaces)
                
                // 移除常见的语气词后缀
                let suffixesToRemove = ["啊", "呀", "哦", "哈", "呢", "吧", "的", "了", "嘛"]
                for suffix in suffixesToRemove {
                    if name.hasSuffix(suffix) && name.count > 2 {
                        name = String(name.dropLast())
                    }
                }
                
                // 验证名字有效性
                if validateName(name) {
                    return name
                }
            }
        }
        
        return nil
    }
    
    /// 验证名字是否有效
    private func validateName(_ name: String) -> Bool {
        // 需要排除的词（这些不是名字）
        let excludeWords = [
            "一个", "一名", "一位", "某个", "那个", "这个", "什么", "谁", "哪个",
            "字", "名字", "名", "知道", "记得", "忘了", "说", "讲", "告诉",
            "什么名", "叫什么", "啥名", "哪位", "怎么", "如何"
        ]
        
        // 不应该出现在名字中的字符
        let invalidChars = ["？", "?", "！", "!", "。", "，", ",", "、", "；", ";", " "]
        
        let containsInvalidChar = invalidChars.contains { name.contains($0) }
        let isExcludedWord = excludeWords.contains(name)
        let containsExcludedWord = excludeWords.contains { name.contains($0) }
        
        return !name.isEmpty &&
               name.count >= 2 &&
               name.count <= 6 &&
               !isExcludedWord &&
               !containsExcludedWord &&
               !containsInvalidChar &&
               !name.contains("是") &&
               !name.contains("的")
    }
    
    /// 更新用户姓名（如果有效）
    private func updateNameIfValid(_ name: String) {
        let oldName = userProfile.name
        // 只有当新名字不同于旧名字时才更新
        if oldName != name {
            userProfile.name = name
            print("👤 Extracted name: \(name)" + (oldName != nil ? " (was: \(oldName!))" : ""))
            isDirty = true
            // 姓名变化是最重要的，立即保存
            saveToDisk()
        }
    }
    
    /// 调用 LLM 判断用户意图并提取姓名
    private func askLLMToExtractName(from text: String) async -> NameExtractionResult? {
        let prompt = """
        判断以下用户输入的意图类型，并提取姓名（如果存在）。

        【用户说】
        \(text)

        【判断任务】
        1. 用户是否在告诉你他的名字？（声明姓名）
        2. 用户是否在询问你是否知道他的名字？（询问姓名）
        3. 其他意图

        【输出格式】(严格JSON格式)
        {
            "intent": "declare_name" 或 "ask_name" 或 "other",
            "extracted_name": "提取的名字或null",
            "confidence": 0.0-1.0
        }

        如果 intent 是 "declare_name"，extracted_name 应该是提取到的名字。
        如果 intent 是 "ask_name" 或 "other"，extracted_name 应该是 null。
        请直接输出JSON，不要其他文字：
        """
        
        // 使用 DeepSeekOrchestrator 调用 API
        guard let response = await DeepSeekOrchestrator.shared.callDeepSeekAPI(prompt: prompt) else {
            print("⚠️ Failed to call LLM for name extraction")
            return nil
        }
        
        // 解析响应
        return parseNameExtractionResponse(response)
    }
    
    /// 解析 LLM 返回的姓名提取结果
    private func parseNameExtractionResponse(_ response: String) -> NameExtractionResult? {
        let cleanResponse = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanResponse.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("⚠️ Failed to parse LLM response: \(response)")
            return nil
        }
        
        let intent = json["intent"] as? String ?? "other"
        let extractedName = json["extracted_name"] as? String
        let confidence = json["confidence"] as? Double ?? 0.0
        
        return NameExtractionResult(
            intent: intent,
            extractedName: extractedName,
            confidence: Float(confidence)
        )
    }
    
    private func extractHobbies(from text: String) {
        let hobbyPatterns = [
            "喜欢(.{1,20}?)(?:[，。！？,.]|$)",
            "爱好是(.{1,20}?)(?:[，。！？,.]|$)",
            "热爱(.{1,20}?)(?:[，。！？,.]|$)"
        ]
        
        for pattern in hobbyPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let hobby = String(text[range]).trimmingCharacters(in: .whitespaces)
                if !hobby.isEmpty && !userProfile.hobbies.contains(hobby) {
                    userProfile.hobbies.append(hobby)
                    print("👤 Extracted hobby: \(hobby)")
                }
            }
        }
    }
    
    private func extractPeopleInfo(from text: String) {
        let peoplePatterns: [(String, String)] = [
            ("我妈(?:妈)?(.{0,10})", "母亲"),
            ("我爸(?:爸)?(.{0,10})", "父亲"),
            ("我(?:男|女)朋友(.{0,10})", "恋人"),
            ("我老(?:公|婆)(.{0,10})", "配偶"),
            ("我朋友(.{1,5})", "朋友")
        ]
        
        for (pattern, relationship) in peoplePatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                // 简单处理：只记录关系类型，不提取名字
                if !userProfile.importantPeople.contains(where: { $0.relationship == relationship }) {
                    let person = PersonInfo(name: "", relationship: relationship, notes: [])
                    userProfile.importantPeople.append(person)
                    print("👤 Extracted relationship: \(relationship)")
                }
            }
        }
    }
    
    private func extractFacts(from text: String) {
        let factPatterns = [
            "我是(.{2,30}?)(?:的|，|。|$)",
            "我在(.{2,30}?)工作",
            "我住在(.{2,30}?)(?:，|。|$)"
        ]
        
        for pattern in factPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let fact = String(text[range]).trimmingCharacters(in: .whitespaces)
                if !fact.isEmpty && fact.count <= 30 && !userProfile.facts.contains(fact) {
                    userProfile.facts.append(fact)
                    // 限制事实数量
                    if userProfile.facts.count > 10 {
                        userProfile.facts.removeFirst()
                    }
                    print("👤 Extracted fact: \(fact)")
                }
            }
        }
    }
    
    // MARK: - 持久化
    
    /// 保存到磁盘
    func saveToDisk() {
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            self.persistToDiskIfNeeded(force: true)
        }
    }

    private func persistToDiskIfNeeded(force: Bool = false) {
        guard force || isDirty else { return }

        let data = MemoryStorageData(
            shortTermMemory: shortTermMemory,
            longTermMemory: longTermMemory,
            userProfile: userProfile,
            lastSaveTime: Date(),
            version: MemoryStorageData.currentVersion
        )

        let targetURL = storageURL

        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: targetURL)
            isDirty = false
            print("💾 Memory saved to disk (\(encoded.count) bytes) namespace=\(currentNamespace)")
        } catch {
            print("❌ Failed to save memory: \(error)")
        }
    }
    
    /// 从磁盘加载
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            print("📂 No existing memory file found, starting fresh")
            return
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode(MemoryStorageData.self, from: data)
            
            shortTermMemory = decoded.shortTermMemory
            longTermMemory = decoded.longTermMemory
            userProfile = decoded.userProfile
            
            print("📂 Memory loaded from disk:")
            print("   - Short-term: \(shortTermMemory.count) memories")
            print("   - Long-term: \(longTermMemory.count) memories")
            print("   - User profile: \(userProfile.isEmpty ? "empty" : "filled")")
        } catch {
            print("❌ Failed to load memory: \(error)")
        }
    }
    
    /// 启动自动保存
    private func startAutoSave() {
        // 每 60 秒检查一次是否需要保存
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self, self.isDirty else { return }
            self.saveToDisk()
        }
    }
    
    /// 获取最后保存时间
    private func getLastSaveTime() -> Date? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: storageURL.path)
        return attributes?[.modificationDate] as? Date
    }
    
    /// 计算存储大小
    private func calculateStorageSize() -> Int {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return 0 }
        let attributes = try? FileManager.default.attributesOfItem(atPath: storageURL.path)
        return attributes?[.size] as? Int ?? 0
    }
}

// MARK: - 记忆统计
struct MemoryStatistics {
    let shortTermCount: Int
    let longTermCount: Int
    let userProfileFilled: Bool
    let totalMemorySize: Int
    let lastSaveTime: Date?
    
    var description: String {
        return """
        📊 Memory Statistics:
        - Short-term: \(shortTermCount) memories
        - Long-term: \(longTermCount) memories
        - User profile: \(userProfileFilled ? "filled" : "empty")
        - Storage size: \(totalMemorySize) bytes
        - Last saved: \(lastSaveTime?.description ?? "never")
        """
    }
}

// MARK: - 姓名提取结果
struct NameExtractionResult {
    let intent: String  // "declare_name", "ask_name", "other"
    let extractedName: String?  // 提取到的名字（如果 intent 是 declare_name）
    let confidence: Float  // 置信度 0.0-1.0
}

// MARK: - 记忆回廊总结结果
struct MemoryCorridorSummaryResult {
    let title: String
    let content: String
}

// MARK: - 记忆回廊总结服务
final class MemoryCorridorSummaryService {
    static let shared = MemoryCorridorSummaryService()

    private let maxTitleCharacters = 10
    private let maxContentCharacters = 1000
    private let maxTurnsForPrompt = 40
    private let perSideTextLimit = 180
    private let weakTitleKeywords = [
        "今日回廊", "回廊日记", "情绪起伏", "日常记录", "我的一天", "今天记录"
    ]
    private let factKeywordGroups: [[String]] = [
        ["女朋友", "男朋友", "对象", "感情", "和好", "分手", "道歉"],
        ["工作", "同事", "老板", "公司", "面试", "加班", "项目"],
        ["考试", "学习", "作业", "成绩", "论文", "学校"],
        ["照片", "图片", "圣诞树", "画面", "相机"],
        ["家人", "父母", "妈妈", "爸爸", "孩子"],
        ["焦虑", "紧张", "担心", "生气", "难过", "压力"]
    ]

    private init() {}

    func summarize(draft: MemoryCorridorDraft) async -> MemoryCorridorSummaryResult {
        let clippedTurns = Array(draft.turns.suffix(maxTurnsForPrompt))
        let dialogueText = buildDialogueText(from: clippedTurns)
        let factHighlights = extractFactHighlights(from: clippedTurns)
        let factCandidates = factHighlights.isEmpty ? "（未抽取到明确事实）" : factHighlights.joined(separator: "、")

        let prompt = """
        你是“记忆回廊”日记总结助手。请基于用户当天与 AI 的对话，生成一篇第一人称日记。

        【硬性要求】
        1) 严格输出 JSON，不要多余解释；
        2) JSON 结构：
           {"title":"10字以内标题","content":"日记正文"}
        3) title 不超过 \(maxTitleCharacters) 个中文字符；
        4) content 不超过 \(maxContentCharacters) 个字符；
        5) 必须是第一人称视角（我）；
        6) 标题必须体现当天关键事实，禁止泛化标题（例如“今日回廊”“情绪起伏”）；
        7) 正文先写事实，再写情绪变化，最后写当下感受；
        8) 正文分段清晰（至少两段），不要使用列表；
        9) 禁止连续标点和混合标点（例如“？；”“。；”“！！！”）。

        【日期】
        \(draft.dateString)

        【关键事实候选】
        \(factCandidates)

        【当日对话】
        \(dialogueText.isEmpty ? "（无）" : dialogueText)
        """

        let message = ArkInputMessage(
            role: "user",
            content: [.inputText(prompt)]
        )

        if let response = await DeepSeekOrchestrator.shared.callDoubaoAPI(
            messages: [message],
            temperature: 0.25,
            maxOutputTokens: 900,
            feature: .memoryCorridorSummary
        ), let parsed = parseSummaryResponse(response, turns: clippedTurns) {
            return parsed
        }

        if await shouldShowRechargePlaceholder() {
            return MemoryCorridorSummaryResult(
                title: "待补写",
                content: "今日对话已记录。当前积分不足，记忆回廊日记会在你恢复可用积分后继续生成。"
            )
        }

        return fallbackSummary(from: clippedTurns)
    }

    private func buildDialogueText(from turns: [DiaryTurn]) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm:ss"

        return turns.map { turn in
            let time = timeFormatter.string(from: turn.timestamp)
            let user = sanitizeDialogueText(turn.userText, limit: perSideTextLimit)
            let ai = sanitizeDialogueText(turn.aiText, limit: perSideTextLimit)
            return "[\(time)] 用户：\(user)\n[\(time)] AI：\(ai)"
        }
        .joined(separator: "\n")
    }

    private func sanitizeDialogueText(_ text: String, limit: Int) -> String {
        let compact = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else { return "（空）" }
        return String(compact.prefix(limit))
    }

    private func parseSummaryResponse(_ response: String, turns: [DiaryTurn]) -> MemoryCorridorSummaryResult? {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return refineSummary(
                titleRaw: json["title"] as? String ?? "",
                contentRaw: json["content"] as? String ?? "",
                turns: turns
            )
        }

        let loose = parseLooseResponse(cleaned)
        guard let loose else { return nil }
        return refineSummary(
            titleRaw: loose.title,
            contentRaw: loose.content,
            turns: turns
        )
    }

    private func parseLooseResponse(_ text: String) -> MemoryCorridorSummaryResult? {
        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        if lines.count == 1 {
            let onlyContent = normalizeContent(lines[0])
            guard !onlyContent.isEmpty else { return nil }
            return MemoryCorridorSummaryResult(
                title: "",
                content: onlyContent
            )
        }

        let possibleTitle = normalizeTitle(lines[0])
        let contentRaw = lines.dropFirst().joined(separator: "\n")
        let content = normalizeContent(contentRaw)
        guard !content.isEmpty else { return nil }

        return MemoryCorridorSummaryResult(
            title: possibleTitle.isEmpty ? fallbackTitle(from: content) : possibleTitle,
            content: content
        )
    }

    private func normalizeTitle(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "标题：", with: "")
            .replacingOccurrences(of: "title:", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let punctuationCleaned = normalizePunctuation(cleaned)
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "：", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(punctuationCleaned.prefix(maxTitleCharacters))
    }

    private func normalizeContent(_ raw: String) -> String {
        let normalizedLineBreaks = raw.replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalizePunctuation(normalizedLineBreaks)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let paragraphSource: String
        if trimmed.contains("\n") {
            let paragraphs = trimmed
                .split(separator: "\n")
                .map { normalizePunctuation($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.isEmpty }
            paragraphSource = paragraphs.joined(separator: "\n\n")
        } else {
            paragraphSource = buildParagraphsFromSentences(trimmed)
        }

        return normalizePunctuation(String(paragraphSource.prefix(maxContentCharacters)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildParagraphsFromSentences(_ text: String) -> String {
        let sentences = splitIntoSentences(text)
        guard !sentences.isEmpty else { return text }

        var paragraphs: [String] = []
        var currentParagraph: [String] = []
        var currentLength = 0

        for sentence in sentences {
            currentParagraph.append(sentence)
            currentLength += sentence.count

            if currentParagraph.count >= 3 || currentLength >= 150 {
                paragraphs.append(currentParagraph.joined())
                currentParagraph.removeAll()
                currentLength = 0
            }
        }

        if !currentParagraph.isEmpty {
            paragraphs.append(currentParagraph.joined())
        }

        return paragraphs.joined(separator: "\n\n")
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        var result: [String] = []
        var buffer = ""
        let delimiters = Set(["。", "！", "？", "；"])

        for char in text {
            buffer.append(char)
            if delimiters.contains(String(char)) {
                let sentence = normalizePunctuation(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    result.append(sentence)
                }
                buffer = ""
            }
        }

        let tail = normalizePunctuation(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            result.append(tail)
        }

        return result
    }

    private func fallbackSummary(from turns: [DiaryTurn]) -> MemoryCorridorSummaryResult {
        let facts = extractFactHighlights(from: turns)
        let content = buildFactDrivenContent(from: turns, facts: facts)
        let title = buildFactDrivenTitle(from: facts, content: content)
        return MemoryCorridorSummaryResult(title: title, content: content)
    }

    private func refineSummary(
        titleRaw: String,
        contentRaw: String,
        turns: [DiaryTurn]
    ) -> MemoryCorridorSummaryResult? {
        let facts = extractFactHighlights(from: turns)
        var content = normalizeContent(contentRaw)
        guard !content.isEmpty else { return nil }

        if !isContentCoherent(content, facts: facts) {
            content = buildFactDrivenContent(from: turns, facts: facts)
        } else if !facts.isEmpty && !containsAnyFact(in: content, facts: facts) {
            let lead = "今天我反复围绕\(facts.prefix(2).joined(separator: "、"))展开。"
            content = normalizeContent("\(lead)\n\n\(content)")
        }

        var title = normalizeTitle(titleRaw)
        if title.isEmpty || isGenericTitle(title) || (!facts.isEmpty && !containsAnyFact(in: title, facts: facts)) {
            title = buildFactDrivenTitle(from: facts, content: content)
        }
        if title.isEmpty {
            title = fallbackTitle(from: content, facts: facts)
        }

        return MemoryCorridorSummaryResult(title: title, content: content)
    }

    private func normalizePunctuation(_ text: String) -> String {
        let asciiNormalized = text
            .replacingOccurrences(of: ",", with: "，")
            .replacingOccurrences(of: ";", with: "；")
            .replacingOccurrences(of: ":", with: "：")
            .replacingOccurrences(of: "!", with: "！")
            .replacingOccurrences(of: "?", with: "？")
            .replacingOccurrences(of: ".", with: "。")
            .replacingOccurrences(of: "\t", with: " ")

        var output = ""
        var previousWasSpace = false

        for rawChar in asciiNormalized {
            let char = canonicalPunctuation(rawChar)

            if char == "\n" {
                while output.last == " " {
                    output.removeLast()
                }
                if output.hasSuffix("\n\n") {
                    continue
                }
                output.append("\n")
                previousWasSpace = false
                continue
            }

            if char == " " {
                if previousWasSpace || output.last == "\n" || output.isEmpty {
                    continue
                }
                output.append(char)
                previousWasSpace = true
                continue
            }

            previousWasSpace = false

            if isSupportedPunctuation(char) {
                while output.last == " " {
                    output.removeLast()
                }
                if let last = output.last, isSupportedPunctuation(last) {
                    output.removeLast()
                    output.append(preferredPunctuation(last, char))
                } else {
                    output.append(char)
                }
                continue
            }

            output.append(char)
        }

        while output.last == " " || output.last == "\n" {
            output.removeLast()
        }

        return output
    }

    private func canonicalPunctuation(_ char: Character) -> Character {
        switch char {
        case "!":
            return "！"
        case "?":
            return "？"
        case ",":
            return "，"
        case ";":
            return "；"
        case ":":
            return "："
        case ".":
            return "。"
        default:
            return char
        }
    }

    private func isSupportedPunctuation(_ char: Character) -> Bool {
        ["。", "！", "？", "；", "，", "："].contains(char)
    }

    private func preferredPunctuation(_ lhs: Character, _ rhs: Character) -> Character {
        let priority: [Character: Int] = [
            "？": 6,
            "！": 5,
            "。": 4,
            "；": 3,
            "，": 2,
            "：": 1
        ]
        return (priority[rhs] ?? 0) >= (priority[lhs] ?? 0) ? rhs : lhs
    }

    private func extractFactHighlights(from turns: [DiaryTurn]) -> [String] {
        var scored: [(text: String, score: Int)] = []

        for turn in turns {
            let cleanUser = turn.userText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanUser.isEmpty else { continue }
            let normalized = normalizePunctuation(cleanUser.replacingOccurrences(of: "\r", with: "\n"))
            let sentences = splitIntoSentences(normalized)
            let candidates = sentences.isEmpty ? [normalized] : sentences

            for sentence in candidates {
                let fact = sanitizeFactSentence(sentence)
                guard !fact.isEmpty, !isTrivialSentence(fact) else { continue }
                let score = scoreFactSentence(fact)
                guard score > 0 else { continue }
                scored.append((fact, score))
            }
        }

        var seen = Set<String>()
        let ordered = scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.text.count > rhs.text.count
            }
            .map(\.text)
            .filter { candidate in
                guard !seen.contains(candidate) else { return false }
                seen.insert(candidate)
                return true
            }

        return Array(ordered.prefix(3))
    }

    private func sanitizeFactSentence(_ raw: String) -> String {
        var text = normalizePunctuation(raw)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return "" }

        let fillerPrefixes = ["那那", "那个", "那", "然后", "就是", "嗯", "呃", "啊", "这个", "其实", "我想", "我在想"]
        var removedPrefix = true
        while removedPrefix {
            removedPrefix = false
            for prefix in fillerPrefixes where text.hasPrefix(prefix) && text.count > prefix.count + 2 {
                text.removeFirst(prefix.count)
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                removedPrefix = true
                break
            }
        }

        while let last = text.last, isSupportedPunctuation(last) {
            text.removeLast()
        }

        if text.count > 22 {
            text = String(text.prefix(22))
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isTrivialSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed.count <= 3 { return true }

        let trivialWords = ["你好", "在吗", "好的", "谢谢", "哈哈", "行吧", "再见", "嗯嗯", "ok"]
        return trivialWords.contains(trimmed.lowercased())
    }

    private func scoreFactSentence(_ text: String) -> Int {
        var score = max(0, 24 - abs(text.count - 11))

        for (index, group) in factKeywordGroups.enumerated() where group.contains(where: { text.contains($0) }) {
            score += max(6, 20 - index * 2)
        }

        if text.contains("怎么") || text.contains("怎么办") || text.contains("为什么") {
            score += 8
        }
        if text.contains("我") {
            score += 2
        }
        if text.contains("你好") {
            score -= 15
        }

        return score
    }

    private func buildFactDrivenContent(from turns: [DiaryTurn], facts: [String]) -> String {
        let userTexts = turns
            .map { $0.userText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let emotionHint = inferEmotionHint(from: userTexts.joined(separator: " "))
        let keyFacts = Array(facts.prefix(2))
        let keyFactText = keyFacts.isEmpty ? "我最在意的那件事" : keyFacts.joined(separator: "、")

        var paragraphs: [String] = []
        paragraphs.append("今天我和 Gaya 的对话主要围绕\(keyFactText)展开，\(emotionHint)。")

        if let firstFact = keyFacts.first {
            if keyFacts.count > 1 {
                paragraphs.append("我一边反复确认\(firstFact)，一边又提到\(keyFacts[1])，想把事情的来龙去脉讲清楚。说出口的过程里，我能感觉到自己从紧绷慢慢变得更冷静。")
            } else {
                paragraphs.append("我反复确认\(firstFact)，其实是在给自己找一个更稳妥的做法。把它讲清楚之后，我心里没那么乱了。")
            }
        } else {
            paragraphs.append("虽然话题不只一个，但我能感觉到自己是在一点点梳理真实困扰，也更愿意正面看待情绪。")
        }

        if let lastAI = turns
            .map({ $0.aiText.trimmingCharacters(in: .whitespacesAndNewlines) })
            .last(where: { !$0.isEmpty }) {
            let cleanAI = sanitizeFactSentence(String(lastAI.prefix(72)))
            if !cleanAI.isEmpty {
                paragraphs.append("听到最后那句回应“\(cleanAI)”，我更确定接下来要先处理什么，也更愿意把情绪放回事实本身。")
            }
        }

        return normalizeContent(paragraphs.joined(separator: "\n\n"))
    }

    private func buildFactDrivenTitle(from facts: [String], content: String) -> String {
        if let factTitle = factTitleCandidate(from: facts) {
            return String(factTitle.prefix(maxTitleCharacters))
        }
        return fallbackTitle(from: content, facts: facts)
    }

    private func factTitleCandidate(from facts: [String]) -> String? {
        let mappings: [(keywords: [String], title: String)] = [
            (["女朋友", "男朋友", "对象", "感情", "道歉"], "关系里的解释"),
            (["工作", "同事", "老板", "项目", "面试"], "工作里的决定"),
            (["考试", "学习", "作业", "成绩"], "学习的压力"),
            (["照片", "图片", "圣诞树", "画面"], "照片里的线索"),
            (["家人", "父母", "妈妈", "爸爸"], "家里的牵挂"),
            (["焦虑", "担心", "紧张", "生气", "难过"], "情绪背后的事")
        ]

        for fact in facts {
            for mapping in mappings where mapping.keywords.contains(where: { fact.contains($0) }) {
                return mapping.title
            }
        }

        guard let firstFact = facts.first else { return nil }
        return shortenFactForTitle(firstFact)
    }

    private func shortenFactForTitle(_ fact: String) -> String {
        var text = sanitizeFactSentence(fact)

        let removablePrefixes = ["我在想", "我想", "我", "今天", "刚才", "其实", "然后", "就是", "应该", "想问"]
        for prefix in removablePrefixes where text.hasPrefix(prefix) && text.count > prefix.count + 1 {
            text.removeFirst(prefix.count)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let range = text.range(of: "怎么") {
            let head = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if head.count >= 2 {
                return "\(String(head.prefix(6)))这件事"
            }
        }

        return String(text.prefix(maxTitleCharacters))
    }

    private func isGenericTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { return true }
        return weakTitleKeywords.contains(where: { normalized.contains($0) })
    }

    private func isContentCoherent(_ content: String, facts: [String]) -> Bool {
        guard content.count >= 40 else { return false }
        let invalidPunctuationPatterns = ["？；", "。；", "；。", "！！", "？？", "。。"]
        if invalidPunctuationPatterns.contains(where: { content.contains($0) }) {
            return false
        }

        let paragraphs = content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard paragraphs.count >= 2 else { return false }
        if facts.isEmpty { return true }
        return containsAnyFact(in: content, facts: facts)
    }

    private func containsAnyFact(in text: String, facts: [String]) -> Bool {
        for fact in facts {
            let anchor = factAnchor(from: fact)
            guard anchor.count >= 2 else { continue }
            if text.contains(anchor) {
                return true
            }
        }
        return false
    }

    private func factAnchor(from fact: String) -> String {
        let cleaned = sanitizeFactSentence(fact).replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return "" }
        return cleaned.count <= 4 ? cleaned : String(cleaned.prefix(4))
    }

    private func inferEmotionHint(from text: String) -> String {
        let mappings: [(keywords: [String], hint: String)] = [
            (["开心", "高兴", "快乐", "惊喜"], "我心里有明显的轻松和开心"),
            (["难过", "伤心", "失落", "委屈"], "我能感觉到一点低落和失落"),
            (["焦虑", "紧张", "担心", "害怕"], "我一直带着一些紧张和担心"),
            (["生气", "愤怒", "烦", "火大"], "我的情绪起伏比较明显")
        ]

        for mapping in mappings {
            if mapping.keywords.contains(where: { text.contains($0) }) {
                return mapping.hint
            }
        }

        return "我把今天的状态说得更清楚了一些"
    }

    private func fallbackTitle(from content: String, facts: [String] = []) -> String {
        if let factTitle = factTitleCandidate(from: facts) {
            return String(factTitle.prefix(maxTitleCharacters))
        }

        let candidates = [
            ("开心", "开心片刻"),
            ("低落", "低落一刻"),
            ("紧张", "心里发紧"),
            ("担心", "有点担心"),
            ("生气", "需要解释")
        ]

        for (keyword, title) in candidates where content.contains(keyword) {
            return String(title.prefix(maxTitleCharacters))
        }

        return String("今天的心事".prefix(maxTitleCharacters))
    }

    private func shouldShowRechargePlaceholder() async -> Bool {
        await MainActor.run {
            MembershipStore.shared.blockingMessage != nil
        }
    }
}

// MARK: - 记忆回廊存储与调度
@MainActor
final class MemoryCorridorStore: ObservableObject {
    static let shared = MemoryCorridorStore()

    @Published private(set) var entries: [MemoryCorridorEntry] = []
    @Published private(set) var currentDraftDateString: String?

    private var currentDraft: MemoryCorridorDraft? {
        didSet {
            currentDraftDateString = currentDraft?.dateString
        }
    }

    private var storageURL: URL
    private var currentNamespace: String = "local"
    private var calendar: Calendar
    private let dateFormatter: DateFormatter
    private var dailyFinalizeTimer: Timer?
    private var autoSaveTimer: Timer?
    private var isDirty = false
    private var finalizingDraftID: UUID?

    private init() {
        var baseCalendar = Calendar(identifier: .gregorian)
        baseCalendar.locale = Locale(identifier: "zh_CN")
        baseCalendar.timeZone = .current
        calendar = baseCalendar

        dateFormatter = DateFormatter()
        dateFormatter.calendar = baseCalendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        storageURL = Self.makeStorageURL(namespace: currentNamespace)

        loadFromDisk()

        if currentDraft == nil {
            createDraftIfNeeded(for: Date())
        }

        startAutoSave()
        scheduleDailyFinalizeTimer(referenceDate: Date())
    }

    private static func sanitizeNamespace(_ namespace: String) -> String {
        let trimmed = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        return filtered.isEmpty ? "local" : filtered
    }

    private static func makeStorageURL(namespace: String) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sanitized = sanitizeNamespace(namespace)
        return documentsPath.appendingPathComponent("gaya_memory_corridor_\(sanitized).json")
    }

    deinit {
        dailyFinalizeTimer?.invalidate()
        autoSaveTimer?.invalidate()
    }

    func handleAppDidBecomeActive() async {
        await finalizeExpiredDraftIfNeeded(
            reason: "app-active",
            referenceDate: Date()
        )
        scheduleDailyFinalizeTimer(referenceDate: Date())
    }

    func switchNamespace(_ namespace: String) async {
        let normalized = Self.sanitizeNamespace(namespace)
        guard normalized != currentNamespace else { return }

        saveToDisk()

        dailyFinalizeTimer?.invalidate()
        autoSaveTimer?.invalidate()
        dailyFinalizeTimer = nil
        autoSaveTimer = nil

        entries = []
        currentDraft = nil
        isDirty = false
        finalizingDraftID = nil

        currentNamespace = normalized
        storageURL = Self.makeStorageURL(namespace: normalized)

        loadFromDisk()
        if currentDraft == nil {
            createDraftIfNeeded(for: Date())
        }

        startAutoSave()
        scheduleDailyFinalizeTimer(referenceDate: Date())

        print("🗂️ MemoryCorridor namespace switched to: \(normalized)")
    }

    func recordConversationTurn(
        userText: String,
        aiText: String,
        timestamp: Date = Date()
    ) async {
        let cleanUser = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAI = aiText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty || !cleanAI.isEmpty else { return }

        await finalizeExpiredDraftIfNeeded(
            reason: "before-record",
            referenceDate: timestamp
        )

        guard var draft = currentDraft else { return }
        let turn = DiaryTurn(timestamp: timestamp, userText: cleanUser, aiText: cleanAI)
        draft.turns.append(turn)
        draft.updatedAt = timestamp
        currentDraft = draft
        isDirty = true
    }

    func getEntriesInCreationOrder() -> [MemoryCorridorEntry] {
        uniqueEntriesByDate(entries).sorted { $0.createdAt < $1.createdAt }
    }

    func saveToDisk() {
        guard isDirty else { return }

        let normalizedEntries = uniqueEntriesByDate(entries).sorted { $0.createdAt < $1.createdAt }
        if normalizedEntries.count != entries.count {
            entries = normalizedEntries
        }

        let data = MemoryCorridorStorageData(
            entries: normalizedEntries,
            currentDraft: currentDraft,
            lastSaveTime: Date(),
            version: MemoryCorridorStorageData.currentVersion
        )

        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: storageURL, options: .atomic)
            isDirty = false
            print("💾 MemoryCorridor saved (\(encoded.count) bytes)")
        } catch {
            print("❌ MemoryCorridor save failed: \(error)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            print("📂 No MemoryCorridor file found, starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode(MemoryCorridorStorageData.self, from: data)
            let deduped = uniqueEntriesByDate(decoded.entries).sorted { $0.createdAt < $1.createdAt }
            if deduped.count != decoded.entries.count {
                let removed = decoded.entries.count - deduped.count
                print("🧹 MemoryCorridor removed duplicate entries: \(removed)")
                isDirty = true
            }
            entries = deduped
            currentDraft = decoded.currentDraft
            print("📂 MemoryCorridor loaded: \(entries.count) entries")
            if let draft = currentDraft {
                print("   - current draft date: \(draft.dateString), turns: \(draft.turns.count)")
            }
        } catch {
            print("❌ MemoryCorridor load failed: \(error)")
        }
    }

    private func startAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isDirty else { return }
                self.saveToDisk()
            }
        }
    }

    private func scheduleDailyFinalizeTimer(referenceDate: Date) {
        dailyFinalizeTimer?.invalidate()

        let fireDate = nextFinalizeDate(after: referenceDate)
        let interval = max(1, fireDate.timeIntervalSince(referenceDate))

        dailyFinalizeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.handleDailyFinalizeTimerFired()
            }
        }

        print("⏰ MemoryCorridor finalize timer scheduled at: \(fireDate)")
    }

    private func handleDailyFinalizeTimerFired() async {
        await finalizeExpiredDraftIfNeeded(
            reason: "daily-timer",
            referenceDate: Date()
        )
        scheduleDailyFinalizeTimer(referenceDate: Date())
    }

    private func finalizeExpiredDraftIfNeeded(
        reason: String,
        referenceDate: Date
    ) async {
        guard let draft = currentDraft else {
            createDraftIfNeeded(for: referenceDate)
            return
        }
        guard shouldFinalize(draft: draft, referenceDate: referenceDate) else { return }
        guard finalizingDraftID != draft.id else {
            print("⏳ MemoryCorridor finalization already running for \(draft.dateString)")
            return
        }
        await finalizeDraft(draft, reason: reason)

        let nextDraftAnchor: Date
        if referenceDate >= draft.windowEnd {
            nextDraftAnchor = referenceDate.addingTimeInterval(1)
        } else {
            nextDraftAnchor = referenceDate
        }
        createDraftIfNeeded(for: nextDraftAnchor)
    }

    private func finalizeDraft(_ draft: MemoryCorridorDraft, reason: String) async {
        guard currentDraft?.id == draft.id else { return }
        guard finalizingDraftID == nil || finalizingDraftID == draft.id else { return }
        finalizingDraftID = draft.id
        defer {
            if finalizingDraftID == draft.id {
                finalizingDraftID = nil
            }
        }

        if entries.contains(where: { $0.dateString == draft.dateString }) {
            print("⚠️ MemoryCorridor duplicate date skipped: \(draft.dateString)")
            currentDraft = nil
            isDirty = true
            return
        }

        guard draft.hasConversation else {
            print("🗂️ MemoryCorridor skip empty day: \(draft.dateString)")
            currentDraft = nil
            isDirty = true
            saveToDisk()
            return
        }

        print("📝 Finalizing MemoryCorridor draft (\(draft.dateString), reason: \(reason))")
        let summary = await MemoryCorridorSummaryService.shared.summarize(draft: draft)
        guard currentDraft?.id == draft.id else { return }

        if entries.contains(where: { $0.dateString == draft.dateString }) {
            print("⚠️ MemoryCorridor duplicate date skipped after summary: \(draft.dateString)")
            currentDraft = nil
            isDirty = true
            return
        }

        let entry = MemoryCorridorEntry(
            title: summary.title,
            dateString: draft.dateString,
            content: summary.content,
            createdAt: draft.windowEnd,
            sourceTurnCount: draft.turns.count
        )

        entries.append(entry)
        entries = uniqueEntriesByDate(entries).sorted { $0.createdAt < $1.createdAt }
        currentDraft = nil
        isDirty = true
        saveToDisk()
    }

    private func shouldFinalize(draft: MemoryCorridorDraft, referenceDate: Date) -> Bool {
        let currentDateKey = dateString(for: referenceDate)
        return draft.dateString < currentDateKey || referenceDate >= draft.windowEnd
    }

    private func createDraftIfNeeded(for referenceDate: Date) {
        let expectedDate = dateString(for: referenceDate)

        if let draft = currentDraft, draft.dateString == expectedDate {
            return
        }

        let window = dayWindow(for: referenceDate)
        currentDraft = MemoryCorridorDraft(
            dateString: expectedDate,
            windowStart: window.start,
            windowEnd: window.end,
            createdAt: referenceDate
        )
        isDirty = true
        print("🆕 MemoryCorridor draft created for \(expectedDate)")
    }

    private func dayWindow(for date: Date) -> (start: Date, end: Date) {
        let dayStart = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .second, value: 1, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart)
            ?? dayStart.addingTimeInterval(86_399)
        return (start, end)
    }

    private func nextFinalizeDate(after date: Date) -> Date {
        let todayWindow = dayWindow(for: date)
        if date < todayWindow.end {
            return todayWindow.end
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)
            ?? date.addingTimeInterval(86_400)
        return dayWindow(for: tomorrow).end
    }

    private func dateString(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private func uniqueEntriesByDate(_ source: [MemoryCorridorEntry]) -> [MemoryCorridorEntry] {
        var table: [String: MemoryCorridorEntry] = [:]

        for entry in source {
            if let existing = table[entry.dateString] {
                table[entry.dateString] = preferredEntry(existing, entry)
            } else {
                table[entry.dateString] = entry
            }
        }

        return Array(table.values)
    }

    private func preferredEntry(_ lhs: MemoryCorridorEntry, _ rhs: MemoryCorridorEntry) -> MemoryCorridorEntry {
        if lhs.sourceTurnCount != rhs.sourceTurnCount {
            return lhs.sourceTurnCount > rhs.sourceTurnCount ? lhs : rhs
        }
        if lhs.content.count != rhs.content.count {
            return lhs.content.count > rhs.content.count ? lhs : rhs
        }
        return lhs.createdAt <= rhs.createdAt ? lhs : rhs
    }
}
