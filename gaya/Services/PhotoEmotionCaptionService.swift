import Foundation
import UIKit

struct PhotoConversationPayload {
    let description: String
    let injectedUserInput: String
}

/// 基于 Doubao-Seed-1.8 多模态能力生成拍立得情绪短语。
/// 输出约束：10 个字符以内，中文，带轻微情绪价值。
final class PhotoEmotionCaptionService {
    static let shared = PhotoEmotionCaptionService()

    private let maxImageDimension: CGFloat = 960
    private let jpegCompressionQuality: CGFloat = 0.70
    private let captionMaxOutputTokens = 512
    private let conversationMaxOutputTokens = 700

    private init() {}

    func generateCaption(from image: UIImage) async -> String {
        guard let imageDataURL = buildImageDataURL(from: image) else {
            return fallbackCaption()
        }

        let prompt = """
        看图后仅输出一个中文短语，不要解释。
        要求：10字以内，带一点温度和情绪感，不换行。
        """

        let message = ArkInputMessage(
            role: "user",
            content: [
                .inputText(prompt),
                .inputImage(url: imageDataURL)
            ]
        )

        guard let response = await DeepSeekOrchestrator.shared.callDoubaoAPI(
            messages: [message],
            temperature: 0.2,
            maxOutputTokens: captionMaxOutputTokens
        ) else {
            return fallbackCaption()
        }

        let normalized = normalizeCaption(response)
        return normalized.isEmpty ? fallbackCaption() : normalized
    }

    /// 生成可注入语音对话链路的文本。
    /// 该文本会作为“用户输入”送入当前会话，触发 AI 先进行照片解读并语音播报。
    func generateConversationInput(from image: UIImage) async -> String {
        let payload = await generateConversationPayload(from: image)
        return payload.injectedUserInput
    }

    /// 生成图片理解结果：
    /// - description: 仅图片描述文本（用于 UI 气泡展示）
    /// - injectedUserInput: 注入语音对话链路的完整用户输入
    func generateConversationPayload(from image: UIImage) async -> PhotoConversationPayload {
        guard let imageDataURL = buildImageDataURL(from: image) else {
            return fallbackConversationPayload()
        }

        let prompt = """
        请基于图片做视觉理解，只输出2到3句中文完整句子，不要分点。
        要求：
        1) 覆盖画面主体、一个关键细节、整体氛围；
        2) 总长度控制在120字以内；
        3) 不要使用引号，不换行，不要输出任何解释性前缀。
        """

        let message = ArkInputMessage(
            role: "user",
            content: [
                .inputText(prompt),
                .inputImage(url: imageDataURL)
            ]
        )

        guard let response = await DeepSeekOrchestrator.shared.callDoubaoAPI(
            messages: [message],
            temperature: 0.35,
            maxOutputTokens: conversationMaxOutputTokens
        ) else {
            return fallbackConversationPayload()
        }

        let summary = normalizeConversationSummary(response)
        let description = summary.isEmpty ? fallbackConversationSummary() : summary
        return PhotoConversationPayload(
            description: description,
            injectedUserInput: composeConversationInput(with: description)
        )
    }

    private func buildImageDataURL(from image: UIImage) -> String? {
        let resized = downscaledImage(image, maxDimension: maxImageDimension)
        guard let jpegData = resized.jpegData(compressionQuality: jpegCompressionQuality) else {
            return nil
        }
        return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }

    private func downscaledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        let maxSide = max(width, height)

        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let targetSize = CGSize(width: width * scale, height: height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func normalizeCaption(_ raw: String) -> String {
        let firstLine = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map(String.init)
            .first ?? ""

        let cleaned = firstLine
            .replacingOccurrences(of: "短语：", with: "")
            .replacingOccurrences(of: "文案：", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "" }

        // 限制 10 字以内
        let clipped = String(cleaned.prefix(10))
        return clipped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeConversationSummary(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "描述：", with: "")
            .replacingOccurrences(of: "画面：", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let compact = cleaned
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")

        return String(compact.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func composeConversationInput(with summary: String) -> String {
        """
        我刚上传了一张新照片。先给你这张照片的画面信息：\(summary)
        请你先用2到3句口语化中文回应你观察到的内容，然后自然地问我一个问题，让我继续和你聊这张照片。
        """
    }

    private func fallbackCaption() -> String {
        "把光留住"
    }

    private func fallbackConversationSummary() -> String {
        "画面里有一个安静又有情绪的瞬间，细节里带着生活感，整体氛围让人想停下来多看一会儿。"
    }

    private func fallbackConversationPayload() -> PhotoConversationPayload {
        let description = fallbackConversationSummary()
        return PhotoConversationPayload(
            description: description,
            injectedUserInput: composeConversationInput(with: description)
        )
    }
}
