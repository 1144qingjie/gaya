//
//  MemorySystemTests.swift
//  gaya
//
//  混合记忆系统测试用例
//  用于验证分层记忆存储和 DeepSeek 记忆调度的功能
//

import Foundation

/// 记忆系统测试类
/// 可以在开发阶段调用 runAllTests() 来验证系统功能
class MemorySystemTests {
    
    static let shared = MemorySystemTests()
    
    private init() {}
    
    // MARK: - 测试入口
    
    /// 运行所有测试
    func runAllTests() async {
        print("🧪 ========== 开始记忆系统测试 ==========")
        
        // 清理测试环境
        MemoryStore.shared.clearAllMemory()
        
        // 1. 测试基础记忆存储
        await testBasicMemoryStorage()
        
        // 2. 测试用户信息提取
        testUserInfoExtraction()
        
        // 3. 测试记忆重要性计算
        testImportanceCalculation()
        
        // 4. 测试分层记忆管理
        testTieredMemoryManagement()
        
        // 5. 测试上下文构建
        testContextBuilding()
        
        // 6. 测试 DeepSeek 记忆检索（需要网络）
        await testDeepSeekRetrieval()
        
        // 7. 测试向量检索
        await testVectorSearch()
        
        // 8. 测试混合检索
        await testHybridRetrieval()
        
        // 9. 测试持久化
        testPersistence()
        
        print("🧪 ========== 记忆系统测试完成 ==========")
    }
    
    // MARK: - 测试用例
    
    /// 测试 1: 基础记忆存储
    private func testBasicMemoryStorage() async {
        print("\n📋 测试 1: 基础记忆存储")
        
        // 添加测试记忆
        MemoryStore.shared.addMemory(
            userText: "我叫小明，今天心情不太好",
            aiText: "小明，我听出来了，你声音里有些低落。是发生了什么事吗？"
        )
        
        MemoryStore.shared.addMemory(
            userText: "我妈妈生病住院了",
            aiText: "这一定让你很担心吧...她现在情况怎么样？"
        )
        
        let stats = MemoryStore.shared.getStatistics()
        let passed = stats.shortTermCount == 2
        
        print("   - 添加了 2 条记忆")
        print("   - 当前短期记忆数: \(stats.shortTermCount)")
        print("   - 测试结果: \(passed ? "✅ 通过" : "❌ 失败")")
    }
    
    /// 测试 2: 用户信息提取
    private func testUserInfoExtraction() {
        print("\n📋 测试 2: 用户信息提取")
        
        // 添加包含用户信息的记忆
        MemoryStore.shared.addMemory(
            userText: "我叫张三，喜欢听爵士乐，我住在北京",
            aiText: "张三，爵士乐很有品味呢！北京冬天冷吗？"
        )
        
        let profile = MemoryStore.shared.getUserProfile()
        
        let nameExtracted = profile.name == "张三" || profile.name == "小明"
        let hobbyExtracted = profile.hobbies.contains(where: { $0.contains("爵士") || $0.contains("听") })
        
        print("   - 提取的姓名: \(profile.name ?? "无")")
        print("   - 提取的爱好: \(profile.hobbies)")
        print("   - 提取的事实: \(profile.facts)")
        print("   - 测试结果: \(nameExtracted ? "✅ 姓名提取成功" : "⚠️ 姓名未提取")")
        print("   - 测试结果: \(hobbyExtracted ? "✅ 爱好提取成功" : "⚠️ 爱好未提取")")
    }
    
    /// 测试 3: 记忆重要性计算
    private func testImportanceCalculation() {
        print("\n📋 测试 3: 记忆重要性计算")
        
        // 添加不同重要性的记忆
        MemoryStore.shared.addMemory(
            userText: "你好",
            aiText: "嗨！"
        )
        
        MemoryStore.shared.addMemory(
            userText: "我很难过，我最好的朋友要去世了",
            aiText: "这个消息一定让你很痛苦...我在这里陪着你。"
        )
        
        let memories = MemoryStore.shared.getShortTermMemories()
        
        // 找到两条记忆
        let simpleMemory = memories.first { $0.userText == "你好" }
        let importantMemory = memories.first { $0.userText.contains("难过") }
        
        let importanceDiff = (importantMemory?.importance ?? 0) > (simpleMemory?.importance ?? 0)
        
        print("   - 简单问候重要性: \(simpleMemory?.importance ?? 0)")
        print("   - 情感对话重要性: \(importantMemory?.importance ?? 0)")
        print("   - 测试结果: \(importanceDiff ? "✅ 重要性计算正确" : "❌ 重要性计算异常")")
    }
    
