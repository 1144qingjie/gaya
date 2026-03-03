import SwiftUI
import PhotosUI
import UIKit
import Combine
import Security
#if canImport(ATAuthSDK)
import ATAuthSDK
#endif

enum SeedState {
    case idle
    case active
}

enum ConversationMode: String, CaseIterable, Identifiable {
    case text
    case voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text:
            return "文本"
        case .voice:
            return "语音"
        }
    }
}

private struct TextConversationContextTurn {
    let userText: String
    let aiText: String
}

private final class TextConversationService {
    static let shared = TextConversationService()
    private let fallbackReply = "我刚刚有点走神了，你可以再说一次吗？"
    private let primaryMaxOutputTokens = 900
    private let retryMaxOutputTokens = 1400

    private init() {}

    func generateReply(
        userText: String,
        history: [TextConversationContextTurn],
        fallbackOverride: String? = nil
    ) async -> String {
        let prompt = buildPrompt(userText: userText, history: history)
        if let primary = await requestReply(prompt: prompt, maxOutputTokens: primaryMaxOutputTokens) {
            return primary
        }

        let retryPrompt = buildPrompt(
            userText: userText,
            history: Array(history.suffix(3))
        )
        if let retry = await requestReply(prompt: retryPrompt, maxOutputTokens: retryMaxOutputTokens) {
            return retry
        }

        if let fallbackOverride {
            let normalizedFallback = normalize(fallbackOverride)
            if !normalizedFallback.isEmpty {
                return normalizedFallback
            }
        }

        return fallbackReply
    }

