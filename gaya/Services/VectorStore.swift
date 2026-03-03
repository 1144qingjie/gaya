//
//  VectorStore.swift
//  gaya
//
//  SQLite 向量存储服务
//  提供向量的持久化存储和相似度检索功能
//

import Foundation
import SQLite3

/// SQLite 向量存储
/// 用于存储和检索文本的向量表示
class VectorStore {
    
    // MARK: - Singleton
    static let shared = VectorStore()
    
    // MARK: - 数据库
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.gaya.vectorstore.db")
    
    // MARK: - 配置
    private var currentNamespace: String = "guest"
    private let tableName = "memory_vectors"
    
    // MARK: - 嵌入服务
    private let embedding = LocalEmbedding.shared
    
    // MARK: - 初始化
    private init() {
        setupDatabase(for: currentNamespace)
        print("📦 VectorStore initialized")
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - 数据库设置
    
    private func setupDatabase(for namespace: String) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbFileName = dbFileName(for: namespace)
        let dbPath = documentsPath.appendingPathComponent(dbFileName).path
        
        print("📁 Vector database path: \(dbPath)")
        
        db = nil
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            createTables()
            createIndexes()
        } else {
            print("❌ Failed to open vector database")
        }
    }

    private func sanitizedNamespace(_ namespace: String) -> String {
        let trimmed = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        return filtered.isEmpty ? "guest" : filtered
    }

    private func dbFileName(for namespace: String) -> String {
        "gaya_vectors_\(sanitizedNamespace(namespace)).sqlite"
    }

    /// 切换向量库命名空间（按用户隔离）
    func switchNamespace(_ namespace: String) {
        let normalized = sanitizedNamespace(namespace)
        guard normalized != currentNamespace else { return }

        dbQueue.sync {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
            self.currentNamespace = normalized
            setupDatabase(for: normalized)
        }

        print("📦 VectorStore namespace switched to: \(normalized)")
    }
    
    private func createTables() {
        let createSQL = """
        CREATE TABLE IF NOT EXISTS \(tableName) (
            id TEXT PRIMARY KEY,
            memory_id TEXT NOT NULL,
            text TEXT NOT NULL,
            vector BLOB NOT NULL,
            vector_dimension INTEGER NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            access_count INTEGER DEFAULT 0
        );
        """
        
        executeSQL(createSQL)
    }
    
    private func createIndexes() {
        let indexSQL = """
        CREATE INDEX IF NOT EXISTS idx_memory_id ON \(tableName)(memory_id);
        CREATE INDEX IF NOT EXISTS idx_created_at ON \(tableName)(created_at);
        """
        
        executeSQL(indexSQL)
    }
    
    private func executeSQL(_ sql: String) {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            if let error = errorMessage {
                print("❌ SQL Error: \(String(cString: error))")
                sqlite3_free(error)
            }
        }
    }
    
    // MARK: - 存储操作
    
    /// 存储文本及其向量
    /// - Parameters:
    ///   - id: 唯一标识符
    ///   - memoryId: 关联的记忆 ID
    ///   - text: 原始文本
    /// - Returns: 是否存储成功
    @discardableResult
    func store(id: String, memoryId: String, text: String) -> Bool {
        guard let vector = embedding.encode(text) else {
            print("⚠️ Failed to encode text: \(text.prefix(50))...")
            return false
        }
        
        return storeWithVector(id: id, memoryId: memoryId, text: text, vector: vector)
    }
    
    /// 存储文本和预计算的向量
    @discardableResult
    func storeWithVector(id: String, memoryId: String, text: String, vector: [Float]) -> Bool {
        let vectorData = embedding.vectorToData(vector)
        let now = Date().timeIntervalSince1970
        
        let insertSQL = """
        INSERT OR REPLACE INTO \(tableName) 
        (id, memory_id, text, vector, vector_dimension, created_at, updated_at, access_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0);
        """
        
        var success = false
        
        dbQueue.sync {
            var stmt: OpaquePointer?
            
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 2, memoryId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 3, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_blob(stmt, 4, (vectorData as NSData).bytes, Int32(vectorData.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 5, Int32(vector.count))
                sqlite3_bind_double(stmt, 6, now)
                sqlite3_bind_double(stmt, 7, now)
                
                success = sqlite3_step(stmt) == SQLITE_DONE
            }
            
            sqlite3_finalize(stmt)
        }
        
        if success {
            print("📦 Stored vector for: \(text.prefix(30))... (dim: \(vector.count))")
        }
        
        return success
    }
    
    /// 删除向量
    @discardableResult
    func delete(id: String) -> Bool {
        let deleteSQL = "DELETE FROM \(tableName) WHERE id = ?;"
        
        var success = false
        
        dbQueue.sync {
            var stmt: OpaquePointer?
            
            if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                success = sqlite3_step(stmt) == SQLITE_DONE
            }
            
            sqlite3_finalize(stmt)
        }
        
        return success
    }
    
    /// 根据 memoryId 删除所有相关向量
    @discardableResult
    func deleteByMemoryId(_ memoryId: String) -> Bool {
        let deleteSQL = "DELETE FROM \(tableName) WHERE memory_id = ?;"
        
        var success = false
        
        dbQueue.sync {
            var stmt: OpaquePointer?
            
            if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, memoryId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                success = sqlite3_step(stmt) == SQLITE_DONE
            }
            
            sqlite3_finalize(stmt)
        }
        
        return success
    }
    
    // MARK: - 检索操作
    
    /// 语义搜索最相似的记录
    /// - Parameters:
    ///   - query: 查询文本
    ///   - topK: 返回前 K 个结果
    ///   - threshold: 相似度阈值（低于此值的结果将被过滤）
    /// - Returns: 按相似度排序的结果列表
    func search(query: String, topK: Int = 5, threshold: Float = 0.0) -> [VectorSearchResult] {
        guard let queryVector = embedding.encode(query) else {
            print("⚠️ Failed to encode query: \(query)")
            return []
        }
        
        return searchWithVector(queryVector, topK: topK, threshold: threshold)
    }
    
    /// 使用预计算的向量进行搜索
    func searchWithVector(_ queryVector: [Float], topK: Int = 5, threshold: Float = 0.0) -> [VectorSearchResult] {
        var results: [VectorSearchResult] = []
        
        let selectSQL = "SELECT id, memory_id, text, vector FROM \(tableName);"
        
        dbQueue.sync {
            var stmt: OpaquePointer?
            
            if sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let idCStr = sqlite3_column_text(stmt, 0),
                          let memoryIdCStr = sqlite3_column_text(stmt, 1),
                          let textCStr = sqlite3_column_text(stmt, 2),
                          let vectorBlob = sqlite3_column_blob(stmt, 3) else {
                        continue
                    }
                    
                    let id = String(cString: idCStr)
                    let memoryId = String(cString: memoryIdCStr)
                    let text = String(cString: textCStr)
                    
                    let vectorSize = sqlite3_column_bytes(stmt, 3)
                    let vectorData = Data(bytes: vectorBlob, count: Int(vectorSize))
                    let storedVector = embedding.dataToVector(vectorData)
                    
                    // 计算相似度
                    let similarity = embedding.cosineSimilarity(queryVector, storedVector)
                    
                    if similarity >= threshold {
                        results.append(VectorSearchResult(
                            id: id,
                            memoryId: memoryId,
                            text: text,
                            similarity: similarity
                        ))
                    }
                }
            }
            
            sqlite3_finalize(stmt)
        }
        
        // 按相似度降序排序
        results.sort { $0.similarity > $1.similarity }
        
        // 更新访问计数
        let topResults = Array(results.prefix(topK))
        updateAccessCount(for: topResults.map { $0.id })
        
        return topResults
    }
    
    /// 根据 ID 列表搜索
    func searchByIds(_ ids: [String]) -> [VectorSearchResult] {
        guard !ids.isEmpty else { return [] }
        
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let selectSQL = "SELECT id, memory_id, text, vector FROM \(tableName) WHERE id IN (\(placeholders));"
        
        var results: [VectorSearchResult] = []
        
        dbQueue.sync {
            var stmt: OpaquePointer?
            
            if sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK {
                for (index, id) in ids.enumerated() {
                    sqlite3_bind_text(stmt, Int32(index + 1), id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let idCStr = sqlite3_column_text(stmt, 0),
                          let memoryIdCStr = sqlite3_column_text(stmt, 1),
                          let textCStr = sqlite3_column_text(stmt, 2) else {
                        continue
                    }
                    
                    results.append(VectorSearchResult(
                        id: String(cString: idCStr),
                        memoryId: String(cString: memoryIdCStr),
                        text: String(cString: textCStr),
                        similarity: 1.0
                    ))
                }
            }
            
            sqlite3_finalize(stmt)
        }
        
        return results
    }
    
    /// 更新访问计数
    private func updateAccessCount(for ids: [String]) {
        guard !ids.isEmpty else { return }
        
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        let updateSQL = """
        UPDATE \(tableName) 
        SET access_count = access_count + 1, updated_at = ?
        WHERE id IN (\(placeholders));
        """
        
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            
            var stmt: OpaquePointer?
            
            if sqlite3_prepare_v2(self.db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
                
                for (index, id) in ids.enumerated() {
                    sqlite3_bind_text(stmt, Int32(index + 2), id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
                
                sqlite3_step(stmt)
            }
            
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - 统计信息
    
    /// 获取存储的向量数量
    func count() -> Int {
        let countSQL = "SELECT COUNT(*) FROM \(tableName);"
        var count = 0
        
        dbQueue.sync {
            var stmt: OpaquePointer?
            
            if sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
            }
            
            sqlite3_finalize(stmt)
        }
        
        return count
    }
    
    /// 获取数据库文件大小
    func databaseSize() -> Int {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = documentsPath.appendingPathComponent(dbFileName(for: currentNamespace)).path
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: dbPath)
        if let size = attributes?[.size] as? NSNumber {
            return size.intValue
        }
        if let size = attributes?[.size] as? Int {
            return size
        }
        if let size = attributes?[.size] as? UInt64 {
            return Int(size)
        }
        return 0
    }
    
    /// 清空所有向量
    func clearAll() {
        let deleteSQL = "DELETE FROM \(tableName);"
        executeSQL(deleteSQL)
        
        // 压缩数据库
        executeSQL("VACUUM;")
        
        print("🗑️ Vector store cleared")
    }
    
    /// 状态信息
    var status: String {
        return """
        📦 VectorStore Status:
        - Total vectors: \(count())
        - Database size: \(databaseSize() / 1024) KB
        - Embedding dimension: \(embedding.embeddingDimension)
        """
    }
}

// MARK: - 搜索结果

/// 向量搜索结果
struct VectorSearchResult {
    let id: String
    let memoryId: String
    let text: String
    let similarity: Float
    
    var description: String {
        return "[\(String(format: "%.3f", similarity))] \(text.prefix(50))..."
    }
}

// MARK: - 便捷扩展

extension VectorStore {
    
    /// 批量存储
    func storeBatch(_ items: [(id: String, memoryId: String, text: String)]) -> Int {
        var successCount = 0
        
        for item in items {
            if store(id: item.id, memoryId: item.memoryId, text: item.text) {
                successCount += 1
            }
        }
        
        return successCount
    }
    
    /// 快速测试
    func runQuickTest() {
        print("\n🧪 VectorStore Quick Test:")
        
        // 清空测试数据
        clearAll()
        
        // 存储测试数据
        let testData = [
            ("test1", "mem1", "我妈妈生病住院了"),
            ("test2", "mem2", "今天天气真好"),
            ("test3", "mem3", "我喜欢听爵士音乐"),
            ("test4", "mem4", "母亲的身体不太好"),
            ("test5", "mem5", "你好，很高兴认识你")
        ]
        
        for (id, memId, text) in testData {
            store(id: id, memoryId: memId, text: text)
        }
        
        print("   - Stored \(count()) vectors")
        
        // 搜索测试
        let queries = ["她现在怎么样了", "音乐爱好", "天气"]
        
        for query in queries {
            print("\n   Query: '\(query)'")
            let results = search(query: query, topK: 3)
            for result in results {
                print("   - \(result.description)")
            }
        }
        
        // 清理
        clearAll()
        print("\n   - Test completed, data cleared")
    }
}
