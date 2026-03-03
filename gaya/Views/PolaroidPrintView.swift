import SwiftUI
import UIKit
import CoreText
import AVFoundation
import CoreMotion
import Photos
import ImageIO
import UniformTypeIdentifiers
import PhotosUI

private struct TopControlsBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 70

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DynamicPolaroidView: View {
    let image: UIImage
    var cardWidth: CGFloat
    var edgePadding: CGFloat = 12
    var developmentProgress: CGFloat
    var captionText: String = ""
    var backStoryText: String = ""
    var paperStyle: PolaroidPaperStyle = .defaultStyle
    var livePlaybackEnabled: Bool = false
    var includeDropShadow: Bool = true
    @State private var captionInkSaturation: Double = Double.random(in: 0.9...0.96)
    @StateObject private var reflectionMotion = PhotoReflectionMotion()
    @State private var liveFlipAngle: Double = 0
    @State private var liveFlipTask: Task<Void, Never>?
    @State private var isLiveFlipping = false
    @State private var liveImpact = UIImpactFeedbackGenerator(style: .light)

    private var imageAspectRatio: CGFloat {
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        return width / height
    }

    private var imageFrameWidth: CGFloat {
        max(1, cardWidth - edgePadding * 2)
    }

    private var imageFrameHeight: CGFloat {
        imageFrameWidth / imageAspectRatio
    }

    private var bottomPadding: CGFloat {
        edgePadding * 4
    }

    private var cardHeight: CGFloat {
        edgePadding + imageFrameHeight + bottomPadding
    }

    private var captionFontSize: CGFloat {
        max(20, imageFrameWidth * 0.085)
    }

    var body: some View {
        let normalizedProgress = min(max(developmentProgress, 0), 1)
        let progress = Double(normalizedProgress)
        let styleScale = max(0.85, min(1.4, cardWidth / 760))
        let blurRadius = (1 - progress) * 3.6
        let saturation = 0.03 + progress * 0.97
        let contrast = 0.52 + progress * 0.66
        let whiteVeilOpacity = (1 - progress) * 0.08
        let chemicalFogOpacity = (1 - progress) * 0.32
        let chemicalBlue = Color(red: 0.19, green: 0.27, blue: 0.33)
        let chemicalGreen = Color(red: 0.16, green: 0.25, blue: 0.2)
        let chemicalMultiply = Color(
            red: 0.34 + progress * 0.66,
            green: 0.39 + progress * 0.61,
            blue: 0.43 + progress * 0.57
        )
        let frontPaperGradient = LinearGradient(
            colors: [paperStyle.frontTopColor, paperStyle.frontBottomColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let cardCornerRadius: CGFloat = 6 * styleScale
        let photoCornerRadius: CGFloat = 2.2 * styleScale
        let outerStrokeWidth: CGFloat = 0.9 * styleScale

        let frontCard = ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(frontPaperGradient)
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                )
                .overlay(
                    PaperTextureOverlay(opacity: 0.018)
                        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .strokeBorder(paperStyle.borderColor.opacity(0.46), lineWidth: outerStrokeWidth)
                )

            ZStack {
                Rectangle()
                    .fill(Color(red: 0.1, green: 0.13, blue: 0.14).opacity(0.94 - progress * 0.62))
                    .frame(width: imageFrameWidth, height: imageFrameHeight)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageFrameWidth, height: imageFrameHeight)
                    .blur(radius: blurRadius)
                    .saturation(saturation)
                    .contrast(contrast)
                    .colorMultiply(chemicalMultiply)

                // Subtle bloom on bright regions to mimic light spill on instant film coating.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageFrameWidth, height: imageFrameHeight)
                    .saturation(saturation * 1.08 + 0.02)
                    .contrast(contrast * 1.22)
                    .brightness(0.04)
                    .blur(radius: 1.2)
                    .opacity(0.08 + progress * 0.12)
                    .blendMode(.screen)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                chemicalBlue.opacity(0.75 - progress * 0.62),
                                chemicalGreen.opacity(0.7 - progress * 0.58)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: imageFrameWidth, height: imageFrameHeight)
                    .opacity(chemicalFogOpacity)
                    .blendMode(.multiply)

                Rectangle()
                    .fill(Color.white.opacity(whiteVeilOpacity))
                    .frame(width: imageFrameWidth, height: imageFrameHeight)

                PlasticReflectionOverlay(
                    motionOffset: reflectionMotion.offset,
                    progress: progress
                )
                .frame(width: imageFrameWidth, height: imageFrameHeight)

                SubtleVignetteOverlay(intensity: 0.08)
                    .frame(width: imageFrameWidth, height: imageFrameHeight)
            }
            .clipShape(RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.75)
                    .blur(radius: 0.75)
                    .offset(x: 0.15, y: 0.5)
                    .mask(
                        RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.black, .black.opacity(0.62), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                    .blur(radius: 0.68)
                    .offset(y: 0.2)
                    .mask(
                        RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.black, .black.opacity(0.75), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: photoCornerRadius + 0.4, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.6)
                    .blur(radius: 0.65)
                    .opacity(0.58)
            }
            .padding(.leading, edgePadding)
            .padding(.top, edgePadding)
            .overlay(alignment: .topLeading) {
                // Slight color spill beyond image edge to mimic dye spread on instant film.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: imageFrameWidth, height: imageFrameHeight)
                    .scaleEffect(1.01)
                    .saturation(1.06)
                    .blur(radius: 0.52)
                    .opacity(0.03 + progress * 0.07)
                    .blendMode(.plusLighter)
                    .mask(
                        RoundedRectangle(cornerRadius: photoCornerRadius + 0.2, style: .continuous)
                            .stroke(Color.white, lineWidth: 0.24)
                            .blur(radius: 0.24)
                    )
                    .padding(.leading, edgePadding)
                    .padding(.top, edgePadding)
                    .allowsHitTesting(false)
            }

            if !captionText.isEmpty {
                Text(captionText)
                    .font(.custom(PolaroidHandwritingFont.fontName, size: captionFontSize))
                    .foregroundStyle(paperStyle.inkColor.opacity(0.76))
                    .saturation(captionInkSaturation)
                    .blendMode(.multiply)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .multilineTextAlignment(.center)
                    .frame(width: imageFrameWidth - 6, alignment: .center)
                    .padding(.leading, edgePadding + 3)
                    .padding(.top, edgePadding + imageFrameHeight + bottomPadding * 0.26)
            }
        }
        .frame(width: cardWidth, height: cardHeight)

        let backCard = PolaroidBackFaceView(
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            storyText: backStoryText,
            paperStyle: paperStyle
        )

        ZStack {
            frontCard
                .opacity(liveFlipAngle < 90 ? 1 : 0)

            backCard
                .opacity(liveFlipAngle >= 90 ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(width: cardWidth, height: cardHeight)
        .rotation3DEffect(
            .degrees(liveFlipAngle),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center,
            perspective: 0.78
        )
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(includeDropShadow ? 0.14 : 0),
            radius: includeDropShadow ? 12 : 0,
            x: 0,
            y: includeDropShadow ? 7 : 0
        )
        .overlay(alignment: .bottomLeading) {
            if livePlaybackEnabled {
                Button {
                    triggerLiveFlip()
                } label: {
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.2))
                                .frame(width: 14, height: 14)

                            Circle()
                                .stroke(Color.white.opacity(0.82), lineWidth: 0.8)
                                .frame(width: 10, height: 10)

                            Circle()
                                .stroke(
                                    Color.white.opacity(0.74),
                                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [0.9, 1.8])
                                )
                                .frame(width: 14, height: 14)

                            Image(systemName: "play.fill")
                                .font(.system(size: 5.6, weight: .bold))
                                .foregroundStyle(.white.opacity(0.95))
                                .offset(x: 0.35)
                        }

                        Text("实况")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.94))
                    }
                    .padding(.leading, 7)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.28, green: 0.28, blue: 0.3).opacity(0.92))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.64)
                    )
                }
                .buttonStyle(.plain)
                // Capsule's left edge aligns with the polaroid card's outer left edge.
                // Keep capsule fully outside the bottom border with ~2pt breathing room.
                .offset(x: 0, y: 24)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onAppear {
            PolaroidHandwritingFont.registerIfNeeded()
            reflectionMotion.start()
            liveImpact.prepare()
        }
        .onChange(of: livePlaybackEnabled) { _, enabled in
            if !enabled {
                cancelLiveFlip(resetAngle: true)
            }
        }
        .onDisappear {
            reflectionMotion.stop()
            cancelLiveFlip(resetAngle: true)
        }
    }

    private func triggerLiveFlip() {
        guard livePlaybackEnabled else { return }
        guard !isLiveFlipping else { return }

        liveImpact.impactOccurred(intensity: 0.68)
        liveImpact.prepare()
        isLiveFlipping = true

        liveFlipTask?.cancel()
        liveFlipTask = Task { @MainActor in
            defer {
                isLiveFlipping = false
                liveFlipTask = nil
            }

            withAnimation(.easeInOut(duration: 1.0)) {
                liveFlipAngle = 180
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 1.0)) {
                liveFlipAngle = 0
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func cancelLiveFlip(resetAngle: Bool) {
        liveFlipTask?.cancel()
        liveFlipTask = nil
        isLiveFlipping = false

        guard resetAngle else { return }
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            liveFlipAngle = 0
        }
    }
}