    func makePhotoInjectionFallbackReply(from description: String) -> String {
        let compactDescription = compact(description)
        if compactDescription.isEmpty {
            return "这张照片的氛围很有故事感，我一下就被画面里的细节吸引住了。你拍下这一刻时，最想留住什么？"
        }

        let clippedDescription = String(compactDescription.prefix(90)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "我先接住这张照片的感觉：\(clippedDescription) 画面里的情绪很完整，也很耐看。你按下快门的那一秒，在想什么？"
    }

    private func requestReply(prompt: String, maxOutputTokens: Int) async -> String? {
        guard let response = await DeepSeekOrchestrator.shared.callDoubaoTextAPI(
            prompt: prompt,
            temperature: 0.3,
            maxOutputTokens: maxOutputTokens
        ) else {
            return nil
        }

        let normalized = normalize(response)
        return normalized.isEmpty ? nil : normalized
    }

    private func buildPrompt(
        userText: String,
        history: [TextConversationContextTurn]
    ) -> String {
        let characterDefinition = GayaCharacterPrompt.coreDefinition()
        let historyText: String
        if history.isEmpty {
            historyText = "无"
        } else {
            historyText = history.suffix(8).enumerated().map { index, turn in
                let user = compact(turn.userText)
                let ai = compact(turn.aiText)
                return "第\(index + 1)轮\n用户：\(user)\nAI：\(ai)"
            }
            .joined(separator: "\n\n")
        }

        return """
        \(characterDefinition)

        请延续上下文进行回复，优先回答用户问题，再自然推进对话。

        【最近对话】
        \(historyText)

        【用户最新输入】
        \(compact(userText))

        【输出要求】
        - 只输出 AI 回复正文，不要加“AI:”前缀；
        - 用自然口语化中文；
        - 避免冗长和重复；
        - 如信息不足，先澄清再给建议。
        """
    }

    private func compact(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ raw: String) -> String {
        compact(raw)
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var voiceService = VoiceService()
    @StateObject private var authService = AuthService.shared
    @State private var seedState: SeedState = .idle
    @State private var errorMessage: String?
    @State private var wakePulse = false
    @AppStorage("selected_polaroid_paper_style") private var selectedPolaroidPaperStyleID: String = PolaroidPaperStyle.defaultStyle.rawValue
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoImage: UIImage?
    @State private var photoVersion: Int = 0
    @State private var isPhotoProcessing = false
    @StateObject private var photoSettings = PhotoParticleSettings()
    @State private var isPhotoModalPresented = false
    @State private var polaroidCaption: String = ""
    @State private var polaroidStoryText: String = ""
    @State private var isCaptionGenerating = false
    @State private var captionRequestID = UUID()
    @State private var photoConversationRequestID = UUID()
    @State private var isPhotoStoryTrackingActive = false
    @State private var photoStoryTurns: [PhotoStoryDialogueTurn] = []
    @State private var photoStoryUpdateTask: Task<Void, Never>?
    @State private var photoStorySessionID = UUID()
    @State private var isMoreDrawerPresented = false
    @State private var isMemoryCorridorPresented = false
    @State private var isPaperSelectionPresented = false
    @State private var conversationMode: ConversationMode = .text
    @State private var inputText: String = ""
    @State private var currentRoundUserText: String = ""
    @State private var currentRoundAIText: String = ""
    @State private var isResponding = false
    @State private var activeResponseMode: ConversationMode?
    @State private var textResponseTask: Task<Void, Never>?
    @State private var contextTurns: [TextConversationContextTurn] = []
    @State private var textPseudoAudioLevel: Float = 0.0
    @State private var keyboardBottomInset: CGFloat = 0
    @State private var inputBarTopY: CGFloat = .infinity
    @State private var photoModalInputBarTopY: CGFloat = .infinity
    @State private var conversationModeBottomY: CGFloat = .infinity
    @State private var conversationBubbleHeight: CGFloat = 0
    @State private var conversationBubbleIntrinsicHeight: CGFloat = 0
    @State private var isPhotoUnderstandingPending = false
    @State private var isAuthLoginPresented = false
    @State private var pendingPostLoginAction: PostLoginAction?
    @State private var showMembershipComingSoon = false

    private let particlePageCoordinateSpace = "particlePage"
    private let moreDrawerHeaderLeadingInset: CGFloat = 18
    private let moreDrawerHeaderTrailingInset: CGFloat = 20
    private let moreDrawerSubtitleFontSize: CGFloat = 15
    private let moreDrawerItems: [MoreDrawerItem] = [
        .init(icon: "crown", title: "会员计划", action: .membership),
        .init(icon: "brain.head.profile", title: "记忆回廊", action: .memoryCorridor),
        .init(icon: "safari", title: "AI 洞察", action: .insight),
        .init(icon: "photo.on.rectangle.angled", title: "相纸选择", action: .paperSelection),
        .init(icon: "message", title: "联系我们", action: .contact),
        .init(icon: "lock.shield", title: "隐私政策", action: .privacyPolicy),
        .init(icon: "doc.text", title: "用户协议", action: .userAgreement)
    ]

    private var selectedPolaroidPaperStyle: PolaroidPaperStyle {
        PolaroidPaperStyle(rawValue: selectedPolaroidPaperStyleID) ?? .defaultStyle
    }

    private var moreDrawerTitle: String {
        let nickname = authService.userNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if nickname.isEmpty {
            return "你好!"
        }
        return "你好! \(nickname)"
    }

    private var moreDrawerSubtitle: String {
        if authService.isLoggedIn {
            return "欢迎回来，继续和 Gaya 聊聊"
        }
        return "游客模式可体验，会员功能需登录"
    }

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = moreDrawerWidth(screenWidth: proxy.size.width)

            ZStack(alignment: .topLeading) {
                if !isPhotoModalPresented && !isMemoryCorridorPresented && !isPaperSelectionPresented {
                    MoreDrawerPanel(
                        title: moreDrawerTitle,
                        subtitle: moreDrawerSubtitle,
                        items: moreDrawerItems,
                        headerLeadingInset: moreDrawerHeaderLeadingInset,
                        headerTrailingInset: moreDrawerHeaderTrailingInset,
                        onItemTap: handleMoreDrawerItemTap
                    )
                    .frame(width: drawerWidth, height: proxy.size.height, alignment: .topLeading)
                    .ignoresSafeArea()
                    .offset(x: isMoreDrawerPresented ? 0 : -drawerWidth)
                    .animation(.easeInOut(duration: 0.22), value: isMoreDrawerPresented)
                    .zIndex(1)
                }

                canvasContent
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .offset(
                        x: isMoreDrawerPresented && !isPhotoModalPresented && !isMemoryCorridorPresented && !isPaperSelectionPresented
                            ? drawerWidth
                            : 0
                    )
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isMoreDrawerPresented)
                    .shadow(color: Color.black.opacity(isMoreDrawerPresented ? 0.34 : 0), radius: 16, x: -6, y: 0)
                    .zIndex(2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(
                Color.black
                    .ignoresSafeArea()
            )
        }
        .onChange(of: isPhotoModalPresented) { _, isPresented in
            if isPresented {
                isMoreDrawerPresented = false
                isMemoryCorridorPresented = false
                isPaperSelectionPresented = false
            } else {
                stopPhotoStorySession()
                photoModalInputBarTopY = .infinity
                isPhotoUnderstandingPending = false
            }
        }
        .onChange(of: seedState) { _, newState in
            if newState != .active {
                isMoreDrawerPresented = false
                isMemoryCorridorPresented = false
                isPaperSelectionPresented = false
            }
        }
        .onReceive(voiceService.$streamingResponseText) { text in
            guard activeResponseMode == .voice else { return }
            currentRoundAIText = text
        }
        .onReceive(voiceService.$latestConversationTurn.compactMap { $0 }) { turn in
            handleIncomingVoiceTurn(turn)
        }
        .onReceive(voiceService.$connectionError.compactMap { $0 }) { message in
            errorMessage = message
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardVisibility(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardBottomInset = 0
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            isPhotoProcessing = true
            isPhotoUnderstandingPending = true
            currentRoundUserText = ""
            currentRoundAIText = ""
            isResponding = false
            activeResponseMode = nil
            textPseudoAudioLevel = 0

            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    let requestID = UUID()
                    await MainActor.run {
                        captionRequestID = requestID
                        photoConversationRequestID = requestID
                        polaroidCaption = ""
                        polaroidStoryText = ""
                        isCaptionGenerating = true
                        selectedPhotoImage = image
                        photoVersion += 1
                        isPhotoProcessing = false
                        isPhotoUnderstandingPending = true
                        startPhotoStorySession()
                        var openTransaction = Transaction()
                        openTransaction.disablesAnimations = true
                        withTransaction(openTransaction) {
                            isPhotoModalPresented = true
                        }
                    }

                    async let generatedCaptionTask = PhotoEmotionCaptionService.shared.generateCaption(from: image)
                    async let conversationPayloadTask = PhotoEmotionCaptionService.shared.generateConversationPayload(from: image)

                    let conversationPayload = await conversationPayloadTask

                    await MainActor.run {
                        guard photoConversationRequestID == requestID else { return }
                        isPhotoUnderstandingPending = false
                    }

                    await handlePhotoConversationInjection(
                        conversationPayload.injectedUserInput,
                        photoDescription: conversationPayload.description,
                        for: requestID
                    )

                    let generatedCaption = await generatedCaptionTask

                    await MainActor.run {
                        guard captionRequestID == requestID else { return }
                        polaroidCaption = generatedCaption
                        isCaptionGenerating = false
                    }
                } else {
                    await MainActor.run {
                        isPhotoProcessing = false
                        isCaptionGenerating = false
                        isPhotoUnderstandingPending = false
                    }
                }
            }
        }
        .onDisappear {
            textResponseTask?.cancel()
            textResponseTask = nil
        }
        .fullScreenCover(isPresented: $isAuthLoginPresented, onDismiss: {
            // Auth 登录页会触发键盘安全区变化，关闭后主动归零，避免主页面几何被残留键盘状态污染。
            keyboardBottomInset = 0
            dismissKeyboard()
        }) {
            AuthLoginFlowView(authService: authService) {
                isAuthLoginPresented = false
                handlePostLoginActionIfNeeded()
            }
        }
        .alert("会员功能", isPresented: $showMembershipComingSoon) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("会员支付链路将在登录接入后继续完善。")
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var canvasContent: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ParticleView(
                audioLevel: 0,
                seedState: seedState,
                isAISpeaking: effectiveAISpeaking,
                aiAudioLevel: effectiveAIAudioLevel,
                photoImage: nil,
                photoVersion: photoVersion,
                photoSettings: photoSettings,
                photoInteraction: .inactive,
                photoZoom: 1.0,
                photoActive: false
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if keyboardBottomInset > 0 {
                        dismissKeyboard()
                    }
                }

            if isPhotoModalPresented, let previewImage = selectedPhotoImage {
                PolaroidPhotoPageView(
                    image: previewImage,
                    captionText: isCaptionGenerating ? "" : polaroidCaption,
                    storyText: polaroidStoryText,
                    paperStyle: selectedPolaroidPaperStyle,
                    inputText: $inputText,
                    selectedPhotoItem: $selectedPhotoItem,
                    isPhotoProcessing: isPhotoProcessing,
                    isResponding: isResponding,
                    onSend: {
                        sendCurrentInput()
                    },
                    onInputBarTopChanged: { top in
                        photoModalInputBarTopY = top
                    },
                    onClose: {
                        var closeTransaction = Transaction()
                        closeTransaction.disablesAnimations = true
                        withTransaction(closeTransaction) {
                            isPhotoModalPresented = false
                        }
                        captionRequestID = UUID()
                        photoConversationRequestID = UUID()
                        polaroidCaption = ""
                        polaroidStoryText = ""
                        isCaptionGenerating = false
                        isPhotoUnderstandingPending = false
                        isResponding = false
                        activeResponseMode = nil
                        textPseudoAudioLevel = 0
                        stopPhotoStorySession()
                        voiceService.clearPendingInjectedQueries(cancelInFlight: true)
                        selectedPhotoImage = nil
                        selectedPhotoItem = nil
                    }
                )
                .id(photoVersion)
                .zIndex(20)
            }

            if shouldShowConversationBubble && !isMemoryCorridorPresented && !isPaperSelectionPresented {
                conversationBubbleOverlay
                    .zIndex(isPhotoModalPresented ? 25 : 12)
            }

            if !isPhotoModalPresented && !isMemoryCorridorPresented && !isPaperSelectionPresented {
                if seedState == .idle && errorMessage == nil && !isMoreDrawerPresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleStart()
                        }
                }