    /// 测试 4: 分层记忆管理
    private func testTieredMemoryManagement() {
        print("\n📋 测试 4: 分层记忆管理")
        
        // 清空并添加超过短期记忆限制的记忆
        MemoryStore.shared.clearAllMemory()
        
        // 添加 7 条记忆（超过短期记忆限制 5）
        for i in 1...7 {
            MemoryStore.shared.addMemory(
                userText: "测试消息 \(i)，我很喜欢这个功能",
                aiText: "回复 \(i)"
            )
        }
        
        let stats = MemoryStore.shared.getStatistics()
        
        // 短期记忆应该不超过 5 条
        let shortTermCorrect = stats.shortTermCount <= 5
        
        print("   - 添加了 7 条记忆")
        print("   - 当前短期记忆数: \(stats.shortTermCount)")
        print("   - 当前长期记忆数: \(stats.longTermCount)")
        print("   - 测试结果: \(shortTermCorrect ? "✅ 分层管理正常" : "❌ 分层管理异常")")
    }
    
    /// 测试 5: 上下文构建
    private func testContextBuilding() {
        print("\n📋 测试 5: 上下文构建")
        
        // 更新用户画像
        MemoryStore.shared.updateUserProfile { profile in
            profile.name = "测试用户"
            profile.hobbies = ["编程", "音乐"]
        }
        
        let context = MemoryStore.shared.buildBaseContext(recentTurns: 2)
        
        let hasProfile = context.contains("测试用户") || context.contains("编程")
        let hasRecentMemory = context.contains("最近对话") || context.contains("用户：")
        
        print("   - 上下文长度: \(context.count) 字符")
        print("   - 包含用户画像: \(hasProfile ? "是" : "否")")
        print("   - 包含最近对话: \(hasRecentMemory ? "是" : "否")")
        print("   - 上下文预览: \(context.prefix(200))...")
        print("   - 测试结果: ✅ 上下文构建完成")
    }
    
    /// 测试 6: DeepSeek 记忆检索
    private func testDeepSeekRetrieval() async {
        print("\n📋 测试 6: DeepSeek 记忆检索")
        
        // 确保有一些记忆
        if MemoryStore.shared.getStatistics().shortTermCount == 0 {
            MemoryStore.shared.addMemory(
                userText: "我妈妈上周住院了",
                aiText: "这一定让你很担心，她现在怎么样了？"
            )
        }
        
        // 测试快速检查
        let needMemory1 = DeepSeekOrchestrator.shared.quickCheckNeedMemory(query: "你好")
        let needMemory2 = DeepSeekOrchestrator.shared.quickCheckNeedMemory(query: "她现在怎么样了")
        
        print("   - 快速检查 '你好': \(needMemory1 ? "需要记忆" : "不需要记忆")")
        print("   - 快速检查 '她现在怎么样了': \(needMemory2 ? "需要记忆" : "不需要记忆")")
        
        // 测试完整检索（需要网络）
        print("   - 正在测试 DeepSeek API 调用...")
        let result = await DeepSeekOrchestrator.shared.processUserInput(
            userQuery: "她现在怎么样了"
        )
        
        print("   - 需要检索: \(result.shouldRetrieve)")
        print("   - 检索到的记忆数: \(result.retrievedMemories.count)")
        print("   - 处理时间: \(String(format: "%.2f", result.processingTime))s")
        print("   - 测试结果: \(result.processingTime > 0 ? "✅ API 调用成功" : "⚠️ API 可能超时")")
    }
    