private struct PolaroidBackFaceView: View {
    var cardWidth: CGFloat
    var cardHeight: CGFloat
    var storyText: String = ""
    var paperStyle: PolaroidPaperStyle = .defaultStyle

    private var normalizedStory: String {
        storyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let backPaperGradient = LinearGradient(
            colors: [paperStyle.backTopColor, paperStyle.backBottomColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let styleScale = max(0.85, min(1.4, cardWidth / 760))
        let cardCornerRadius: CGFloat = 6 * styleScale
        let lineColor = paperStyle.backLineColor.opacity(0.17)
        let contentInsetX = max(24, cardWidth * 0.09)
        let contentInsetTop = max(18, cardHeight * 0.14)
        let storyFontSize = max(24, cardWidth * 0.057)

        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(backPaperGradient)
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                )
                .overlay(
                    PaperTextureOverlay(opacity: 0.016)
                        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .strokeBorder(paperStyle.borderColor.opacity(0.36), lineWidth: 0.65 * styleScale)
                )

            if !normalizedStory.isEmpty {
                VStack(spacing: max(18, cardHeight * 0.08)) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(lineColor)
                            .frame(height: 0.8)
                    }
                }
                .padding(.horizontal, contentInsetX - 8)
                .offset(y: cardHeight * 0.04)
                .allowsHitTesting(false)

                Text(normalizedStory)
                    .font(.custom(PolaroidHandwritingFont.fontName, size: storyFontSize))
                    .foregroundStyle(paperStyle.inkColor.opacity(0.74))
                    .saturation(0.94)
                    .blendMode(.multiply)
                    .lineSpacing(max(2, cardHeight * 0.006))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, contentInsetX)
                    .padding(.trailing, contentInsetX)
                    .padding(.top, contentInsetTop)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

private struct PlasticReflectionOverlay: View {
    var motionOffset: CGSize
    var progress: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let sheenOpacity = 0.1 + progress * 0.08

            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.44),
                        Color.white.opacity(0.16),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: width * 0.62, height: height * 1.28)
                .rotationEffect(.degrees(-23))
                .offset(
                    x: motionOffset.width * 0.65 - width * 0.16,
                    y: motionOffset.height * 0.48 - height * 0.04
                )
                .blur(radius: 0.95)

                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.36),
                        Color.white.opacity(0.08),
                        .clear
                    ]),
                    center: .center,
                    startRadius: 1,
                    endRadius: max(width, height) * 0.32
                )
                .frame(width: width * 0.46, height: height * 0.4)
                .offset(
                    x: motionOffset.width * 0.9 + width * 0.18,
                    y: motionOffset.height * 0.4 - height * 0.28
                )
                .blur(radius: 1.1)
            }
            .opacity(sheenOpacity)
            .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }
}

