import SwiftUI
import MetalKit
import UIKit

struct ParticleView: UIViewRepresentable {
    var audioLevel: Float = 0.0
    var seedState: SeedState = .idle
    var isAISpeaking: Bool = false      // AI 是否正在说话
    var aiAudioLevel: Float = 0.0       // AI 音频等级
    var photoImage: UIImage?
    var photoVersion: Int = 0
    @ObservedObject var photoSettings: PhotoParticleSettings
    var photoInteraction: PhotoInteractionState
    var photoZoom: CGFloat
    var photoActive: Bool

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.backgroundColor = .clear
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let renderer = ParticleRenderer(metalView: mtkView)
        mtkView.delegate = renderer
        context.coordinator.renderer = renderer

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.audioIntensity = audioLevel
        context.coordinator.renderer?.seedState = seedState
        context.coordinator.renderer?.isAISpeaking = isAISpeaking
        context.coordinator.renderer?.aiAudioIntensity = aiAudioLevel
        context.coordinator.renderer?.photoSettings = photoSettings.snapshot
        context.coordinator.renderer?.photoInteraction = photoInteraction
        context.coordinator.renderer?.photoZoom = Float(photoZoom)
        context.coordinator.renderer?.photoSessionActive = photoActive

        if context.coordinator.lastPhotoActive != photoActive {
            context.coordinator.lastPhotoActive = photoActive
            if !photoActive {
                context.coordinator.renderer?.resetToSeedIfNeeded()
                context.coordinator.lastPhotoVersion = -1
            }
        }

        if photoActive, context.coordinator.lastPhotoVersion != photoVersion {
            context.coordinator.lastPhotoVersion = photoVersion
            if let photoImage {
                context.coordinator.renderer?.updatePhoto(image: photoImage)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var renderer: ParticleRenderer?
        var lastPhotoVersion: Int = 0
        var lastPhotoActive: Bool = false
    }
}