                if seedState == .idle && errorMessage == nil {
                    VStack {
                        Spacer()

                        Text("它正在等待你的触摸，让它醒来")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.white.opacity(wakePulse ? 0.8 : 0.4))
                            .kerning(1)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 120)
                    }
                    .allowsHitTesting(false)
                    .onAppear {
                        wakePulse = false
                        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                            wakePulse = true
                        }
                    }
                }

                if seedState == .active {
                    conversationModeOverlay
                        .zIndex(27)

                    bottomInputOverlay
                        .zIndex(29)
                }

                if isMoreDrawerPresented {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeMoreDrawer()
                        }
                        .zIndex(28)
                }

                if seedState == .active {
                    menuButtonOverlay
                        .zIndex(30)
                }
            }

            if isMemoryCorridorPresented {
                MemoryCorridorView {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isMemoryCorridorPresented = false
                    }
                }
                .zIndex(35)
                .transition(.move(edge: .trailing))
            }

            if isPaperSelectionPresented {
                PolaroidPaperSelectionView(
                    currentStyle: selectedPolaroidPaperStyle,
                    onConfirm: { selectedStyle in
                        selectedPolaroidPaperStyleID = selectedStyle.rawValue
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPaperSelectionPresented = false
                        }
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPaperSelectionPresented = false
                        }
                    }
                )
                .zIndex(35)
                .transition(.move(edge: .trailing))
            }

            if let errorMessage = errorMessage {
                VStack(spacing: 16) {
                    Text("Error")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red.opacity(0.4))
                        .kerning(2)
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button {
                        handleStart()
                    } label: {
                        Text("重试")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
                .background(Color(red: 0.18, green: 0.02, blue: 0.05).opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(6)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(name: particlePageCoordinateSpace)
    }

    private var effectiveAISpeaking: Bool {
        voiceService.isSpeaking || (activeResponseMode == .text && isResponding && !currentRoundAIText.isEmpty)
    }

    private var effectiveAIAudioLevel: Float {
        voiceService.isSpeaking ? voiceService.aiAudioLevel : textPseudoAudioLevel
    }

    private var shouldShowConversationBubble: Bool {
        guard !isPhotoUnderstandingPending else { return false }
        let user = currentRoundUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ai = currentRoundAIText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !user.isEmpty || !ai.isEmpty
    }

    private var conversationBubbleLift: CGFloat {
        guard keyboardBottomInset > 0 else { return 0 }
        let activeInputBarTopY = isPhotoModalPresented ? photoModalInputBarTopY : inputBarTopY
        guard activeInputBarTopY.isFinite, conversationBubbleHeight > 0 else {
            return min(keyboardBottomInset * 0.42, 220)
        }

        let screenHeight = UIScreen.main.bounds.height
        let centeredBubbleBottomY = (screenHeight * 0.5) + (conversationBubbleHeight * 0.5)
        let targetBubbleBottomY = activeInputBarTopY - 20
        return max(0, centeredBubbleBottomY - targetBubbleBottomY)
    }

    private var conversationBubbleOverlay: some View {
        GeometryReader { proxy in
            let activeInputBarTop = isPhotoModalPresented ? photoModalInputBarTopY : inputBarTopY
            let fallbackModeBottom = proxy.safeAreaInsets.top + 58
            let modeBottom = conversationModeBottomY.isFinite ? conversationModeBottomY : fallbackModeBottom
            let fallbackInputTop = proxy.size.height - proxy.safeAreaInsets.bottom - 84
            let inputTop = activeInputBarTop.isFinite ? activeInputBarTop : fallbackInputTop
            let keyboardBottomSpacing: CGFloat = 30
            let keyboardTopSpacingWhenOverflow: CGFloat = 10
            let areaMinusBottomSpacing = max(0, inputTop - modeBottom - keyboardBottomSpacing)
            let latestBubbleHeight = max(conversationBubbleIntrinsicHeight, conversationBubbleHeight)
            let hasValidBubbleMeasure = latestBubbleHeight > 0
            let shouldClampToTop = !hasValidBubbleMeasure || latestBubbleHeight > areaMinusBottomSpacing
            let bubbleBottomY = inputTop - keyboardBottomSpacing
            let bubbleTopY = shouldClampToTop
                ? (modeBottom + keyboardTopSpacingWhenOverflow)
                : max(modeBottom, bubbleBottomY - latestBubbleHeight)
            let maxBubbleHeight = shouldClampToTop ? max(0, bubbleBottomY - bubbleTopY) : nil

            ZStack(alignment: .top) {
                if keyboardBottomInset > 0 {
                    ConversationBubbleView(
                        userText: currentRoundUserText,
                        aiText: currentRoundAIText,
                        isResponding: isResponding,
                        maxBubbleHeight: maxBubbleHeight
                    )
                    .padding(.horizontal, 13)
                    .padding(.top, max(0, bubbleTopY))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(
                        GeometryReader { innerProxy in
                            let height = innerProxy.size.height
                            Color.clear
                                .onAppear {
                                    conversationBubbleHeight = height
                                }
                                .onChange(of: height) { _, newHeight in
                                    conversationBubbleHeight = newHeight
                                }
                        }
                    )
                } else {
                    VStack {
                        Spacer()
                        ConversationBubbleView(
                            userText: currentRoundUserText,
                            aiText: currentRoundAIText,
                            isResponding: isResponding
                        )
                        .padding(.horizontal, 13)
                        .background(
                            GeometryReader { innerProxy in
                                let height = innerProxy.size.height
                                Color.clear
                                    .onAppear {
                                        conversationBubbleHeight = height
                                    }
                                    .onChange(of: height) { _, newHeight in
                                        conversationBubbleHeight = newHeight
                                    }
                            }
                        )
                        Spacer()
                    }
                    .offset(y: -conversationBubbleLift)
                    .animation(.easeOut(duration: 0.2), value: conversationBubbleLift)
                }

                ConversationBubbleView(
                    userText: currentRoundUserText,
                    aiText: currentRoundAIText,
                    isResponding: isResponding
                )
                .padding(.horizontal, 13)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { measureProxy in
                        let height = measureProxy.size.height
                        Color.clear
                            .onAppear {
                                conversationBubbleIntrinsicHeight = height
                            }
                            .onChange(of: height) { _, newHeight in
                                conversationBubbleIntrinsicHeight = newHeight
                            }
                    }
                )
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(keyboardBottomInset > 0)
    }

    private var conversationModeOverlay: some View {
        VStack {
            HStack {
                Spacer()
                ConversationModeSwitch(mode: $conversationMode)
                    .background(
                        GeometryReader { proxy in
                            let bottom = proxy.frame(in: .named(particlePageCoordinateSpace)).maxY
                            Color.clear
                                .onAppear {
                                    conversationModeBottomY = bottom
                                }
                                .onChange(of: bottom) { _, newBottom in
                                    conversationModeBottomY = newBottom
                                }
                        }
                    )
                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal, 70)

            Spacer()
        }
    }

    private var bottomInputOverlay: some View {
        VStack {
            Spacer()
            ConversationInputBar(
                text: $inputText,
                selectedPhotoItem: $selectedPhotoItem,
                isPhotoLoading: isPhotoProcessing,
                isSendDisabled: isResponding,
                isKeyboardActive: keyboardBottomInset > 0,
                measurementSpace: .named(particlePageCoordinateSpace),
                onTopChanged: { top in
                    inputBarTopY = top
                },
                onSend: {
                    sendCurrentInput()
                }
            )
            .padding(.horizontal, 18)
            .padding(.bottom, keyboardBottomInset > 0 ? (keyboardBottomInset + 5) : 10)
        }
    }

    private var menuButtonOverlay: some View {
        VStack {
            HStack {
                Button {
                    toggleMoreDrawer()
                } label: {
                    LiquidGlassMenuCircleIcon(
                        size: 42,
                        isActive: isMoreDrawerPresented
                    )
                }
                .buttonStyle(LiquidGlassCircleButtonStyle(pressedScale: 0.95))
                .accessibilityLabel("更多")

                Spacer()
            }
            .padding(.leading, 20)
            .padding(.top, 16)

            Spacer()
        }
    }

    // MARK: - Actions

    private func toggleMoreDrawer() {
        guard !isMemoryCorridorPresented else { return }
        guard !isPaperSelectionPresented else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            isMoreDrawerPresented.toggle()
        }
    }

    private func closeMoreDrawer() {
        guard isMoreDrawerPresented else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            isMoreDrawerPresented = false
        }
    }

    private func handleMoreDrawerItemTap(_ item: MoreDrawerItem) {
        switch item.action {
        case .membership:
            closeMoreDrawer()
            guard authService.isLoggedIn else {
                pendingPostLoginAction = .membership
                isAuthLoginPresented = true
                return
            }
            showMembershipComingSoon = true
        case .memoryCorridor:
            closeMoreDrawer()
            withAnimation(.easeInOut(duration: 0.2)) {
                isMemoryCorridorPresented = true
            }
        case .paperSelection:
            closeMoreDrawer()
            withAnimation(.easeInOut(duration: 0.2)) {
                isPaperSelectionPresented = true
            }
        default:
            closeMoreDrawer()
        }
    }

    private func handlePostLoginActionIfNeeded() {
        guard let action = pendingPostLoginAction else { return }
        pendingPostLoginAction = nil

        switch action {
        case .membership:
            showMembershipComingSoon = true
        }
    }

    private func moreDrawerWidth(screenWidth: CGFloat) -> CGFloat {
        let subtitleFont = UIFont.systemFont(ofSize: moreDrawerSubtitleFontSize, weight: .semibold)
        let subtitleWidth = ceil((moreDrawerSubtitle as NSString).size(withAttributes: [.font: subtitleFont]).width)
        let targetWidth = subtitleWidth + moreDrawerHeaderLeadingInset + moreDrawerHeaderTrailingInset
        let maxWidth = min(screenWidth * 0.9, 322)
        return min(targetWidth, maxWidth)
    }

    private func handleStart() {
        activateSeedIfNeeded()
    }

    private func activateSeedIfNeeded() {
        errorMessage = nil
        if seedState != .active {
            withAnimation(.easeInOut(duration: 0.24)) {
                seedState = .active
            }
        }
    }

    private func sendCurrentInput() {
        let userText = normalizeDialogueText(inputText)
        guard !userText.isEmpty else { return }
        guard !isResponding else { return }

        dismissKeyboard()
        activateSeedIfNeeded()
        inputText = ""
        currentRoundUserText = userText
        currentRoundAIText = ""
        isResponding = true
        activeResponseMode = conversationMode
        textPseudoAudioLevel = 0
        errorMessage = nil

        switch conversationMode {
        case .text:
            sendTextModeMessage(userText)
        case .voice:
            sendVoiceModeMessage(userText)
        }
    }

    private func sendTextModeMessage(_ userText: String) {
        textResponseTask?.cancel()
        textResponseTask = Task {
            let response = await TextConversationService.shared.generateReply(
                userText: userText,
                history: contextTurns
            )
            let normalized = normalizeDialogueText(response)
            await streamTextResponse(normalized)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                currentRoundAIText = normalized
                finalizeTextConversationTurn(userText: userText, aiText: normalized)
            }
        }
    }

    private func sendVoiceModeMessage(_ userText: String) {
        textResponseTask?.cancel()
        textResponseTask = nil
        if voiceService.connectionError != nil {
            voiceService.resetConnection()
        }
        voiceService.submitUserTextQuery(userText)
    }

    private func handleIncomingVoiceTurn(_ turn: VoiceConversationTurn) {
        let userText = normalizeDialogueText(turn.userText)
        let aiText = normalizeDialogueText(turn.aiText)
        guard !userText.isEmpty || !aiText.isEmpty else { return }

        if turn.isInjectedQuery {
            appendContextTurn(
                userText: compactInjectedQueryForContext(userText),
                aiText: aiText
            )
            currentRoundUserText = ""
            currentRoundAIText = aiText
            isResponding = false
            activeResponseMode = nil
            textPseudoAudioLevel = 0
            return
        }

        handlePhotoConversationTurn(turn)

        currentRoundUserText = userText
        currentRoundAIText = aiText
        appendContextTurn(userText: userText, aiText: aiText)
        isResponding = false
        activeResponseMode = nil
        textPseudoAudioLevel = 0
    }

    private func finalizeTextConversationTurn(userText: String, aiText: String) {
        appendContextTurn(userText: userText, aiText: aiText)
        MemoryStore.shared.addMemory(userText: userText, aiText: aiText)

        Task {
            await DeepSeekOrchestrator.shared.analyzeAndUpdateProfile(
                userText: userText,
                aiText: aiText
            )
        }

        Task { @MainActor in
            await MemoryCorridorStore.shared.recordConversationTurn(
                userText: userText,
                aiText: aiText,
                timestamp: Date()
            )
        }

        handlePhotoConversationTexts(userText: userText, aiText: aiText)
        isResponding = false
        activeResponseMode = nil
        textPseudoAudioLevel = 0
    }

    private func appendContextTurn(userText: String, aiText: String) {
        let normalizedUser = normalizeDialogueText(userText)
        let normalizedAI = normalizeDialogueText(aiText)
        guard !normalizedUser.isEmpty || !normalizedAI.isEmpty else { return }

        contextTurns.append(
            TextConversationContextTurn(
                userText: normalizedUser,
                aiText: normalizedAI
            )
        )

        if contextTurns.count > 12 {
            contextTurns.removeFirst(contextTurns.count - 12)
        }
    }

    private func startPhotoStorySession() {
        photoStoryUpdateTask?.cancel()
        photoStoryUpdateTask = nil
        photoStorySessionID = UUID()
        photoStoryTurns.removeAll()
        polaroidStoryText = ""
        isPhotoStoryTrackingActive = true
    }

    private func stopPhotoStorySession() {
        isPhotoStoryTrackingActive = false
        photoStorySessionID = UUID()
        photoStoryUpdateTask?.cancel()
        photoStoryUpdateTask = nil
        photoStoryTurns.removeAll()
        polaroidStoryText = ""
    }

    private func handlePhotoConversationTurn(_ turn: VoiceConversationTurn) {
        guard !turn.isInjectedQuery else { return }
        handlePhotoConversationTexts(userText: turn.userText, aiText: turn.aiText)
    }

    private func handlePhotoConversationTexts(userText: String, aiText: String) {
        guard isPhotoStoryTrackingActive else { return }
        let normalizedUser = normalizeDialogueText(userText)
        let normalizedAI = normalizeDialogueText(aiText)
        guard !normalizedUser.isEmpty || !normalizedAI.isEmpty else { return }

        photoStoryTurns.append(
            PhotoStoryDialogueTurn(
                userText: normalizedUser,
                aiText: normalizedAI
            )
        )

        let sessionID = photoStorySessionID
        let turnsSnapshot = photoStoryTurns
        let previousSummary = polaroidStoryText

        photoStoryUpdateTask?.cancel()
        photoStoryUpdateTask = Task {
            let summary = await PhotoStorySummaryService.shared.summarize(
                turns: turnsSnapshot,
                previousSummary: previousSummary
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard isPhotoStoryTrackingActive, photoStorySessionID == sessionID else { return }
                polaroidStoryText = normalizePhotoStorySummary(summary)
            }
        }
    }

    private func streamTextResponse(_ text: String) async {
        await MainActor.run {
            currentRoundAIText = ""
            textPseudoAudioLevel = 0
        }

        guard !text.isEmpty else {
            await MainActor.run {
                textPseudoAudioLevel = 0
            }
            return
        }

        let characters = Array(text)
        var collected = ""

        for character in characters {
            if Task.isCancelled { return }
            collected.append(character)
            let nextLevel = pseudoAudioLevel(for: character)

            await MainActor.run {
                currentRoundAIText = collected
                textPseudoAudioLevel = nextLevel
            }

            try? await Task.sleep(nanoseconds: 22_000_000)
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        await MainActor.run {
            textPseudoAudioLevel = 0
        }
    }

    private func handlePhotoConversationInjection(
        _ injectedText: String,
        photoDescription: String,
        for requestID: UUID
    ) async {
        let normalized = normalizeDialogueText(injectedText)
        guard !normalized.isEmpty else {
            await MainActor.run {
                guard photoConversationRequestID == requestID else { return }
                isResponding = false
                activeResponseMode = nil
                textPseudoAudioLevel = 0
            }
            return
        }

        enum InjectionMode {
            case text
            case voice
        }

        let mode = await MainActor.run { () -> InjectionMode? in
            guard photoConversationRequestID == requestID else { return nil }
            currentRoundUserText = ""
            currentRoundAIText = ""
            isResponding = true
            textPseudoAudioLevel = 0
            switch conversationMode {
            case .text:
                activeResponseMode = .text
                return .text
            case .voice:
                activeResponseMode = .voice
                return .voice
            }
        }

        guard let mode else { return }

        switch mode {
        case .voice:
            await MainActor.run {
                guard photoConversationRequestID == requestID else { return }
                voiceService.submitPhotoUnderstandingAsUserInput(normalized)
            }
        case .text:
            let fallback = TextConversationService.shared.makePhotoInjectionFallbackReply(
                from: photoDescription
            )
            let response = await TextConversationService.shared.generateReply(
                userText: normalized,
                history: contextTurns,
                fallbackOverride: fallback
            )
            let normalizedResponse = normalizeDialogueText(response)
            await streamTextResponse(normalizedResponse)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard photoConversationRequestID == requestID else { return }
                currentRoundAIText = normalizedResponse
                appendContextTurn(
                    userText: compactPhotoDescriptionForContext(photoDescription),
                    aiText: normalizedResponse
                )
                isResponding = false
                activeResponseMode = nil
                textPseudoAudioLevel = 0
            }
        }
    }

    private func pseudoAudioLevel(for character: Character) -> Float {
        if "。！？!?，,；;：:".contains(character) {
            return 0.78
        }
        return Float.random(in: 0.26...0.56)
    }

    private func normalizePhotoStorySummary(_ text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(compact.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeDialogueText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactPhotoDescriptionForContext(_ description: String) -> String {
        let normalized = normalizeDialogueText(description)
        guard !normalized.isEmpty else {
            return "【照片信息】用户上传了一张新照片"
        }
        let clipped = String(normalized.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "【照片信息】\(clipped)"
    }

    private func compactInjectedQueryForContext(_ injectedText: String) -> String {
        let normalized = normalizeDialogueText(injectedText)
        guard !normalized.isEmpty else {
            return "【照片信息】用户上传了一张新照片"
        }

        let infoMarker = "画面信息："
        let promptMarker = "请你先用2到3句口语化中文回应"

        if let infoRange = normalized.range(of: infoMarker) {
            let tail = String(normalized[infoRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let description: String
            if let promptRange = tail.range(of: promptMarker) {
                description = String(tail[..<promptRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                description = tail
            }

            if !description.isEmpty {
                return compactPhotoDescriptionForContext(description)
            }
        }

        return compactPhotoDescriptionForContext(normalized)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func updateKeyboardVisibility(from notification: Notification) {
        guard let endFrameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }

        let endFrame = endFrameValue.cgRectValue
        let screenHeight = UIScreen.main.bounds.height
        let safeAreaBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
        let overlap = max(0, screenHeight - endFrame.minY - safeAreaBottom)
        keyboardBottomInset = overlap
    }
}

private enum PostLoginAction {
    case membership
}

private enum MoreDrawerAction: String, Hashable {
    case membership
    case memoryCorridor
    case insight
    case paperSelection
    case contact
    case privacyPolicy
    case userAgreement
}

private struct MoreDrawerItem: Identifiable {
    var id: String { action.rawValue }
    let icon: String
    let title: String
    let action: MoreDrawerAction
}

private struct MoreDrawerPanel: View {
    var title: String
    var subtitle: String
    var items: [MoreDrawerItem]
    var headerLeadingInset: CGFloat
    var headerTrailingInset: CGFloat
    var onItemTap: (MoreDrawerItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white.opacity(0.98))

                Text(subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.top, 88)
            .padding(.leading, headerLeadingInset)
            .padding(.trailing, headerTrailingInset)
            .padding(.bottom, 44)

            VStack(alignment: .leading, spacing: 28) {
                ForEach(items) { item in
                    Button {
                        onItemTap(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 26, alignment: .center)

                            Text(item.title)
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            Color.black.opacity(0.94)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 1),
                    alignment: .trailing
                )
        )
    }
}

private struct PolaroidPaperSelectionView: View {
    let currentStyle: PolaroidPaperStyle
    var onConfirm: (PolaroidPaperStyle) -> Void
    var onClose: () -> Void

    @State private var pendingSelection: PolaroidPaperStyle
    private let topControlSize: CGFloat = 42
    private let gridColumns: [GridItem] = [
        .init(.flexible(minimum: 120), spacing: 20),
        .init(.flexible(minimum: 120), spacing: 20)
    ]

    init(
        currentStyle: PolaroidPaperStyle,
        onConfirm: @escaping (PolaroidPaperStyle) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.currentStyle = currentStyle
        self.onConfirm = onConfirm
        self.onClose = onClose
        _pendingSelection = State(initialValue: currentStyle)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .frame(width: topControlSize, height: topControlSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")

                    Spacer()

                    Text("相纸选择")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white.opacity(0.96))
                        .frame(height: topControlSize)

                    Spacer()

                    Color.clear
                        .frame(width: topControlSize, height: topControlSize)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 22) {
                        ForEach(PolaroidPaperStyle.allCases) { style in
                            Button {
                                pendingSelection = style
                            } label: {
                                PolaroidPaperStyleCard(
                                    style: style,
                                    isSelected: pendingSelection == style
                                )
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(pendingSelection == style ? 1.02 : 1.0)
                            .animation(.spring(response: 0.24, dampingFraction: 0.88), value: pendingSelection)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
                }

                Button {
                    onConfirm(pendingSelection)
                } label: {
                    Text("确认")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.94))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.78), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, max(16, proxy.safeAreaInsets.bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black.ignoresSafeArea())
        }
    }
}

private struct PolaroidPaperStyleCard: View {
    let style: PolaroidPaperStyle
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [style.selectionTopColor, style.selectionBottomColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.black.opacity(0.98))
                    .padding(.leading, 9)
                    .padding(.trailing, 9)
                    .padding(.top, 11)
                    .padding(.bottom, 31)
            }
            .aspectRatio(0.76, contentMode: .fit)
            .overlay {
                Text(style.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .shadow(color: .black.opacity(0.36), radius: 1.4, x: 0, y: 0.7)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(
                        isSelected ? style.borderColor.opacity(0.84) : Color.white.opacity(0.14),
                        lineWidth: isSelected ? 1.5 : 0.9
                    )
            )
            .shadow(
                color: Color.black.opacity(isSelected ? 0.32 : 0.2),
                radius: isSelected ? 12 : 8,
                x: 0,
                y: isSelected ? 7 : 4
            )

            if isSelected {
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black.opacity(0.85))
                    )
                    .padding(.top, 7)
                    .padding(.trailing, 7)
            }
        }
    }
}

