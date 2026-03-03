import SwiftUI
import UIKit
import PhotosUI

/// 统一的圆形液体玻璃按钮按压反馈
struct LiquidGlassCircleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// iOS 26 风格的圆形液体玻璃 icon 容器
struct LiquidGlassCircleIcon: View {
    var systemName: String
    var size: CGFloat = 42
    var iconSize: CGFloat = 16
    var isLoading: Bool = false
    var isActive: Bool = false
    var symbolScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.30 : 0.22),
                            Color.white.opacity(isActive ? 0.10 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.42 : 0.28),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.68
                    )
                )
                .blendMode(.screen)

            Circle()
                .stroke(Color.white.opacity(isActive ? 0.50 : 0.30), lineWidth: 0.9)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.75),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
                .opacity(0.95)

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.9))
            } else {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.white.opacity(0.88))
                    .scaleEffect(symbolScale)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.white.opacity(isActive ? 0.20 : 0.12), radius: 4, x: -1, y: -1)
        .shadow(color: Color.black.opacity(isActive ? 0.34 : 0.24), radius: 10, x: 0, y: 6)
    }
}

/// 语音输入交互组件：
/// - 提示文案
/// - 按住说话按钮
/// 统一布局参数后，可在全项目复用并集中调整。
struct VoiceInputControl: View {
    @Binding var isPressed: Bool
    @Binding var isRecording: Bool
    var hintBottomSpacing: CGFloat = 16
    var buttonBottomPadding: CGFloat = 20
    var measurementSpace: CoordinateSpace = .global
    var onButtonTopChanged: ((CGFloat) -> Void)? = nil
    var onPressStart: () -> Void
    var onPressEnd: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VoiceInputHint(isPressed: isPressed)
                .padding(.bottom, hintBottomSpacing)

            VoiceInputButton(
                isPressed: $isPressed,
                isRecording: $isRecording,
                onPressStart: {
                    onPressStart()
                },
                onPressEnd: {
                    onPressEnd()
                }
            )
            .background(
                GeometryReader { proxy in
                    let top = proxy.frame(in: measurementSpace).minY
                    Color.clear
                        .onAppear {
                            onButtonTopChanged?(top)
                        }
                        .onChange(of: top) { _, newTop in
                            onButtonTopChanged?(newTop)
                        }
                }
            )
            .padding(.bottom, buttonBottomPadding)
        }
    }
}

/// 按住说话按钮
private struct VoiceInputButton: View {
    @Binding var isPressed: Bool
    @Binding var isRecording: Bool
    var onPressStart: () -> Void
    var onPressEnd: () -> Void

    @State private var pulseAnimation = false
    @State private var innerPulse = false

    var body: some View {
        ZStack {
            if isRecording {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    .frame(width: 94, height: 94)
                    .scaleEffect(pulseAnimation ? 1.25 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.5)
                    .animation(
                        .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                        value: pulseAnimation
                    )

                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .frame(width: 86, height: 86)
                    .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                    .opacity(pulseAnimation ? 0.1 : 0.35)
                    .animation(
                        .easeOut(duration: 0.9).repeatForever(autoreverses: false),
                        value: pulseAnimation
                    )
            }

            LiquidGlassCircleIcon(
                systemName: isRecording ? "waveform" : "mic.fill",
                size: 74,
                iconSize: 24,
                isActive: isPressed || isRecording,
                symbolScale: innerPulse && isRecording ? 1.08 : 1.0
            )
                .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onPressStart()

                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    onPressEnd()

                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
        )
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                pulseAnimation = true
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    innerPulse = true
                }
            } else {
                pulseAnimation = false
                innerPulse = false
            }
        }
    }
}

/// 语音输入提示文案
private struct VoiceInputHint: View {
    var isPressed: Bool

    var body: some View {
        Text(isPressed ? "松开发送" : "按住说话")
            .font(.system(size: 12, weight: .light))
            .foregroundColor(.white.opacity(isPressed ? 0.8 : 0.5))
            .animation(.easeInOut(duration: 0.2), value: isPressed)
    }
}