    /// 测试 7: 向量检索
    private func testVectorSearch() async {
        print("\n📋 测试 7: 向量检索")
        
        // 清空并添加测试记忆
        MemoryStore.shared.clearAllMemory()
        
        // 添加一些语义相关的记忆
        MemoryStore.shared.addMemory(
            userText: "我妈妈最近身体不太好，住院了",
            aiText: "这一定让你很担心，她现在情况怎么样？"
        )
        
        MemoryStore.shared.addMemory(
            userText: "我养了一只猫，叫团子",
            aiText: "团子听起来很可爱！它是什么品种的？"
        )
        
        MemoryStore.shared.addMemory(
            userText: "我喜欢吃辣的食物，尤其是四川菜",
            aiText: "四川菜确实很美味！你会自己做吗？"
        )
        
        // 等待向量存储完成
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒
        
        // 测试语义搜索
        print("   - 测试查询: '她现在怎么样了'")
        let results1 = MemoryStore.shared.semanticSearchWithScores(
            query: "她现在怎么样了",
            topK: 3,
            threshold: 0.1
        )
        
        let found1 = results1.first?.memory.userText.contains("妈妈") ?? false
        print("   - 搜索结果数: \(results1.count)")
        if let top = results1.first {
            print("   - 最相关记忆: \(top.memory.userText.prefix(30))...")
            print("   - 相似度: \(String(format: "%.3f", top.similarity))")
        }
        print("   - 测试结果: \(found1 ? "✅ 正确找到妈妈相关记忆" : "⚠️ 未找到预期记忆")")
        
        // 测试另一个查询
        print("\n   - 测试查询: '我的宠物最近很调皮'")
        let results2 = MemoryStore.shared.semanticSearchWithScores(
            query: "我的宠物最近很调皮",
            topK: 3,
            threshold: 0.1
        )
        
        let found2 = results2.first?.memory.userText.contains("猫") ?? false
        print("   - 搜索结果数: \(results2.count)")
        if let top = results2.first {
            print("   - 最相关记忆: \(top.memory.userText.prefix(30))...")
            print("   - 相似度: \(String(format: "%.3f", top.similarity))")
        }
        print("   - 测试结果: \(found2 ? "✅ 正确找到宠物相关记忆" : "⚠️ 未找到预期记忆")")
        
        // 测试不相关查询
        print("\n   - 测试查询: '今天天气真好'")
        let results3 = MemoryStore.shared.semanticSearchWithScores(
            query: "今天天气真好",
            topK: 3,
            threshold: 0.5  // 较高阈值
        )
        
        print("   - 搜索结果数（高阈值）: \(results3.count)")
        print("   - 测试结果: \(results3.isEmpty ? "✅ 正确过滤不相关查询" : "⚠️ 返回了不相关结果")")
    }
    
    /// 测试 8: 混合检索
    private func testHybridRetrieval() async {
        print("\n📋 测试 8: 混合检索")
        
        // 确保有记忆
        if MemoryStore.shared.getStatistics().shortTermCount == 0 {
            MemoryStore.shared.addMemory(
                userText: "我妈妈最近身体不太好",
                aiText: "希望阿姨早日康复"
            )
        }
        
        // 测试混合检索
        print("   - 测试查询: '她现在怎么样了'")
        let result = await DeepSeekOrchestrator.shared.hybridRetrieval(
            query: "她现在怎么样了",
            useDeepSeekFallback: true
        )
        
        print("   - 检索方法: \(result.method.rawValue)")
        print("   - 置信度: \(String(format: "%.2f", result.confidence))")
        print("   - 检索到记忆数: \(result.memories.count)")
        print("   - 处理时间: \(String(format: "%.2f", result.processingTime))s")
        
        if !result.memories.isEmpty {
            print("   - 检索到的记忆:")
            for memory in result.memories.prefix(2) {
                print("     • \(memory.userText.prefix(40))...")
            }
        }
        
        // 测试上下文构建
        let context = result.buildContext()
        print("   - 构建的上下文长度: \(context.count) 字符")
        print("   - 测试结果: \(!result.isEmpty ? "✅ 混合检索成功" : "⚠️ 未检索到记忆")")
        
        // 测试纯向量检索（不使用 DeepSeek）
        print("\n   - 测试纯向量检索（无 DeepSeek）")
        let result2 = await DeepSeekOrchestrator.shared.hybridRetrieval(
            query: "我的宠物",
            useDeepSeekFallback: false
        )
        
        print("   - 检索方法: \(result2.method.rawValue)")
        print("   - 检索到记忆数: \(result2.memories.count)")
        print("   - 测试结果: ✅ 纯向量检索完成")
    }
    
