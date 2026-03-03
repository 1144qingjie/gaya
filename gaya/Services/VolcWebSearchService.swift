//
//  VolcWebSearchService.swift
//  gaya
//
//  火山引擎融合信息搜索服务
//  参考文档：https://www.volcengine.com/docs/85508/1650263?lang=zh
//

import Foundation
import CryptoKit

/// 火山引擎融合信息搜索服务
class VolcWebSearchService {
    
    // MARK: - Singleton
    static let shared = VolcWebSearchService()
    
    // MARK: - 配置
    // 优先使用 API Key（控制台创建的融合信息搜索 Key）
    private let apiKey = VolcEngineConfig.webSearchApiKey
    private let apiKeyBaseURL = "https://open.feedcoopapi.com/search_api/web_search"

    // 备用：使用火山引擎 OpenAPI（AK/SK 签名）
    // 参考：https://www.volcengine.com/docs/85508/1650263?lang=zh
    private let accessKey = VolcEngineConfig.webSearchAccessKey
    private let secretKey = VolcEngineConfig.webSearchSecretKey
    private let endpoint = VolcEngineConfig.webSearchEndpoint
    private let service = VolcEngineConfig.webSearchService
    private let region = VolcEngineConfig.webSearchRegion
    private let action = VolcEngineConfig.webSearchAction
    private let version = VolcEngineConfig.webSearchVersion
    
    private let timeout: TimeInterval = 10
    
    // 打印 API 调用信息（用于调试）
    private func logAPICall(url: String, headers: [String: String], body: [String: Any]) {
        print("🔍 VolcWebSearch API Call:")
        print("   URL: \(url)")
        print("   Headers: \(headers)")
        print("   Body: \(body)")
    }
    
    // MARK: - 初始化
    private init() {
        print("🔍 VolcWebSearchService initialized")
    }
    
    // MARK: - 公开接口
    
    /// 执行联网搜索（AK/SK 签名）
    /// - Parameters:
    ///   - query: 搜索查询
    ///   - maxResults: 最大返回结果数（默认 5）
    /// - Returns: 搜索结果，如果失败返回 nil
    func search(query: String, maxResults: Int = 5) async -> WebSearchResult? {
        if !apiKey.isEmpty {
            return await searchWithAPIKey(query: query, maxResults: maxResults)
        }
        return await searchWithAKSK(query: query, maxResults: maxResults)
    }