private final class PhotoReflectionMotion: ObservableObject {
    @Published var offset: CGSize = .zero

    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "polaroid.reflection.motion.queue"
        queue.qualityOfService = .userInteractive
        return queue
    }()

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let roll = max(-1, min(1, motion.attitude.roll / 0.5))
            let pitch = max(-1, min(1, motion.attitude.pitch / 0.5))
            let mapped = CGSize(
                width: roll * 14,
                height: -pitch * 10
            )

            DispatchQueue.main.async {
                self.offset = mapped
            }
        }
    }

    func stop() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        DispatchQueue.main.async { [weak self] in
            self?.offset = .zero
        }
    }

    deinit {
        stop()
    }
}

private struct PaperTextureOverlay: View {
    var opacity: Double

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let cell: CGFloat = 2.2

            for y in stride(from: CGFloat.zero, through: size.height, by: cell) {
                for x in stride(from: CGFloat.zero, through: size.width, by: cell) {
                    let coarseNoise = pseudoNoise(Double(x) * 0.32, Double(y) * 0.31)
                    let fineNoise = pseudoNoise(Double(x) * 1.17 + 23.1, Double(y) * 1.11 + 11.9)
                    let mixed = coarseNoise * 0.62 + fineNoise * 0.38
                    let centered = mixed - 0.5
                    let alpha = pow(abs(centered), 1.22) * opacity * 0.95
                    guard alpha > 0.0013 else { continue }

                    let tone: Color = centered > 0
                        ? .white.opacity(alpha)
                        : .black.opacity(alpha)
                    let sizeFactor = 0.44 + CGFloat(fineNoise) * 0.46
                    let dotSize = cell * sizeFactor
                    let jitterX = (CGFloat(pseudoNoise(Double(x) * 0.71 + 7.3, Double(y) * 0.67 + 2.1)) - 0.5) * cell * 0.52
                    let jitterY = (CGFloat(pseudoNoise(Double(x) * 0.66 + 13.7, Double(y) * 0.73 + 4.6)) - 0.5) * cell * 0.52
                    let rect = CGRect(
                        x: x + jitterX + (cell - dotSize) * 0.5,
                        y: y + jitterY + (cell - dotSize) * 0.5,
                        width: dotSize,
                        height: dotSize
                    )

                    context.fill(Path(ellipseIn: rect), with: .color(tone))
                }
            }
        }
        .blur(radius: 0.22)
        .allowsHitTesting(false)
    }
}

private struct SubtleVignetteOverlay: View {
    var intensity: Double

    var body: some View {
        GeometryReader { proxy in
            let minSide = min(proxy.size.width, proxy.size.height)
            let maxSide = max(proxy.size.width, proxy.size.height)

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.46),
                    .init(color: Color.black.opacity(intensity * 0.56), location: 0.8),
                    .init(color: Color.black.opacity(intensity), location: 1.0)
                ]),
                center: .center,
                startRadius: minSide * 0.2,
                endRadius: maxSide * 0.78
            )
            .blendMode(.multiply)
        }
        .allowsHitTesting(false)
    }
}

private func pseudoNoise(_ x: Double, _ y: Double, _ t: Double = 0) -> Double {
    let seed = sin(x * 12.9898 + y * 78.233 + t * 37.719) * 43_758.5453
    return seed - floor(seed)
}

struct PolaroidPrintStageView: View {
    let image: UIImage
    var captionText: String = ""
    var backStoryText: String = ""
    var paperStyle: PolaroidPaperStyle = .defaultStyle
    var horizontalPadding: CGFloat = 10
    var edgePadding: CGFloat = 12
    var topLimitY: CGFloat = 70
    var bottomLimitY: CGFloat?

    @State private var extrusionProgress: CGFloat = 0
    @State private var developmentProgress: CGFloat = 0
    @State private var displayedCaption: String = ""
    @State private var printFinished = false
    @State private var captionTask: Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?
    @State private var extrusionStartDate = Date()
    @State private var feedbackGenerator = UINotificationFeedbackGenerator()
    @StateObject private var mechanicalAudio = PolaroidMechanicalAudioPlayer()

    private let extrusionDuration: TimeInterval = 6.0
    private let developmentDuration: TimeInterval = 4.0
    private let developmentDelay: TimeInterval = 1.2

    private var imageAspectRatio: CGFloat {
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        return width / height
    }

    private func cardHeight(for cardWidth: CGFloat) -> CGFloat {
        let imageWidth = max(1, cardWidth - edgePadding * 2)
        let imageHeight = imageWidth / imageAspectRatio
        return edgePadding + imageHeight + edgePadding * 4
    }