private struct MemoryCorridorView: View {
    @ObservedObject private var corridorStore = MemoryCorridorStore.shared
    var onClose: () -> Void
    private let topControlSize: CGFloat = 42

    var body: some View {
        GeometryReader { proxy in
            let cardHeight = max(320, proxy.size.height * 0.60)
            let orderedEntries = corridorStore.getEntriesInCreationOrder()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .frame(width: topControlSize, height: topControlSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭记忆回廊")

                    Spacer()

                    Text("记忆回廊")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white.opacity(0.95))
                        .frame(height: topControlSize)

                    Spacer()

                    Color.clear
                        .frame(width: topControlSize, height: topControlSize)
                }
                .frame(height: topControlSize)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                if orderedEntries.isEmpty {
                    VStack(spacing: 12) {
                        Text("今天还没有生成日记")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.88))
                        Text("当你和 Gaya 开始对话后，会在每天结束时自动写入记忆回廊。")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 34)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { reader in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 14) {
                                ForEach(orderedEntries) { entry in
                                    MemoryCorridorDiaryCard(
                                        entry: entry,
                                        cardHeight: cardHeight
                                    )
                                    .id(entry.id)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 6)
                            .padding(.bottom, 20)
                        }
                        .onAppear {
                            guard let latestId = orderedEntries.last?.id else { return }
                            DispatchQueue.main.async {
                                reader.scrollTo(latestId, anchor: .bottom)
                            }
                        }
                        .onChange(of: orderedEntries.count) { _, _ in
                            guard let latestId = orderedEntries.last?.id else { return }
                            DispatchQueue.main.async {
                                reader.scrollTo(latestId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private struct MemoryCorridorDiaryCard: View {
    let entry: MemoryCorridorEntry
    let cardHeight: CGFloat

    private let headerHeight: CGFloat = 90

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.09, blue: 0.16),
                        Color(red: 0.02, green: 0.04, blue: 0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack(alignment: .top, spacing: 12) {
                    Text(entry.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 8)

                    Text(entry.dateString)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.62))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .frame(height: headerHeight)

            VStack(spacing: 0) {
                ScrollView {
                    Text(entry.content)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white.opacity(0.86))
                        .lineSpacing(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 16)
                }

                HStack(spacing: 22) {
                    MemoryCorridorPlaceholderButton(systemName: "tray.full", tint: Color.cyan)
                    MemoryCorridorPlaceholderButton(systemName: "doc.on.doc", tint: Color.white)
                    MemoryCorridorPlaceholderButton(systemName: "xmark", tint: Color.pink)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.1),
                            Color.black.opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.1),
                        Color(red: 0.02, green: 0.03, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
        )
        .shadow(color: Color.black.opacity(0.32), radius: 14, x: 0, y: 8)
    }
}

private struct MemoryCorridorPlaceholderButton: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        tint.opacity(0.34),
                        Color.white.opacity(0.03)
                    ],
                    center: .center,
                    startRadius: 2,
                    endRadius: 22
                )
            )
            .frame(width: 44, height: 44)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
            )
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
            )
    }
}

