//
//  LocalEmbedding.swift
//  gaya
//
//  本地文本嵌入服务
//  使用 Apple NaturalLanguage 框架实现中文文本向量化
//

import Foundation
import NaturalLanguage
import Accelerate

/// 本地文本嵌入服务
/// 将文本转换为向量表示，用于语义相似度计算
class LocalEmbedding {
    
    // MARK: - Singleton
    static let shared = LocalEmbedding()
    
    // MARK: - 配置
    let embeddingDimension = 512  // 向量维度
    
    // MARK: - NaturalLanguage 组件
    private var chineseEmbedding: NLEmbedding?
    private var englishEmbedding: NLEmbedding?
    private let tagger: NLTagger
    
    // MARK: - 缓存
    private var embeddingCache: [String: [Float]] = [:]
    private let cacheLimit = 1000
    private let cacheQueue = DispatchQueue(label: "com.gaya.embedding.cache")
    
    // MARK: - 初始化
    private init() {
        // 初始化分词器
        tagger = NLTagger(tagSchemes: [.tokenType, .language])
        
        // 加载词嵌入模型
        loadEmbeddings()
        
        print("🧮 LocalEmbedding initialized")
        print("   - Chinese embedding: \(chineseEmbedding != nil ? "✅" : "❌")")
        print("   - English embedding: \(englishEmbedding != nil ? "✅" : "❌")")
    }
    
    /// 加载词嵌入模型
    private func loadEmbeddings() {
        // 尝试加载中文词嵌入
        chineseEmbedding = NLEmbedding.wordEmbedding(for: .simplifiedChinese)
        
        // 尝试加载英文词嵌入（用于混合语言）
        englishEmbedding = NLEmbedding.wordEmbedding(for: .english)
        
        // 如果中文不可用，尝试其他语言
        if chineseEmbedding == nil {
            print("⚠️ Chinese embedding not available, trying alternatives...")
            // NLEmbedding 在某些设备上可能不支持中文
            // 这种情况下使用基于字符的简化嵌入
        }
    }
    
    // MARK: - 公开接口
    
    /// 获取文本的向量表示
    /// - Parameter text: 输入文本
    /// - Returns: 向量数组，如果无法生成则返回 nil
    func encode(_ text: String) -> [Float]? {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return nil }
        
        // 检查缓存
        if let cached = getCachedEmbedding(for: normalizedText) {
            return cached
        }
        
        // 生成嵌入
        let embedding: [Float]?
        
        if chineseEmbedding != nil || englishEmbedding != nil {
            // 使用 NLEmbedding 的词级嵌入
            embedding = generateWordLevelEmbedding(for: normalizedText)
        } else {
            // 降级：使用基于字符的简化嵌入
            embedding = generateCharacterBasedEmbedding(for: normalizedText)
        }
        
        // 缓存结果
        if let embedding = embedding {
            cacheEmbedding(embedding, for: normalizedText)
        }
        