    var body: some View {
        GeometryReader { proxy in
            let rawCardWidth = max(160, proxy.size.width - horizontalPadding * 2)
            let rawCardHeight = cardHeight(for: rawCardWidth)
            let stageHeight = proxy.size.height
            let measuredTop = max(0, min(topLimitY, stageHeight))
            let measuredBottom = min(bottomLimitY ?? stageHeight, stageHeight)
            let topInset: CGFloat = 6
            let bottomInset: CGFloat = 10
            let sideInset: CGFloat = 6
            let contentTop = min(measuredTop + topInset, stageHeight - 44)
            let contentBottom = max(contentTop + 44, measuredBottom - bottomInset)
            let contentHeight = max(44, contentBottom - contentTop)
            // Raise the virtual ejection slit so tall (e.g. 9:16) cards keep a visible top frame.
            let slotY = max(-24, measuredTop - 28)
            let maxCardWidthByViewport = max(120, proxy.size.width - horizontalPadding * 2 - sideInset * 2)
            let widthScale = min(1, maxCardWidthByViewport / rawCardWidth)
            let maxCardHeightByViewport = max(44, contentHeight - 18)
            let heightScale = min(1, maxCardHeightByViewport / rawCardHeight)
            let fitScale = min(widthScale, heightScale)
            let cardWidth = rawCardWidth * fitScale
            let cardHeight = rawCardHeight * fitScale
            let slotThickness = max(4.2, min(7, cardHeight * 0.013))
            let maskTopY = slotY + slotThickness * 0.42
            let centeredTopY = (contentTop + contentBottom - cardHeight) * 0.5
            let minTopY = max(maskTopY + 24, contentTop + 3)
            let maxTopY = max(minTopY, contentBottom - cardHeight - 3)
            let finalTopY = min(max(centeredTopY, minTopY), maxTopY)
            let startTopY = slotY - cardHeight + slotThickness * 0.45
            let currentTopY = startTopY + (finalTopY - startTopY) * extrusionProgress
            let currentCenterY = currentTopY + cardHeight * 0.5

            ZStack {
                Color.clear

                ZStack {
                    TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
                        let jitter = jitterOffset(at: timeline.date)

                        DynamicPolaroidView(
                            image: image,
                            cardWidth: cardWidth,
                            edgePadding: edgePadding,
                            developmentProgress: developmentProgress,
                            captionText: displayedCaption,
                            backStoryText: backStoryText,
                            paperStyle: paperStyle,
                            livePlaybackEnabled: printFinished
                        )
                        .position(x: proxy.size.width * 0.5, y: currentCenterY)
                        .offset(x: jitter.width, y: jitter.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mask {
                    Rectangle()
                        .frame(width: proxy.size.width, height: max(0, proxy.size.height - maskTopY), alignment: .top)
                        .offset(y: maskTopY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            PolaroidHandwritingFont.registerIfNeeded()
            mechanicalAudio.preload()
            feedbackGenerator.prepare()
            runPrintAnimation()
        }
        .onChange(of: captionText) { _, _ in
            startCaptionAnimationIfNeeded()
        }
        .onDisappear {
            captionTask?.cancel()
            completionTask?.cancel()
            mechanicalAudio.teardown()
        }
    }

    private func runPrintAnimation() {
        captionTask?.cancel()
        completionTask?.cancel()
        displayedCaption = ""
        printFinished = false

        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            extrusionProgress = 0
            developmentProgress = 0
        }

        DispatchQueue.main.async {
            extrusionStartDate = Date()
            feedbackGenerator.prepare()
            mechanicalAudio.playFromStart()

            withAnimation(.linear(duration: extrusionDuration)) {
                extrusionProgress = 1
            }

            withAnimation(.easeInOut(duration: developmentDuration).delay(developmentDelay)) {
                developmentProgress = 1
            }
        }

        completionTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(extrusionDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                feedbackGenerator.notificationOccurred(.success)
                printFinished = true
                startCaptionAnimationIfNeeded()
            }
        }
    }

    private func jitterOffset(at date: Date) -> CGSize {
        guard extrusionProgress < 0.995 else { return .zero }
        let t = date.timeIntervalSince(extrusionStartDate)
        let x = sin(t * 118) * 0.72 + sin(t * 171 + 0.6) * 0.34
        let y = sin(t * 133 + 1.1) * 0.42
        return CGSize(width: x, height: y)
    }

    private func startCaptionAnimationIfNeeded() {
        guard printFinished else { return }

        let normalizedCaption = normalizeCaption(captionText)
        guard !normalizedCaption.isEmpty else {
            displayedCaption = ""
            return
        }

        guard displayedCaption != normalizedCaption else { return }

        captionTask?.cancel()
        displayedCaption = ""

        captionTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            var writing = ""
            for character in normalizedCaption {
                guard !Task.isCancelled else { return }
                writing.append(character)
                await MainActor.run {
                    displayedCaption = writing
                }
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
        }
    }

    private func normalizeCaption(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(10))
    }
}

private final class PolaroidMechanicalAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private let resourceName = "Record_2026-02-18-13-42-20_a2db1b9502c98f25523e43284b79cce6_polaroid_clean_5to11_fxonly"
    private var player: AVAudioPlayer?

    func preload() {
        guard player == nil else { return }
        guard let audioURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            print("⚠️ Polaroid mechanical audio resource missing: \(resourceName).mp3")
            return
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: audioURL)
            newPlayer.delegate = self
            newPlayer.numberOfLoops = 0
            newPlayer.prepareToPlay()
            player = newPlayer
        } catch {
            print("⚠️ Failed to preload polaroid mechanical audio: \(error)")
        }
    }

    func playFromStart() {
        preload()
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    func teardown() {
        player?.stop()
        player?.delegate = nil
        player = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error {
            print("⚠️ Polaroid mechanical audio decode error: \(error)")
        }
    }
}