struct ConversationModeSwitch: View {
    @Binding var mode: ConversationMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ConversationMode.allCases) { item in
                Button {
                    guard mode != item else { return }
                    mode = item
                    triggerModeSwitchHaptic()
                } label: {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(mode == item ? 0.95 : 0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(mode == item ? 0.24 : 0))
                                .padding(2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 188)
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.25))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 5)
    }

    private func triggerModeSwitchHaptic() {
        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
    }
}

struct ConversationInputBar: View {
    @Binding var text: String
    @Binding var selectedPhotoItem: PhotosPickerItem?
    var isPhotoLoading: Bool = false
    var isSendDisabled: Bool = false
    var isKeyboardActive: Bool = false
    var measurementSpace: CoordinateSpace = .global
    var onTopChanged: ((CGFloat) -> Void)? = nil
    var onSend: () -> Void
    private let capsuleHeight: CGFloat = 42

    private var capsuleFillColor: Color {
        isKeyboardActive ? Color(white: 0.22, opacity: 1) : Color.white.opacity(0.20)
    }

    private var capsuleStrokeColor: Color {
        isKeyboardActive ? Color.white.opacity(0.24) : Color.white.opacity(0.18)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSendDisabled
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: hasText ? 0 : 8) {
            if !hasText {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    LiquidGlassCircleIcon(
                        systemName: "photo.badge.plus",
                        size: 42,
                        iconSize: 16,
                        isLoading: isPhotoLoading,
                        isActive: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择照片")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            HStack(spacing: 8) {
                MessageInputTextField(
                    text: $text,
                    placeholder: "发消息"
                ) {
                    if canSend {
                        onSend()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 22)

                Button {
                    if canSend {
                        onSend()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(canSend ? .white.opacity(0.92) : .white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.leading, 12)
            .padding(.trailing, 9)
            .frame(maxWidth: .infinity)
            .frame(height: capsuleHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(capsuleFillColor)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(capsuleStrokeColor, lineWidth: 1)
                    )
            )
        }
        .frame(height: capsuleHeight)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.16), value: hasText)
        .background(
            GeometryReader { proxy in
                let top = proxy.frame(in: measurementSpace).minY
                Color.clear
                    .onAppear {
                        onTopChanged?(top)
                    }
                    .onChange(of: top) { _, newTop in
                        onTopChanged?(newTop)
                    }
            }
        )
    }
}

private struct MessageInputTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.returnKeyType = .send
        textField.enablesReturnKeyAutomatically = true
        textField.textColor = UIColor.white.withAlphaComponent(0.92)
        textField.tintColor = UIColor.white
        textField.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.autocorrectionType = .default
        textField.spellCheckingType = .yes
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.45),
                .font: UIFont.systemFont(ofSize: 17, weight: .regular)
            ]
        )
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        context.coordinator.onSubmit = onSubmit
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        @objc
        func textDidChange(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            let normalized = (textField.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return false }
            onSubmit()
            return false
        }
    }
}

struct ConversationBubbleView: View {
    var userText: String
    var aiText: String
    var isResponding: Bool
    var maxBubbleHeight: CGFloat? = nil