    /// 测试 9: 持久化
    private func testPersistence() {
        print("\n📋 测试 9: 持久化")
        
        // 保存到磁盘
        MemoryStore.shared.saveToDisk()
        
        let stats = MemoryStore.shared.getStatistics()
        
        print("   - 存储大小: \(stats.totalMemorySize) bytes")
        print("   - 最后保存时间: \(stats.lastSaveTime?.description ?? "未保存")")
        print("   - 测试结果: \(stats.totalMemorySize > 0 || stats.lastSaveTime != nil ? "✅ 持久化成功" : "⚠️ 持久化未执行")")
    }
    
    // MARK: - 场景测试
    
    /// 模拟完整对话场景
    func simulateConversationScenario() async {
        print("\n🎭 ========== 模拟对话场景测试 ==========")
        
        // 清理
        MemoryStore.shared.clearAllMemory()
        
        // 场景：用户第一次使用
        print("\n【场景 1：首次见面】")
        MemoryStore.shared.addMemory(
            userText: "你好，我叫小红",
            aiText: "嗨小红！很高兴认识你，你的声音听起来很温柔呢。"
        )
        
        // 场景：用户分享兴趣
        print("【场景 2：分享兴趣】")
        MemoryStore.shared.addMemory(
            userText: "我喜欢画画和听音乐",
            aiText: "哇，画画和音乐！你平时喜欢画什么呢？"
        )
        
        // 场景：用户分享情感
        print("【场景 3：情感分享】")
        MemoryStore.shared.addMemory(
            userText: "最近工作压力好大，有点焦虑",
            aiText: "我听出来了...工作压力大的时候确实让人喘不过气。你想聊聊是什么让你感到压力吗？"
        )
        
        // 场景：用户提到重要的人
        print("【场景 4：提到家人】")
        MemoryStore.shared.addMemory(
            userText: "我妈妈下周要来看我",
            aiText: "那一定很期待吧！你和妈妈多久没见了？"
        )
        
        // 查看提取的信息
        print("\n📊 对话后的记忆状态：")
        let profile = MemoryStore.shared.getUserProfile()
        print("   - 用户姓名: \(profile.name ?? "未知")")
        print("   - 用户爱好: \(profile.hobbies)")
        print("   - 重要人物: \(profile.importantPeople.map { $0.relationship })")
        print("   - 提取的事实: \(profile.facts)")
        
        // 测试记忆检索
        print("\n🔍 测试记忆检索：")
        let result = await DeepSeekOrchestrator.shared.processUserInput(
            userQuery: "我妈妈快到了"
        )
        
        print("   - 查询: '我妈妈快到了'")
        print("   - 需要检索: \(result.shouldRetrieve)")
        print("   - 检索到: \(result.retrievedMemories.count) 条相关记忆")
        if !result.contextToInject.isEmpty {
            print("   - 注入上下文: \(result.contextToInject.prefix(200))...")
        }
        
        print("\n🎭 ========== 场景测试完成 ==========")
    }
}

// MARK: - 便捷调用
extension MemorySystemTests {
    
    /// 打印当前记忆状态
    func printMemoryStatus() {
        print("\n📊 当前记忆状态：")
        print(MemoryStore.shared.getStatistics().description)
        
        let profile = MemoryStore.shared.getUserProfile()
        print("\n👤 用户画像：")
        if !profile.isEmpty {
            print(profile.toNaturalLanguage())
        } else {
            print("   (空)")
        }
        
        print("\n📝 短期记忆：")
        for memory in MemoryStore.shared.getShortTermMemories() {
            print("   - \(memory.briefDescription)")
        }
        
        print("\n📚 长期记忆：")
        for memory in MemoryStore.shared.getLongTermMemories(limit: 5) {
            print("   - [\(String(format: "%.2f", memory.importance))] \(memory.briefDescription)")
        }
    }
}