struct PolaroidPhotoPageView: View {
    let image: UIImage
    var captionText: String = ""
    var storyText: String = ""
    var paperStyle: PolaroidPaperStyle = .defaultStyle
    @Binding var inputText: String
    @Binding var selectedPhotoItem: PhotosPickerItem?
    var isPhotoProcessing: Bool
    var isResponding: Bool
    var onSend: () -> Void
    var onInputBarTopChanged: ((CGFloat) -> Void)? = nil
    var onClose: () -> Void
    @State private var inputBarTopY: CGFloat = .infinity
    @State private var topControlsBottomY: CGFloat = 0
    @State private var isSavingToLibrary = false
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var saveFeedback = UINotificationFeedbackGenerator()
    @State private var keyboardBottomInset: CGFloat = 0

    private var normalizedCaption: String {
        captionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDownloadEnabled: Bool {
        !normalizedCaption.isEmpty
    }

    var body: some View {
        let hasLayoutBounds = inputBarTopY.isFinite && topControlsBottomY > 0

        ZStack {
            Color.black
                .ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if keyboardBottomInset > 0 {
                        dismissKeyboard()
                    }
                }

            if hasLayoutBounds {
                PolaroidPrintStageView(
                    image: image,
                    captionText: captionText,
                    backStoryText: storyText,
                    paperStyle: paperStyle,
                    horizontalPadding: 10,
                    topLimitY: topControlsBottomY,
                    bottomLimitY: inputBarTopY
                )
                .padding(.horizontal, 0)
            }

            ConversationInputBar(
                text: $inputText,
                selectedPhotoItem: $selectedPhotoItem,
                isPhotoLoading: isPhotoProcessing,
                isSendDisabled: isResponding,
                isKeyboardActive: keyboardBottomInset > 0,
                measurementSpace: .named("polaroidPage"),
                onTopChanged: { top in
                    inputBarTopY = top
                    onInputBarTopChanged?(top)
                }
            ) {
                onSend()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, keyboardBottomInset > 0 ? (keyboardBottomInset + 5) : 10)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .zIndex(20)

            VStack {
                HStack {
                    Button {
                        onClose()
                    } label: {
                        LiquidGlassCircleIcon(
                            systemName: "xmark",
                            size: 42,
                            iconSize: 14
                        )
                    }
                    .buttonStyle(LiquidGlassCircleButtonStyle())

                    Spacer()

                    Button {
                        saveCurrentPolaroidToLibrary()
                    } label: {
                        LiquidGlassCircleIcon(
                            systemName: "square.and.arrow.down",
                            size: 42,
                            iconSize: 16,
                            isLoading: isSavingToLibrary,
                            isActive: isDownloadEnabled && !isSavingToLibrary
                        )
                    }
                    .buttonStyle(LiquidGlassCircleButtonStyle())
                    .accessibilityLabel("保存")
                    .disabled(!isDownloadEnabled || isSavingToLibrary)
                    .opacity(isDownloadEnabled ? 1 : 0.48)
                    .saturation(isDownloadEnabled ? 1 : 0)
                }
                .padding(.leading, 20)
                .padding(.trailing, 20)
                .padding(.top, 16)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TopControlsBottomPreferenceKey.self,
                            value: proxy.frame(in: .named("polaroidPage")).maxY
                        )
                    }
                )
                Spacer()
            }
            .zIndex(30)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .coordinateSpace(name: "polaroidPage")
        .onPreferenceChange(TopControlsBottomPreferenceKey.self) { newValue in
            topControlsBottomY = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardVisibility(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardBottomInset = 0
        }
        .onAppear {
            saveFeedback.prepare()
        }
        .alert("保存结果", isPresented: $showSaveAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(saveAlertMessage)
        }
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

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func saveCurrentPolaroidToLibrary() {
        guard isDownloadEnabled, !isSavingToLibrary else { return }
        guard let renderBundle = renderLivePhotoBundle() else {
            presentSaveResult(success: false, message: "生成拍立得内容失败，请重试")
            return
        }

        isSavingToLibrary = true
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            exportAndSaveLivePhoto(renderBundle: renderBundle)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { authStatus in
                DispatchQueue.main.async {
                    if authStatus == .authorized || authStatus == .limited {
                        exportAndSaveLivePhoto(renderBundle: renderBundle)
                    } else {
                        isSavingToLibrary = false
                        presentSaveResult(success: false, message: "未授予照片权限，无法保存")
                    }
                }
            }
        default:
            isSavingToLibrary = false
            presentSaveResult(success: false, message: "请在系统设置中开启照片权限后重试")
        }
    }

    private func exportAndSaveLivePhoto(renderBundle: LivePhotoRenderBundle) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let resources = try createLivePhotoResources(renderBundle: renderBundle)
                DispatchQueue.main.async {
                    saveLivePhotoResourcesToLibrary(resources)
                }
            } catch {
                DispatchQueue.main.async {
                    isSavingToLibrary = false
                    let message = (error as? LocalizedError)?.errorDescription ?? "生成实况照片失败，请稍后重试"
                    presentSaveResult(success: false, message: message)
                }
            }
        }
    }

    private func saveLivePhotoResourcesToLibrary(_ resources: LivePhotoExportResources) {
        PHPhotoLibrary.shared().performChanges({
            let creationRequest = PHAssetCreationRequest.forAsset()

            let photoOptions = PHAssetResourceCreationOptions()
            photoOptions.shouldMoveFile = false
            creationRequest.addResource(with: .photo, fileURL: resources.photoURL, options: photoOptions)

            let pairedVideoOptions = PHAssetResourceCreationOptions()
            pairedVideoOptions.shouldMoveFile = false
            creationRequest.addResource(with: .pairedVideo, fileURL: resources.pairedVideoURL, options: pairedVideoOptions)
        }) { success, error in
            DispatchQueue.main.async {
                cleanupLivePhotoResources(resources)
                isSavingToLibrary = false
                if success {
                    presentSaveResult(success: true, message: "已保存为实况照片到系统相册")
                } else {
                    let message = error?.localizedDescription ?? "保存失败，请稍后重试"
                    presentSaveResult(success: false, message: message)
                }
            }
        }
    }

    private func presentSaveResult(success: Bool, message: String) {
        saveAlertMessage = message
        showSaveAlert = true
        saveFeedback.notificationOccurred(success ? .success : .error)
        saveFeedback.prepare()
    }

    private func renderLivePhotoBundle() -> LivePhotoRenderBundle? {
        PolaroidHandwritingFont.registerIfNeeded()
        let metrics = polaroidExportMetrics()
        guard let frontCardImage = renderPolaroidFrontCardSnapshot(metrics: metrics),
              let backCardImage = renderPolaroidBackCardSnapshot(
                metrics: metrics,
                storyText: ""
              ),
              let frontCanvasImage = composePolaroidCanvas(cardImage: frontCardImage, metrics: metrics),
              let frontCardCG = normalizedCGImage(from: frontCardImage),
              let frontCanvasCG = normalizedCGImage(from: frontCanvasImage) else {
            return nil
        }

        let insetX = max(0, (frontCanvasCG.width - frontCardCG.width) / 2)
        let insetY = max(0, (frontCanvasCG.height - frontCardCG.height) / 2)

        return LivePhotoRenderBundle(
            frontCardImage: frontCardImage,
            backCardImage: backCardImage,
            frontCanvasImage: frontCanvasImage,
            canvasSizeInPixels: CGSize(width: frontCanvasCG.width, height: frontCanvasCG.height),
            cardInsetX: insetX,
            cardInsetY: insetY,
            paperBackgroundColor: metrics.paperUIColor
        )
    }

    private func renderPolaroidFrontCardSnapshot(metrics: PolaroidExportMetrics) -> UIImage? {
        let snapshotView = DynamicPolaroidView(
            image: image,
            cardWidth: metrics.cardWidth,
            edgePadding: metrics.edgePadding,
            developmentProgress: 1,
            captionText: normalizedCaption,
            paperStyle: paperStyle,
            livePlaybackEnabled: false,
            includeDropShadow: false
        )
        .frame(width: metrics.cardWidth, height: metrics.cardHeight)

        return renderExportImage(
            content: snapshotView,
            size: CGSize(width: metrics.cardWidth, height: metrics.cardHeight)
        )
    }

    private func renderPolaroidBackCardSnapshot(
        metrics: PolaroidExportMetrics,
        storyText: String
    ) -> UIImage? {
        let snapshotView = PolaroidBackFaceView(
            cardWidth: metrics.cardWidth,
            cardHeight: metrics.cardHeight,
            storyText: storyText,
            paperStyle: paperStyle
        )
        .frame(width: metrics.cardWidth, height: metrics.cardHeight)

        return renderExportImage(
            content: snapshotView,
            size: CGSize(width: metrics.cardWidth, height: metrics.cardHeight)
        )
    }

    private func composePolaroidCanvas(cardImage: UIImage, metrics: PolaroidExportMetrics) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = max(cardImage.scale, 1)
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: metrics.canvasSize, format: format)
        return renderer.image { context in
            metrics.paperUIColor.setFill()
            context.fill(CGRect(origin: .zero, size: metrics.canvasSize))
            cardImage.draw(
                in: CGRect(
                    x: metrics.canvasInset,
                    y: metrics.canvasInset,
                    width: metrics.cardWidth,
                    height: metrics.cardHeight
                )
            )
        }
    }

    private func polaroidExportMetrics() -> PolaroidExportMetrics {
        let exportCardWidth: CGFloat = 1080
        let baseCardWidth: CGFloat = 760
        let baseEdgePadding: CGFloat = 12
        let edgePadding: CGFloat = max(
            12,
            (exportCardWidth * (baseEdgePadding / baseCardWidth)).rounded(.toNearestOrAwayFromZero)
        )
        let canvasInset: CGFloat = max(26, (edgePadding * 2).rounded(.toNearestOrAwayFromZero))
        let imageAspectRatio = max(image.size.width, 1) / max(image.size.height, 1)
        let imageFrameWidth = max(1, exportCardWidth - edgePadding * 2)
        let imageFrameHeight = imageFrameWidth / imageAspectRatio
        let cardHeight = edgePadding + imageFrameHeight + edgePadding * 4

        return PolaroidExportMetrics(
            cardWidth: exportCardWidth,
            cardHeight: cardHeight,
            edgePadding: edgePadding,
            canvasInset: canvasInset,
            canvasSize: CGSize(
                width: exportCardWidth + canvasInset * 2,
                height: cardHeight + canvasInset * 2
            ),
            paperUIColor: paperStyle.canvasBackgroundUIColor
        )
    }

    private func renderExportImage<V: View>(content: V, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(2, UIScreen.main.scale)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private func createLivePhotoResources(
        renderBundle: LivePhotoRenderBundle
    ) throws -> LivePhotoExportResources {
        let identifier = UUID().uuidString
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gaya_livephoto_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let photoURL = exportDirectory.appendingPathComponent("photo.jpg")
        let pairedVideoURL = exportDirectory.appendingPathComponent("paired.mov")

        try writeLivePhotoJPEG(
            image: renderBundle.frontCanvasImage,
            outputURL: photoURL,
            assetIdentifier: identifier
        )
        try writeLivePhotoVideo(
            frontCardSnapshot: renderBundle.frontCardImage,
            backCardSnapshot: renderBundle.backCardImage,
            canvasSizeInPixels: renderBundle.canvasSizeInPixels,
            cardInsetX: renderBundle.cardInsetX,
            cardInsetY: renderBundle.cardInsetY,
            paperBackgroundColor: renderBundle.paperBackgroundColor,
            outputURL: pairedVideoURL,
            assetIdentifier: identifier
        )

        return LivePhotoExportResources(
            directoryURL: exportDirectory,
            photoURL: photoURL,
            pairedVideoURL: pairedVideoURL
        )
    }

    private func writeLivePhotoJPEG(
        image: UIImage,
        outputURL: URL,
        assetIdentifier: String
    ) throws {
        guard let cgImage = image.cgImage else {
            throw LivePhotoExportError.encodingFailed("无法读取导出图片")
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw LivePhotoExportError.encodingFailed("无法创建实况主图文件")
        }

        let properties: [CFString: Any] = [
            // Keep border gradients smooth after export; lower JPEG quality amplifies banding.
            kCGImageDestinationLossyCompressionQuality: 1.0,
            kCGImagePropertyMakerAppleDictionary: ["17": assetIdentifier]
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoExportError.encodingFailed("写入实况主图失败")
        }
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = max(image.scale, 1)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }

    private func writeLivePhotoVideo(
        frontCardSnapshot: UIImage,
        backCardSnapshot: UIImage,
        canvasSizeInPixels: CGSize,
        cardInsetX: Int,
        cardInsetY: Int,
        paperBackgroundColor: UIColor,
        outputURL: URL,
        assetIdentifier: String
    ) throws {
        guard let frontCG = normalizedCGImage(from: frontCardSnapshot),
              let backCG = normalizedCGImage(from: backCardSnapshot) else {
            throw LivePhotoExportError.encodingFailed("无法读取实况视频帧")
        }

        let canvasWidth = max(1, Int(round(canvasSizeInPixels.width)))
        let canvasHeight = max(1, Int(round(canvasSizeInPixels.height)))
        let fps: Int32 = 30
        let duration: Double = 3.0
        let totalFrames = max(1, Int(duration * Double(fps)))

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: canvasWidth,
                AVVideoHeightKey: canvasHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 12_000_000
                ]
            ]
        )
        videoInput.expectsMediaDataInRealTime = false

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: canvasWidth,
                kCVPixelBufferHeightKey as String: canvasHeight,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )

        guard writer.canAdd(videoInput) else {
            throw LivePhotoExportError.encodingFailed("无法创建实况视频轨道")
        }
        writer.add(videoInput)

        let metadataSpecifications: [[String: Any]] = [[
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: "com.apple.metadata.datatype.int8"
        ]]
        var metadataFormatDescription: CMFormatDescription?
        let metadataStatus = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: metadataSpecifications as CFArray,
            formatDescriptionOut: &metadataFormatDescription
        )
        guard metadataStatus == noErr, let metadataFormatDescription else {
            throw LivePhotoExportError.encodingFailed("无法创建实况元数据格式描述")
        }

        let metadataInput = AVAssetWriterInput(
            mediaType: .metadata,
            outputSettings: nil,
            sourceFormatHint: metadataFormatDescription
        )
        let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        guard writer.canAdd(metadataInput) else {
            throw LivePhotoExportError.encodingFailed("无法创建实况元数据轨道")
        }
        writer.add(metadataInput)

        let identifierMetadata = AVMutableMetadataItem()
        identifierMetadata.keySpace = .quickTimeMetadata
        identifierMetadata.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
        identifierMetadata.value = assetIdentifier as NSString
        writer.metadata = [identifierMetadata]

        guard writer.startWriting() else {
            throw LivePhotoExportError.encodingFailed(writer.error?.localizedDescription ?? "无法开始写入实况视频")
        }
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: fps)
        let frameCountDenominator = Double(max(totalFrames - 1, 1))

        for frameIndex in 0..<totalFrames {
            while !videoInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }

            let progress = Double(frameIndex) / frameCountDenominator
            let angle = liveFlipAngle(progress: progress)
            let presentationTime = CMTime(value: Int64(frameIndex), timescale: fps)

            guard let pixelBuffer = makeLiveVideoPixelBuffer(
                angle: angle,
                frontCardCG: frontCG,
                backCardCG: backCG,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
                cardInsetX: cardInsetX,
                cardInsetY: cardInsetY,
                paperBackgroundColor: paperBackgroundColor,
                pixelBufferPool: pixelBufferAdaptor.pixelBufferPool
            ) else {
                throw LivePhotoExportError.encodingFailed("无法生成实况视频帧")
            }

            guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw LivePhotoExportError.encodingFailed("写入实况视频帧失败")
            }
        }

        let stillImageTimeMetadata = AVMutableMetadataItem()
        stillImageTimeMetadata.keySpace = .quickTimeMetadata
        stillImageTimeMetadata.key = "com.apple.quicktime.still-image-time" as NSString
        stillImageTimeMetadata.value = 0 as NSNumber
        stillImageTimeMetadata.dataType = "com.apple.metadata.datatype.int8"

        let stillFrameStart = CMTime(value: 0, timescale: fps)
        let stillFrameGroup = AVTimedMetadataGroup(
            items: [stillImageTimeMetadata],
            timeRange: CMTimeRange(start: stillFrameStart, duration: frameDuration)
        )
        guard metadataAdaptor.append(stillFrameGroup) else {
            throw LivePhotoExportError.encodingFailed("写入实况元数据失败")
        }

        videoInput.markAsFinished()
        metadataInput.markAsFinished()

        let finishSemaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            finishSemaphore.signal()
        }
        finishSemaphore.wait()

        guard writer.status == .completed else {
            throw LivePhotoExportError.encodingFailed(writer.error?.localizedDescription ?? "实况视频写入失败")
        }
    }

    private func makeLiveVideoPixelBuffer(
        angle: Double,
        frontCardCG: CGImage,
        backCardCG: CGImage,
        canvasWidth: Int,
        canvasHeight: Int,
        cardInsetX: Int,
        cardInsetY: Int,
        paperBackgroundColor: UIColor,
        pixelBufferPool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {
        guard let pixelBufferPool else { return nil }

        var pixelBufferOut: CVPixelBuffer?
        let createStatus = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBufferOut)
        guard createStatus == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let context = CGContext(
            data: baseAddress,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        context.setFillColor(paperBackgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.interpolationQuality = .high

        let phaseAngle = angle <= 90 ? angle : 180 - angle
        let xScale = max(0.025, CGFloat(abs(cos(phaseAngle * .pi / 180))))
        let cardWidth = CGFloat(frontCardCG.width)
        let cardHeight = CGFloat(frontCardCG.height)
        let drawWidth = cardWidth * xScale
        let drawRect = CGRect(
            x: CGFloat(cardInsetX) + (cardWidth - drawWidth) * 0.5,
            y: CGFloat(cardInsetY),
            width: drawWidth,
            height: cardHeight
        )

        let transitionBand: Double = 7
        let frontOpacity: CGFloat
        if angle <= 90 - transitionBand {
            frontOpacity = 1
        } else if angle >= 90 + transitionBand {
            frontOpacity = 0
        } else {
            let t = (90 + transitionBand - angle) / (transitionBand * 2)
            frontOpacity = CGFloat(min(max(t, 0), 1))
        }
        let backOpacity = CGFloat(1) - frontOpacity

        if frontOpacity > 0.001 {
            context.saveGState()
            context.setAlpha(frontOpacity)
            context.draw(frontCardCG, in: drawRect)
            context.restoreGState()
        }

        if backOpacity > 0.001 {
            context.saveGState()
            context.setAlpha(backOpacity)
            context.draw(backCardCG, in: drawRect)
            context.restoreGState()
        }

        let compressionShade = (1 - xScale) * 0.18
        if compressionShade > 0.001 {
            context.setFillColor(UIColor.black.withAlphaComponent(compressionShade).cgColor)
            context.fill(drawRect)
        }

        let edgeGlow = min(0.16, (1 - xScale) * 0.34)
        if edgeGlow > 0.001 {
            let edgeRect = CGRect(
                x: drawRect.midX - 0.7,
                y: CGFloat(cardInsetY),
                width: 1.4,
                height: cardHeight
            )
            context.setFillColor(UIColor.white.withAlphaComponent(edgeGlow).cgColor)
            context.fill(edgeRect)
        }

        return pixelBuffer
    }

    private func liveFlipAngle(progress: Double) -> Double {
        let normalized = min(max(progress, 0), 1)
        let flipOutEnd = 1.0 / 3.0
        let holdEnd = 2.0 / 3.0
        if normalized < flipOutEnd {
            return 180 * smoothStep(normalized / flipOutEnd)
        }
        if normalized < holdEnd {
            return 180
        }
        return 180 * (1 - smoothStep((normalized - holdEnd) / (1 - holdEnd)))
    }

    private func smoothStep(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func cleanupLivePhotoResources(_ resources: LivePhotoExportResources) {
        try? FileManager.default.removeItem(at: resources.directoryURL)
    }

    private struct PolaroidExportMetrics {
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let edgePadding: CGFloat
        let canvasInset: CGFloat
        let canvasSize: CGSize
        let paperUIColor: UIColor
    }

    private struct LivePhotoRenderBundle {
        let frontCardImage: UIImage
        let backCardImage: UIImage
        let frontCanvasImage: UIImage
        let canvasSizeInPixels: CGSize
        let cardInsetX: Int
        let cardInsetY: Int
        let paperBackgroundColor: UIColor
    }

    private struct LivePhotoExportResources {
        let directoryURL: URL
        let photoURL: URL
        let pairedVideoURL: URL
    }

    private enum LivePhotoExportError: LocalizedError {
        case encodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .encodingFailed(let message):
                return message
            }
        }
    }
}

private enum PolaroidHandwritingFont {
    static let fontName = "MaShanZheng-Regular"
    private static let fontFileName = "MaShanZheng-Regular"
    private static var didRegister = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        guard let fontURL = Bundle.main.url(forResource: fontFileName, withExtension: "ttf") else {
            print("⚠️ Handwriting font file not found, fallback to system font")
            return
        }

        var registrationError: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError)
        if !success, let error = registrationError?.takeRetainedValue() {
            print("⚠️ Handwriting font register failed: \(error)")
        }
    }
}