        return embedding
    }
    
    /// 计算两个文本的语义相似度
    /// - Returns: 相似度分数 [0, 1]，1 表示完全相似
    func similarity(text1: String, text2: String) -> Float {
        guard let v1 = encode(text1),
              let v2 = encode(text2) else {
            return 0
        }
        return cosineSimilarity(v1, v2)
    }
    
    /// 计算两个向量的余弦相似度
    func cosineSimilarity(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count, !v1.isEmpty else { return 0 }
        
        var dotProduct: Float = 0
        var norm1: Float = 0
        var norm2: Float = 0
        
        // 使用 Accelerate 框架加速计算
        vDSP_dotpr(v1, 1, v2, 1, &dotProduct, vDSP_Length(v1.count))
        vDSP_dotpr(v1, 1, v1, 1, &norm1, vDSP_Length(v1.count))
        vDSP_dotpr(v2, 1, v2, 1, &norm2, vDSP_Length(v2.count))
        
        let denominator = sqrt(norm1) * sqrt(norm2)
        guard denominator > 0 else { return 0 }
        
        return dotProduct / denominator
    }
    
    /// 批量计算相似度，返回排序后的结果
    func findMostSimilar(query: String, candidates: [(id: String, text: String)], topK: Int = 5) -> [(id: String, text: String, similarity: Float)] {
        guard let queryVector = encode(query) else { return [] }
        
        var results: [(String, String, Float)] = []
        
        for candidate in candidates {
            if let candidateVector = encode(candidate.text) {
                let sim = cosineSimilarity(queryVector, candidateVector)
                results.append((candidate.id, candidate.text, sim))
            }
        }
        
        // 按相似度降序排序
        results.sort { $0.2 > $1.2 }
        
        return Array(results.prefix(topK))
    }
    
    // MARK: - 词级嵌入（使用 NLEmbedding）
    
    /// 使用 NLEmbedding 生成词级嵌入
    private func generateWordLevelEmbedding(for text: String) -> [Float]? {
        tagger.string = text
        
        var wordVectors: [[Float]] = []
        var wordWeights: [Float] = []
        
        // 遍历所有词
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                           unit: .word,
                           scheme: .tokenType) { tag, range in
            let word = String(text[range]).lowercased()
            
            // 跳过标点和空格
            guard tag != .punctuation && tag != .whitespace else {
                return true
            }
            
            // 尝试获取词向量
            if let vector = getWordVector(for: word) {
                wordVectors.append(vector)
                // 根据词的重要性赋予权重（简化：所有词权重相同）
                wordWeights.append(1.0)
            }
            
            return true
        }
        
        // 如果没有词向量，使用字符级嵌入
        guard !wordVectors.isEmpty else {
            return generateCharacterBasedEmbedding(for: text)
        }
        
        // 加权平均
        return weightedAverageVectors(wordVectors, weights: wordWeights)
    }
    
    /// 获取单个词的向量
    private func getWordVector(for word: String) -> [Float]? {
        // 先尝试中文
        if let embedding = chineseEmbedding,
           let vector = embedding.vector(for: word) {
            return vector.map { Float($0) }
        }
        
        // 再尝试英文
        if let embedding = englishEmbedding,
           let vector = embedding.vector(for: word) {
            return vector.map { Float($0) }
        }
        
        return nil
    }
    
    /// 加权平均向量
    private func weightedAverageVectors(_ vectors: [[Float]], weights: [Float]) -> [Float]? {
        guard !vectors.isEmpty, vectors.count == weights.count else { return nil }
        
        let dimension = vectors[0].count
        var result = [Float](repeating: 0, count: dimension)
        var totalWeight: Float = 0
        
        for (vector, weight) in zip(vectors, weights) {
            guard vector.count == dimension else { continue }
            totalWeight += weight
            
            for i in 0..<dimension {
                result[i] += vector[i] * weight
            }
        }
        
        guard totalWeight > 0 else { return nil }
        
        // 归一化
        for i in 0..<dimension {
            result[i] /= totalWeight
        }
        
        // L2 归一化
        return l2Normalize(result)
    }
    
    // MARK: - 字符级嵌入（降级方案）
    
    /// 基于字符的简化嵌入（当 NLEmbedding 不可用时使用）
    /// 使用字符的 Unicode 值和 TF-IDF 思想生成向量
    private func generateCharacterBasedEmbedding(for text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: embeddingDimension)
        
        let chars = Array(text.unicodeScalars)
        guard !chars.isEmpty else { return vector }
        
        // 使用多个哈希函数生成稀疏向量
        for (i, char) in chars.enumerated() {
            let charValue = Int(char.value)
            
            // 位置编码
            let positionWeight = 1.0 / (1.0 + Float(i) * 0.1)
            
            // 多个哈希函数
            for hashIdx in 0..<4 {
                let hash = (charValue * (hashIdx + 1) * 31 + hashIdx * 17) % embeddingDimension
                let sign: Float = ((charValue + hashIdx) % 2 == 0) ? 1.0 : -1.0
                vector[hash] += sign * positionWeight
            }
            
            // 字符类型特征
            if char.properties.isAlphabetic {
                vector[0] += 0.1
            }
            // 检查是否为数字字符 (0-9)
            if char.value >= 0x30 && char.value <= 0x39 {
                vector[1] += 0.1
            }
            if char.value >= 0x4E00 && char.value <= 0x9FFF {
                // 中文字符
                vector[2] += 0.1
            }
        }
        
        // 文本长度特征
        vector[3] = Float(min(chars.count, 100)) / 100.0
        
        // L2 归一化
        return l2Normalize(vector)
    }
    
    // MARK: - 向量工具
    
    /// L2 归一化
    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_dotpr(vector, 1, vector, 1, &norm, vDSP_Length(vector.count))
        norm = sqrt(norm)
        
        guard norm > 0 else { return vector }
        
        var result = [Float](repeating: 0, count: vector.count)
        var divisor = norm
        vDSP_vsdiv(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
        
        return result
    }
    
    /// 向量转 Data（用于存储）
    func vectorToData(_ vector: [Float]) -> Data {
        return vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    
    /// Data 转向量（用于读取）
    func dataToVector(_ data: Data) -> [Float] {
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
    
    // MARK: - 缓存管理
    
    private func getCachedEmbedding(for text: String) -> [Float]? {
        return cacheQueue.sync {
            embeddingCache[text]
        }
    }
    
    private func cacheEmbedding(_ embedding: [Float], for text: String) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 缓存满时清理一半
            if self.embeddingCache.count >= self.cacheLimit {
                let keysToRemove = Array(self.embeddingCache.keys.prefix(self.cacheLimit / 2))
                for key in keysToRemove {
                    self.embeddingCache.removeValue(forKey: key)
                }
            }
            
            self.embeddingCache[text] = embedding
        }
    }
    
    /// 清空缓存
    func clearCache() {
        cacheQueue.async { [weak self] in
            self?.embeddingCache.removeAll()
        }
    }
    
    // MARK: - 状态信息
    
    var status: String {
        let cacheSize = cacheQueue.sync { embeddingCache.count }
        return """
        🧮 LocalEmbedding Status:
        - Dimension: \(embeddingDimension)
        - Chinese embedding: \(chineseEmbedding != nil ? "available" : "fallback mode")
        - English embedding: \(englishEmbedding != nil ? "available" : "not available")
        - Cache size: \(cacheSize) / \(cacheLimit)
        """
    }
}

// MARK: - 便捷扩展

extension LocalEmbedding {
    
    /// 快速测试嵌入功能
    func runQuickTest() {
        print("\n🧪 LocalEmbedding Quick Test:")
        
        let testCases = [
            ("我妈妈生病了", "她现在怎么样了"),
            ("我喜欢听音乐", "你平时爱好什么"),
            ("今天天气真好", "我妈妈住院了"),
            ("你好", "Hello")
        ]
        
        for (text1, text2) in testCases {
            let sim = similarity(text1: text1, text2: text2)
            print("   '\(text1)' vs '\(text2)' => 相似度: \(String(format: "%.3f", sim))")
        }
    }
}