    /// 使用 API Key 方式搜索（推荐）
    private func searchWithAPIKey(query: String, maxResults: Int) async -> WebSearchResult? {
        guard let url = URL(string: apiKeyBaseURL) else {
            print("❌ Invalid VolcWebSearch URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

        let searchType = inferSearchType(for: query)
        let body: [String: Any] = [
            "query": query,
            "top_k": maxResults,
            "search_type": searchType,
            "SearchType": searchType
        ]

        // 打印请求信息（用于调试）
        let headers = ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"]
        logAPICall(url: url.absoluteString, headers: headers, body: body)

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            print("❌ Failed to serialize VolcWebSearch request")
            return nil
        }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                return nil
            }

            // 打印原始响应（用于调试）
            if let responseText = String(data: data, encoding: .utf8) {
                print("🔍 VolcWebSearch API Response:")
                print("   Status Code: \(httpResponse.statusCode)")
                print("   Response Body: \(responseText.prefix(800))")
            }

            guard httpResponse.statusCode == 200 else {
                print("❌ VolcWebSearch API error: \(httpResponse.statusCode)")
                if let errorText = String(data: data, encoding: .utf8) {
                    print("   Error: \(errorText)")
                }
                return nil
            }

            if let parsed = parseSearchResponse(data: data) {
                return parsed.query.isEmpty ? WebSearchResult(query: query, items: parsed.items) : parsed
            }
            return nil

        } catch {
            print("❌ VolcWebSearch API call failed: \(error)")
            return nil
        }
    }
    
    /// 使用 AK/SK 签名方式搜索
    private func searchWithAKSK(query: String, maxResults: Int) async -> WebSearchResult? {
        guard let url = URL(string: endpoint) else {
            print("❌ Invalid VolcWebSearch URL")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        
        // OpenAPI 公共参数（QueryString）
        let queryItems = [
            URLQueryItem(name: "Action", value: action),
            URLQueryItem(name: "Version", value: version)
        ]
        
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            print("❌ Failed to build URL components")
            return nil
        }
        components.queryItems = queryItems
        guard let finalURL = components.url else {
            print("❌ Failed to build signed URL")
            return nil
        }
        request.url = finalURL
        
        // 请求体（必须包含 SearchType，否则会报 SearchType is invalid）
        let body: [String: Any] = [
            "Query": query,
            "SearchType": inferSearchType(for: query),
            "TopK": maxResults
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            print("❌ Failed to serialize VolcWebSearch request")
            return nil
        }
        request.httpBody = httpBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 计算签名并写入请求头
        let signer = VolcOpenAPISigner(
            accessKey: accessKey,
            secretKey: secretKey,
            service: service,
            region: region
        )
        signer.sign(&request, body: httpBody)
        
        // 打印请求信息（用于调试）
        let headers = request.allHTTPHeaderFields ?? [:]
        logAPICall(url: finalURL.absoluteString, headers: headers, body: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                return nil
            }
            
            // 打印原始响应（用于调试）
            if let responseText = String(data: data, encoding: .utf8) {
                print("🔍 VolcWebSearch API Response:")
                print("   Status Code: \(httpResponse.statusCode)")
                print("   Response Body: \(responseText.prefix(800))") // 只打印前800字符
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ VolcWebSearch API error: \(httpResponse.statusCode)")
                if let errorText = String(data: data, encoding: .utf8) {
                    print("   Error: \(errorText)")
                }
                return nil
            }
            
            // 解析响应
            if let parsed = parseSearchResponse(data: data) {
                return parsed.query.isEmpty ? WebSearchResult(query: query, items: parsed.items) : parsed
            }
            return nil
            
        } catch {
            print("❌ VolcWebSearch API call failed: \(error)")
            return nil
        }
    }
    
    /// 判断用户问题是否需要联网搜索
    /// - Parameter query: 用户问题
    /// - Returns: 是否需要搜索
    func shouldSearch(query: String) -> Bool {
        let searchKeywords = [
            "今天", "现在", "最新", "最近", "当前", "实时",
            "天气", "温度", "降雨", "台风",
            "新闻", "热点", "事件", "发生",
            "股价", "股票", "行情", "涨跌",
            "时间", "日期", "几号", "星期",
            "多少", "价格", "汇率", "汇率"
        ]
        
        return searchKeywords.contains { query.contains($0) }
    }
    
    /// 推断搜索类型（需要与服务端枚举一致）
    private func inferSearchType(for query: String) -> String {
        // 融合信息搜索 API Key 接口目前可用的类型以 web 为主
        // 发送 news 会触发 SearchType is invalid
        _ = query
        return "web"
    }
    
    // MARK: - 私有方法
    
    /// 解析搜索响应
    private func parseSearchResponse(data: Data) -> WebSearchResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Failed to parse VolcWebSearch response")
            if let rawText = String(data: data, encoding: .utf8) {
                print("   Raw response: \(rawText)")
            }
            return nil
        }
        
        // 打印 JSON 结构（用于调试）
        print("🔍 VolcWebSearch Response JSON keys: \(json.keys.joined(separator: ", "))")
        
        var results: [WebSearchItem] = []
        
        // 兼容多种响应格式
        if let resultDict = json["Result"] as? [String: Any] {
            if let webResults = resultDict["WebResults"] as? [[String: Any]] {
                print("🔍 Found 'Result.WebResults' array with \(webResults.count) items")
                results.append(contentsOf: parseItems(webResults))
            }
            if let items = resultDict["Items"] as? [[String: Any]] {
                print("🔍 Found 'Result.Items' array with \(items.count) items")
                results.append(contentsOf: parseItems(items))
            } else if let data = resultDict["Data"] as? [[String: Any]] {
                print("🔍 Found 'Result.Data' array with \(data.count) items")
                results.append(contentsOf: parseItems(data))
            } else if let searchResult = resultDict["SearchResult"] as? [[String: Any]] {
                print("🔍 Found 'Result.SearchResult' array with \(searchResult.count) items")
                results.append(contentsOf: parseItems(searchResult))
            }
        } else if let dataArray = json["data"] as? [[String: Any]] {
            print("🔍 Found 'data' array with \(dataArray.count) items")
            results.append(contentsOf: parseItems(dataArray))
        } else if let resultsArray = json["results"] as? [[String: Any]] {
            print("🔍 Found 'results' array with \(resultsArray.count) items")
            results.append(contentsOf: parseItems(resultsArray))
        }
        
        if results.isEmpty {
            print("⚠️ VolcWebSearch returned empty results")
            print("   JSON structure: \(json)")
            // 尝试打印所有可能的字段
            for (key, value) in json {
                print("   Key '\(key)': \(type(of: value))")
            }
            return nil
        }
        
        print("✅ VolcWebSearch found \(results.count) results")
        let queryText = (json["query"] as? String) ?? (json["Query"] as? String) ?? ""
        return WebSearchResult(query: queryText, items: results)
    }
}

// MARK: - OpenAPI 签名

/// 火山引擎 OpenAPI V4 签名（与官方签名规范一致）
private struct VolcOpenAPISigner {
    let accessKey: String
    let secretKey: String
    let service: String
    let region: String
    