    private var normalizedUserText: String {
        userText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedAIText: String {
        aiText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func bubbleContent(maxBubbleWidth: CGFloat) -> some View {
        VStack(spacing: 14) {
            if !normalizedUserText.isEmpty {
                bubbleRow(
                    text: normalizedUserText,
                    textColor: Color(red: 0.76, green: 0.90, blue: 1.0),
                    alignment: .trailing,
                    isUser: true,
                    maxBubbleWidth: maxBubbleWidth
                )
            }

            if !normalizedAIText.isEmpty || isResponding {
                bubbleRow(
                    text: normalizedAIText.isEmpty ? "正在回复..." : normalizedAIText,
                    textColor: .white.opacity(0.95),
                    alignment: .leading,
                    isUser: false,
                    maxBubbleWidth: maxBubbleWidth
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        let constrainedContentHeight = max(0, maxBubbleHeight ?? 0)
        let screenWidth = UIScreen.main.bounds.width
        let pageHorizontalInset: CGFloat = 13
        // 轨道宽度与页面左右边距完全对齐，换行后可扩展到同一右对齐线
        let maxBubbleWidth = max(220, screenWidth - (pageHorizontalInset * 2))

        Group {
            if let maxBubbleHeight, maxBubbleHeight > 0 {
                ScrollView(.vertical, showsIndicators: true) {
                    bubbleContent(maxBubbleWidth: maxBubbleWidth)
                        .padding(.vertical, 2)
                }
                .frame(maxHeight: constrainedContentHeight, alignment: .top)
            } else {
                bubbleContent(maxBubbleWidth: maxBubbleWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxBubbleHeight, alignment: .top)
    }

    @ViewBuilder
    private func bubbleRow(
        text: String,
        textColor: Color,
        alignment: HorizontalAlignment,
        isUser: Bool,
        maxBubbleWidth: CGFloat
    ) -> some View {
        let bubbleBaseOpacity: CGFloat = isUser ? 0.48 : 0.58
        let bubbleTint = isUser
            ? Color(red: 0.18, green: 0.32, blue: 0.46).opacity(0.44)
            : Color(red: 0.08, green: 0.20, blue: 0.24).opacity(0.36)
        let bubbleStroke = isUser
            ? Color(red: 0.67, green: 0.87, blue: 1.0).opacity(0.24)
            : Color.white.opacity(0.16)
        let rowAlignment: Alignment = alignment == .trailing ? .trailing : .leading
        let bubbleWidth = resolvedBubbleWidth(for: text, maxBubbleWidth: maxBubbleWidth)

        let bubble = VStack(alignment: alignment, spacing: 0) {
            Text(text)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(textColor)
                .lineSpacing(5)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: bubbleWidth, alignment: rowAlignment)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(bubbleBaseOpacity))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(bubbleTint)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(bubbleStroke, lineWidth: 1)
        )

        bubble
            .frame(maxWidth: .infinity, alignment: rowAlignment)
    }

    private func resolvedBubbleWidth(for text: String, maxBubbleWidth: CGFloat) -> CGFloat {
        let minBubbleWidth: CGFloat = 74
        guard !text.isEmpty else { return minBubbleWidth }
        let horizontalPadding: CGFloat = 28 // 14 * 2
        let contentMaxWidth = max(0, maxBubbleWidth - horizontalPadding)
        guard contentMaxWidth > 0 else { return minBubbleWidth }
        let font = UIFont.systemFont(ofSize: 17, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 5

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let maxSize = CGSize(width: contentMaxWidth, height: .greatestFiniteMagnitude)

        let wrappedRect = attributedText.boundingRect(
            with: maxSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let singleLineHeight = ceil(font.lineHeight)
        let wrappedHeight = ceil(wrappedRect.height)
        let hasWrappedAtMaxWidth = wrappedHeight > singleLineHeight + 1
        if hasWrappedAtMaxWidth {
            // 只要已换行，就拉到整轨宽度，确保左气泡右边界与右侧对齐线一致
            return maxBubbleWidth
        }

        let oneLineRect = attributedText.boundingRect(
            with: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let oneLineWidth = ceil(oneLineRect.width)
        var candidateWidth = max(minBubbleWidth, horizontalPadding + oneLineWidth + 2)
        candidateWidth = min(candidateWidth, maxBubbleWidth)

        // 二次校验：若在候选宽度仍会换行，则回退为整轨宽度，避免测量误差导致错位
        let candidateContentWidth = max(0, candidateWidth - horizontalPadding)
        let candidateRect = attributedText.boundingRect(
            with: CGSize(width: candidateContentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let hasWrappedAtCandidateWidth = ceil(candidateRect.height) > singleLineHeight + 1
        return hasWrappedAtCandidateWidth ? maxBubbleWidth : candidateWidth
    }
}