private struct LiquidGlassMenuCircleIcon: View {
    var size: CGFloat = 42
    var isActive: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.24 : 0.18),
                            Color.white.opacity(isActive ? 0.08 : 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.38 : 0.24),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.7
                    )
                )
                .blendMode(.screen)

            Circle()
                .stroke(Color.white.opacity(isActive ? 0.5 : 0.26), lineWidth: 0.9)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )

            VStack(alignment: .leading, spacing: 5) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 17, height: 2.2)

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 11, height: 2.2)
            }
            .frame(width: 17, alignment: .leading)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.white.opacity(isActive ? 0.18 : 0.1), radius: 4, x: -1, y: -1)
        .shadow(color: Color.black.opacity(isActive ? 0.34 : 0.24), radius: 10, x: 0, y: 6)
    }
}

private struct AuthUser: Codable {
    let uid: String
    let nickname: String
    let isNewUser: Bool?

    enum CodingKeys: String, CodingKey {
        case uid
        case nickname
        case isNewUser = "is_new_user"
    }
}

private struct AuthSessionPayload: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

private struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAt: Date
}

private struct AuthPersistedState: Codable {
    let user: AuthUser
    let session: AuthSession
}

private struct AuthEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
}

private struct AuthLoginResult: Decodable {
    let user: AuthUser
    let session: AuthSessionPayload
}