    func sign(_ request: inout URLRequest, body: Data) {
        let now = Date()
        let (amzDate, dateStamp) = Self.formatDates(now)
        
        request.setValue(amzDate, forHTTPHeaderField: "X-Date")
        let payloadHash = Self.sha256Hex(body)
        request.setValue(payloadHash, forHTTPHeaderField: "X-Content-Sha256")
        
        guard let url = request.url,
              let host = url.host else { return }
        
        request.setValue(host, forHTTPHeaderField: "Host")
        
        let canonicalRequest = Self.buildCanonicalRequest(
            method: request.httpMethod ?? "POST",
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            payloadHash: payloadHash
        )
        
        let credentialScope = "\(dateStamp)/\(region)/\(service)/request"
        let stringToSign = """
        HMAC-SHA256
        \(amzDate)
        \(credentialScope)
        \(Self.sha256Hex(canonicalRequest.data(using: .utf8) ?? Data()))
        """
        
        let signingKey = Self.getSignatureKey(
            secretKey: secretKey,
            dateStamp: dateStamp,
            region: region,
            service: service
        )
        let signature = Self.hmacHex(stringToSign, key: signingKey)
        
        let signedHeaders = Self.signedHeaders(from: request.allHTTPHeaderFields ?? [:])
        let authorization = "HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }
    
    private static func buildCanonicalRequest(method: String, url: URL, headers: [String: String], payloadHash: String) -> String {
        let canonicalURI = url.path.isEmpty ? "/" : url.path
        let canonicalQueryString = canonicalQuery(from: url)
        let (canonicalHeaders, signedHeaders) = canonicalHeaders(from: headers)
        
        return """
        \(method)
        \(canonicalURI)
        \(canonicalQueryString)
        \(canonicalHeaders)
        \(signedHeaders)
        \(payloadHash)
        """
    }
    
    private static func canonicalQuery(from url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else {
            return ""
        }
        
        let pairs = items.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        }
        .sorted { $0.0 < $1.0 }
        .map { "\(urlEncode($0.0))=\(urlEncode($0.1))" }
        
        return pairs.joined(separator: "&")
    }
    
    private static func canonicalHeaders(from headers: [String: String]) -> (String, String) {
        let filtered = headers
            .map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0.0 == "host" || $0.0 == "x-date" || $0.0 == "x-content-sha256" }
            .sorted { $0.0 < $1.0 }
        
        let canonical = filtered.map { "\($0.0):\($0.1)\n" }.joined()
        let signed = filtered.map { $0.0 }.joined(separator: ";")
        return (canonical, signed)
    }
    
    private static func signedHeaders(from headers: [String: String]) -> String {
        let keys = headers.keys.map { $0.lowercased() }
        let filtered = keys.filter { $0 == "host" || $0 == "x-date" || $0 == "x-content-sha256" }
        return filtered.sorted().joined(separator: ";")
    }
    
    private static func getSignatureKey(secretKey: String, dateStamp: String, region: String, service: String) -> Data {
        let kDate = hmac("HMAC-SHA256", data: dateStamp, key: "VOLC\(secretKey)")
        let kRegion = hmacData("HMAC-SHA256", data: region, key: kDate)
        let kService = hmacData("HMAC-SHA256", data: service, key: kRegion)
        let kSigning = hmacData("HMAC-SHA256", data: "request", key: kService)
        return kSigning
    }
    
    private static func formatDates(_ date: Date) -> (String, String) {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: date)
        
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)
        
        return (amzDate, dateStamp)
    }
    
    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private static func hmacHex(_ string: String, key: Data) -> String {
        let signature = HMAC<SHA256>.authenticationCode(for: Data(string.utf8), using: SymmetricKey(data: key))
        return signature.map { String(format: "%02x", $0) }.joined()
    }
    
    private static func hmac(_ algorithm: String, data: String, key: String) -> Data {
        let keyData = Data(key.utf8)
        return hmacData(algorithm, data: data, key: keyData)
    }
    
    private static func hmacData(_ algorithm: String, data: String, key: Data) -> Data {
        let signature = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: SymmetricKey(data: key))
        return Data(signature)
    }
    
    private static func urlEncode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

// MARK: - 解析工具

private func parseItems(_ items: [[String: Any]]) -> [WebSearchItem] {
    var results: [WebSearchItem] = []
    for item in items {
        let title = (item["title"] as? String) ?? (item["Title"] as? String) ?? ""
        let content = (item["content"] as? String) ?? (item["snippet"] as? String) ?? (item["Summary"] as? String) ?? ""
        let url = (item["url"] as? String) ?? (item["link"] as? String) ?? (item["Url"] as? String)
        let source = (item["source"] as? String) ?? (item["Source"] as? String)
        
        if !title.isEmpty || !content.isEmpty {
            results.append(WebSearchItem(title: title.isEmpty ? "未命名结果" : title, content: content, url: url, source: source))
        }
    }
    return results
}

// MARK: - 数据模型

/// 搜索结果
struct WebSearchResult {
    let query: String
    let items: [WebSearchItem]
    
    /// 格式化为上下文文本（用于注入 system_role）
    func toContextString() -> String {
        var context = "【联网搜索结果】\n"
        context += "用户查询：\(query)\n\n"
        
        for (index, item) in items.enumerated() {
            context += "\(index + 1). \(item.title)\n"
            context += "   内容：\(item.content)\n"
            if let url = item.url {
                context += "   来源：\(url)\n"
            }
            context += "\n"
        }
        
        return context
    }
}

/// 单个搜索结果项
struct WebSearchItem {
    let title: String
    let content: String
    let url: String?
    let source: String?
}
