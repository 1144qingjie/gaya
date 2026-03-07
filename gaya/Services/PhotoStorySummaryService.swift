import Foundation

/// 照片会话中的单轮对话数据
struct PhotoStoryDialogueTurn {
    let userText: String
    let aiText: String
}

/// 基于 Doubao-Seed-1.8 的拍立得背面故事总结服务
final class PhotoStorySummaryService {
    static let shared = PhotoStorySummaryService()

    private let maxSummaryCharacters = 50
    private let maxTurnsForPrompt = 8
    private let perSideTextLimit = 120

    private init() {}

    func summarize(
        turns: [PhotoStoryDialogueTurn],
        previousSummary: String
    ) async -> String {
        guard !turns.isEmpty else { return "" }

        let clippedTurns = Array(turns.suffix(maxTurnsForPrompt))
        let dialogueText = buildDialogueText(from: clippedTurns)
        let previous = previousSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        let prompt = """
        你是“拍立得照片背后故事”总结助手。请根据照片相关对话，输出这张照片当前最核心的信息。

        规则：
        1) 只输出一句中文总结，不要解释；
        2) 严格不超过\(maxSummaryCharacters)个字符；
        3) 必须使用用户第一人称视角（我/当时/记得），像用户在回忆；
        4) 风格参考：去年圣诞节下班回家路上，我拍下店门口圣诞树，奶油香让我误以为树也有味道；
        5) 重点捕捉用户情绪和记忆线索，而不是客观识别；
        6) 如果信息还少，给出温和且具体的阶段性总结；
        7) 不要换行，不要加引号。

        之前版本（可参考并迭代）：
        \(previous.isEmpty ? "无" : previous)

        最新对话：
        \(dialogueText)
        """

        let message = ArkInputMessage(
            role: "user",
            content: [.inputText(prompt)]
        )

        guard let response = await DeepSeekOrchestrator.shared.callDoubaoAPI(
            messages: [message],
            temperature: 0.2,
            maxOutputTokens: 220,
            feature: .photoStorySummary
        ) else {
            if await shouldKeepPreviousSummaryOnMembershipFailure() {
                return previous
            }
            return fallbackSummary(from: clippedTurns)
        }

        return normalizeSummary(response, fallback: fallbackSummary(from: clippedTurns))
    }

    private func buildDialogueText(from turns: [PhotoStoryDialogueTurn]) -> String {
        turns.enumerated().map { index, turn in
            let user = sanitizeDialogueText(turn.userText, limit: perSideTextLimit)
            let ai = sanitizeDialogueText(turn.aiText, limit: perSideTextLimit)
            return "第\(index + 1)轮 用户：\(user) AI：\(ai)"
        }
        .joined(separator: "\n")
    }

    private func sanitizeDialogueText(_ text: String, limit: Int) -> String {
        let compact = text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else { return "（空）" }
        return String(compact.prefix(limit))
    }

    private func normalizeSummary(_ raw: String, fallback: String) -> String {
        let firstLine = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map(String.init)
            .first ?? ""

        let cleaned = firstLine
            .replacingOccurrences(of: "总结：", with: "")
            .replacingOccurrences(of: "摘要：", with: "")
            .replacingOccurrences(of: "核心信息：", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let compact = cleaned
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let clipped = String(compact.prefix(maxSummaryCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return clipped.isEmpty ? fallback : clipped
    }

    private func fallbackSummary(from turns: [PhotoStoryDialogueTurn]) -> String {
        let latest = turns.last
        let seedText = latest?.userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (latest?.userText ?? "")
            : (latest?.aiText ?? "")

        let normalized = seedText
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            return "这张照片记录了一个正在被慢慢说清的瞬间"
        }

        return String(normalized.prefix(maxSummaryCharacters))
    }

    private func shouldKeepPreviousSummaryOnMembershipFailure() async -> Bool {
        await MainActor.run {
            MembershipStore.shared.blockingMessage != nil
        }
    }
}