private struct SMSChallengeResult: Decodable {
    let challengeID: String
    let resendAfterSeconds: Int
    let expireAfterSeconds: Int

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case resendAfterSeconds = "resend_after_seconds"
        case expireAfterSeconds = "expire_after_seconds"
    }
}

private struct AuthAPIConfig {
    let baseURL: URL
    let oneTapLoginPath: String
    let smsSendPath: String
    let smsVerifyPath: String

    static func current() -> AuthAPIConfig {
        let info = Bundle.main.infoDictionary
        let rawBaseURL = (info?["AUTH_API_BASE_URL"] as? String) ?? "https://YOUR_CLOUDBASE_HTTP_DOMAIN"
        let oneTapPath = (info?["AUTH_ONETAP_LOGIN_PATH"] as? String) ?? "/auth/onetap/login"
        let smsSendPath = (info?["AUTH_SMS_SEND_PATH"] as? String) ?? "/auth/sms/send"
        let smsVerifyPath = (info?["AUTH_SMS_VERIFY_PATH"] as? String) ?? "/auth/sms/verify"
        let url = URL(string: rawBaseURL) ?? URL(string: "https://YOUR_CLOUDBASE_HTTP_DOMAIN")!
        return AuthAPIConfig(
            baseURL: url,
            oneTapLoginPath: oneTapPath,
            smsSendPath: smsSendPath,
            smsVerifyPath: smsVerifyPath
        )
    }
}

private enum AuthError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case notConfigured
    case business(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "登录配置无效，请检查 AUTH_API_BASE_URL。"
        case .invalidResponse:
            return "登录服务返回异常，请稍后重试。"
        case .notConfigured:
            return "一键登录 SDK 未接入，请先执行 pod install，并使用 gaya.xcworkspace 构建。"
        case .business(let message):
            return message
        }
    }
}

private protocol MobileOneTapProvider {
    func prepareMaskedPhone() async -> String?
    func fetchLoginToken() async throws -> String
}

private struct PlaceholderOneTapProvider: MobileOneTapProvider {
    func prepareMaskedPhone() async -> String? {
        return nil
    }

    func fetchLoginToken() async throws -> String {
        throw AuthError.notConfigured
    }
}

private enum OneTapProviderFactory {
    static func make() -> MobileOneTapProvider {
        AliyunPNVSOneTapProvider()
    }
}

private struct AliyunPNVSOneTapProvider: MobileOneTapProvider {
    private let successCodes: Set<String> = ["6666", "600000"]
    private let cancelCodes: Set<String> = ["6667", "700000", "700001"]

    func prepareMaskedPhone() async -> String? {
        nil
    }

    func fetchLoginToken() async throws -> String {
        #if canImport(ATAuthSDK)
        let controller = await MainActor.run { UIApplication.topMostViewController() }
        guard let controller else {
            throw AuthError.business("当前页面不可用，请稍后再试")
        }

        let handler = TXCommonHandler.sharedInstance()

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            handler.getLoginToken(with: controller, model: nil, timeout: 5.0) { payload in
                guard !resumed else { return }
                let result = parseResult(payload)
                let code = result.code

                if let token = result.token, !token.isEmpty, successCodes.contains(code) {
                    resumed = true
                    handler.cancelLoginVC(animated: true, complete: nil)
                    continuation.resume(returning: token)
                    return
                }

                resumed = true
                if cancelCodes.contains(code) {
                    continuation.resume(throwing: AuthError.business("你已取消本机号码登录"))
                    return
                }

                let message = result.message.isEmpty
                    ? "本机号码登录失败(\(code.isEmpty ? "未知" : code))"
                    : result.message
                continuation.resume(throwing: AuthError.business(message))
            }
        }
        #else
        throw AuthError.notConfigured
        #endif
    }

    #if canImport(ATAuthSDK)
    private func parseResult(_ payload: Any?) -> (code: String, message: String, token: String?) {
        guard let dictionary = payload as? [AnyHashable: Any] else {
            return ("", "一键登录返回异常", nil)
        }

        let code = value(for: ["resultCode", "code"], in: dictionary)
        let message = value(for: ["msg", "message", "resultMsg"], in: dictionary)
        let token = value(for: ["token"], in: dictionary)
        return (code, message, token.isEmpty ? nil : token)
    }

    private func value(for keys: [String], in dictionary: [AnyHashable: Any]) -> String {
        for key in keys {
            if let value = dictionary[key], let stringValue = String(describing: value).nilIfNull {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return ""
    }
    #endif
}

private extension String {
    var nilIfNull: String? {
        let lowered = lowercased()
        if lowered == "null" || lowered == "<null>" {
            return nil
        }
        return self
    }
}

private extension UIApplication {
    static func topMostViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
    ) -> UIViewController? {
        if let navigation = base as? UINavigationController {
            return topMostViewController(base: navigation.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topMostViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return base
    }
}

@MainActor
private final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var user: AuthUser?
    @Published private(set) var session: AuthSession?
    @Published private(set) var oneTapMaskedPhone: String = "请使用本机号码授权"

    var isLoggedIn: Bool {
        user != nil && session != nil
    }

    var userNickname: String {
        user?.nickname ?? ""
    }

    private let config = AuthAPIConfig.current()
    private let oneTapProvider: MobileOneTapProvider
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let persistedStateKey = "gaya.auth.persisted.state"
    private var deviceID: String

    private init(oneTapProvider: MobileOneTapProvider = OneTapProviderFactory.make()) {
        self.oneTapProvider = oneTapProvider
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.deviceID = Self.resolveDeviceID()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder.dateEncodingStrategy = .iso8601

        restoreState()
        Task {
            await prepareOneTapMaskedPhone()
        }
    }

    func prepareOneTapMaskedPhone() async {
        let masked = await oneTapProvider.prepareMaskedPhone()
        oneTapMaskedPhone = masked ?? "请使用本机号码授权"
    }

    func sendSMSCode(
        phoneNumber: String,
        agreementAccepted: Bool
    ) async throws -> SMSChallengeResult {
        guard agreementAccepted else {
            throw AuthError.business("请先阅读并同意协议")
        }

        let payload: [String: Any] = [
            "phone_number": phoneNumber,
            "agreement_accepted": agreementAccepted
        ]
        return try await post(path: config.smsSendPath, payload: payload)
    }

    func loginWithSMS(
        phoneNumber: String,
        verifyCode: String,
        challengeID: String,
        nickname: String = "",
        agreementAccepted: Bool
    ) async throws {
        guard agreementAccepted else {
            throw AuthError.business("请先阅读并同意协议")
        }

        let payload: [String: Any] = [
            "phone_number": phoneNumber,
            "verify_code": verifyCode,
            "challenge_id": challengeID,
            "nickname": nickname,
            "agreement_accepted": agreementAccepted
        ]

        let result: AuthLoginResult = try await post(path: config.smsVerifyPath, payload: payload)
        applyLoginResult(result)
    }

    func loginWithOneTap(
        agreementAccepted: Bool,
        nickname: String = ""
    ) async throws {
        guard agreementAccepted else {
            throw AuthError.business("请先阅读并同意协议")
        }

        let oneTapToken = try await oneTapProvider.fetchLoginToken()
        let payload: [String: Any] = [
            "one_tap_token": oneTapToken,
            "nickname": nickname,
            "agreement_accepted": agreementAccepted
        ]

        let result: AuthLoginResult = try await post(path: config.oneTapLoginPath, payload: payload)
        applyLoginResult(result)
    }

    func logout() {
        user = nil
        session = nil
        KeychainStore.delete(for: persistedStateKey)
        switchToNamespace(uid: nil)
    }

    private func applyLoginResult(_ result: AuthLoginResult) {
        let expiresAt = Date().addingTimeInterval(TimeInterval(max(result.session.expiresIn, 300)))
        let session = AuthSession(
            accessToken: result.session.accessToken,
            refreshToken: result.session.refreshToken,
            tokenType: result.session.tokenType,
            expiresAt: expiresAt
        )

        self.user = result.user
        self.session = session
        persistState()
        switchToNamespace(uid: result.user.uid)
    }

    private func switchToNamespace(uid: String?) {
        let normalizedUID = uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let namespace = normalizedUID.isEmpty ? "guest" : normalizedUID
        MemoryStore.shared.switchNamespace(namespace)
        Task { @MainActor in
            await MemoryCorridorStore.shared.switchNamespace(namespace)
        }
    }

    private func restoreState() {
        guard let data = KeychainStore.read(for: persistedStateKey),
              let state = try? decoder.decode(AuthPersistedState.self, from: data) else {
            switchToNamespace(uid: nil)
            return
        }

        guard state.session.expiresAt > Date() else {
            user = nil
            session = nil
            KeychainStore.delete(for: persistedStateKey)
            switchToNamespace(uid: nil)
            return
        }

        user = state.user
        session = state.session
        switchToNamespace(uid: state.user.uid)
    }

    private func persistState() {
        guard let user, let session else { return }
        let state = AuthPersistedState(user: user, session: session)
        guard let data = try? encoder.encode(state) else { return }
        KeychainStore.write(data, for: persistedStateKey)
    }

    private func post<T: Decodable>(
        path: String,
        payload: [String: Any]
    ) async throws -> T {
        guard config.baseURL.absoluteString != "https://YOUR_CLOUDBASE_HTTP_DOMAIN" else {
            throw AuthError.invalidConfiguration
        }

        guard let url = URL(string: path, relativeTo: config.baseURL) else {
            throw AuthError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "x-device-id")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        let envelope = try decoder.decode(AuthEnvelope<T>.self, from: data)
        guard (200 ... 299).contains(http.statusCode), envelope.code == 0, let payload = envelope.data else {
            let message = envelope.message.isEmpty ? "登录失败，请稍后重试" : envelope.message
            throw AuthError.business(message)
        }

        return payload
    }

    private static func resolveDeviceID() -> String {
        let key = "gaya.auth.device.id"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }

        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}

private enum KeychainStore {
    static func write(_ data: Data, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct AuthLoginFlowView: View {
    @ObservedObject var authService: AuthService
    let onLoginSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: LoginMode = .oneTap
    @State private var phoneText: String = ""
    @State private var codeText: String = ""
    @State private var challengeID: String = ""
    @State private var countdown: Int = 0
    @State private var agreementAccepted = false
    @State private var isProcessing = false
    @State private var errorText: String?
    @State private var countdownTask: Task<Void, Never>?

    private enum LoginMode {
        case oneTap
        case sms
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.09),
                    Color(red: 0.04, green: 0.05, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if mode == .oneTap {
                    oneTapContent
                } else {
                    smsContent
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)

            if isProcessing {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .task {
            await authService.prepareOneTapMaskedPhone()
        }
        .onDisappear {
            countdownTask?.cancel()
            countdownTask = nil
        }
        .onChange(of: phoneText) { _, newValue in
            let digits = newValue.filter { $0.isNumber }
            phoneText = String(digits.prefix(11))
        }
        .onChange(of: codeText) { _, newValue in
            let digits = newValue.filter { $0.isNumber }
            codeText = String(digits.prefix(6))
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            if mode == .oneTap {
                Button("验证码登录") {
                    mode = .sms
                    errorText = nil
                }
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color(red: 0.96, green: 0.86, blue: 0.52))
            } else {
                Button("本机号码登录") {
                    mode = .oneTap
                    errorText = nil
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.white.opacity(0.7))
            }
        }
        .padding(.top, 8)
    }

    private var oneTapContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            VStack(spacing: 22) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color(red: 0.96, green: 0.86, blue: 0.52), lineWidth: 4)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(Color(red: 0.96, green: 0.86, blue: 0.52))
                    )

                Text("星野")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(Color(red: 0.96, green: 0.86, blue: 0.52))
            }

            Spacer(minLength: 120)

            Text("本机号码登录")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.62))

            Text(authService.oneTapMaskedPhone)
                .font(.system(size: 46, weight: .bold))
                .foregroundColor(.white.opacity(0.92))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .padding(.top, 14)

            Button {
                submitOneTapLogin()
            } label: {
                Text("一键登录")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(Color(red: 0.05, green: 0.07, blue: 0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 82)
                    .background(
                        RoundedRectangle(cornerRadius: 41, style: .continuous)
                            .fill(Color(red: 0.94, green: 0.84, blue: 0.52))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 36)

            Button {
                mode = .sms
                errorText = nil
            } label: {
                Text("其他手机号登录")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 82)
                    .background(
                        RoundedRectangle(cornerRadius: 41, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 20)

            agreementRow
                .padding(.top, 26)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.top, 14)
            }
        }
    }

    private var smsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 36)

            Text("欢迎登录 星野")
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(.white.opacity(0.94))

            Text("未注册的手机号验证通过后将自动注册")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.white.opacity(0.42))
                .padding(.top, 18)

            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    Text("+86")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))

                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 30)

                    TextField("输入手机号", text: $phoneText)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 28)
                .frame(height: 86)
                .background(
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )

                HStack(spacing: 12) {
                    TextField("输入验证码", text: $codeText)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))

                    Button {
                        sendSMSCode()
                    } label: {
                        Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(countdown > 0 ? .white.opacity(0.45) : .white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .disabled(countdown > 0 || phoneText.count != 11 || !agreementAccepted)
                }
                .padding(.horizontal, 28)
                .frame(height: 86)
                .background(
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
            .padding(.top, 40)

            Button {
                submitSMSLogin()
            } label: {
                Text("确认登录")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(Color(red: 0.05, green: 0.07, blue: 0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 82)
                    .background(
                        RoundedRectangle(cornerRadius: 41, style: .continuous)
                            .fill(canSubmitSMS ? Color(red: 0.94, green: 0.84, blue: 0.52) : Color(red: 0.43, green: 0.39, blue: 0.25))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitSMS)
            .padding(.top, 52)

            agreementRow
                .padding(.top, 26)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.top, 14)
            }
        }
    }

    private var agreementRow: some View {
        HStack(spacing: 12) {
            Button {
                agreementAccepted.toggle()
                errorText = nil
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 25, height: 25)
                    if agreementAccepted {
                        Circle()
                            .fill(Color(red: 0.94, green: 0.84, blue: 0.52))
                            .frame(width: 13, height: 13)
                    }
                }
            }
            .buttonStyle(.plain)

            Text("已阅读并同意《用户服务协议》《用户隐私政策》《中国移动认证服务条款》")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.52))
                .lineLimit(2)
        }
    }

    private var canSubmitSMS: Bool {
        agreementAccepted && phoneText.count == 11 && codeText.count == 6 && !challengeID.isEmpty
    }

    private func sendSMSCode() {
        guard agreementAccepted else {
            errorText = "请先阅读并同意协议"
            return
        }
        guard phoneText.count == 11 else {
            errorText = "请输入正确的手机号"
            return
        }

        errorText = nil
        isProcessing = true

        Task {
            defer {
                Task { @MainActor in
                    isProcessing = false
                }
            }

            do {
                let challenge = try await authService.sendSMSCode(
                    phoneNumber: phoneText,
                    agreementAccepted: agreementAccepted
                )
                await MainActor.run {
                    challengeID = challenge.challengeID
                    startSMSCountdown(seconds: max(challenge.resendAfterSeconds, 1))
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func submitSMSLogin() {
        guard canSubmitSMS else {
            errorText = "请完成手机号和验证码填写"
            return
        }

        errorText = nil
        isProcessing = true

        Task {
            defer {
                Task { @MainActor in
                    isProcessing = false
                }
            }

            do {
                try await authService.loginWithSMS(
                    phoneNumber: phoneText,
                    verifyCode: codeText,
                    challengeID: challengeID,
                    agreementAccepted: agreementAccepted
                )
                await MainActor.run {
                    onLoginSuccess()
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func submitOneTapLogin() {
        guard agreementAccepted else {
            errorText = "请先阅读并同意协议"
            return
        }

        errorText = nil
        isProcessing = true

        Task {
            defer {
                Task { @MainActor in
                    isProcessing = false
                }
            }

            do {
                try await authService.loginWithOneTap(agreementAccepted: agreementAccepted)
                await MainActor.run {
                    onLoginSuccess()
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func startSMSCountdown(seconds: Int) {
        countdownTask?.cancel()
        countdown = seconds
        countdownTask = Task {
            while !Task.isCancelled && countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    countdown = max(0, countdown - 1)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
