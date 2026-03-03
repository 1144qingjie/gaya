import MetalKit
import simd
import UIKit
import Vision

struct Particle {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var size: Float
    var randomValue: Float
    var color: SIMD4<Float>
}

struct Uniforms {
    var time: Float
    var rotationY: Float
    var rotationZ: Float
    var audioIntensity: Float    // 平滑后的音频强度
    var audioBands: SIMD3<Float> // 可选三频段包络（low/mid/high）
    var expansion: Float
    var seedMotionStrength: Float
    var aspectRatio: Float
    var scale: Float
    var screenScale: Float       // 屏幕缩放因子（用于适配不同分辨率）
    var photoMode: Float         // 0 = seed, 1 = photo
    var photoDispersion: Float
    var photoParticleSize: Float
    var photoContrast: Float
    var photoFlowSpeed: Float
    var photoFlowAmplitude: Float
    var photoDepthStrength: Float
    var photoMouseRadius: Float
    var photoMousePosition: SIMD2<Float>
    var photoColorShiftSpeed: Float
    var photoAudioDance: Float
    var photoDanceStrength: Float
    var photoDepthWave: Float
    var photoZoom: Float
    var photoStructureRetention: Float
    var photoMotionStrength: Float
    var photoPadding: SIMD2<Float>
}

struct PhotoParticleParams {
    var width: UInt32
    var height: UInt32
    var particleCount: UInt32
    var center: SIMD2<Float>
    var maxRadius: Float
    var focusRadius: Float
    var edgeFalloff: Float
    var targetRadius: Float
    var depthScale: Float
    var maskThreshold: Float
    var centerSize: Float
    var edgeSize: Float
    var boundsMin: SIMD2<Float>
    var boundsMax: SIMD2<Float>
    var cornerRadius: Float
    var cornerSoftness: Float
    var maskReliability: Float
    var seed: UInt32
    var padding: UInt32
}

private struct PhotoMaskMetrics {
    var center: SIMD2<Float>
    var maxRadius: Float
    var focusRadius: Float
    var coverage: Float
    var boundsMin: SIMD2<Float>
    var boundsMax: SIMD2<Float>
}

enum ParticleRenderMode {
    case seed
    case photo
}

class ParticleRenderer: NSObject, MTKViewDelegate {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var computePipelineState: MTLComputePipelineState!
    var textureLoader: MTKTextureLoader!
    var particles: [Particle] = []
    var particleBuffer: MTLBuffer!
    var time: Float = 0
    var rotationY: Float = 0
    var rotationZ: Float = 0
    var audioIntensity: Float = 0.0
    var smoothedAudioIntensity: Float = 0.0
    var expansion: Float = 0.0
    var smoothedExpansion: Float = 0.0
    var seedState: SeedState = .idle
    var viewportSize: CGSize = .zero
    var renderMode: ParticleRenderMode = .seed
    var currentParticleCount: Int = 0
    var photoSettings: PhotoParticleSettingsValue = .default
    var photoInteraction: PhotoInteractionState = .inactive
    var photoZoom: Float = 1.0
    var photoSessionActive: Bool = false
    private var photoUpdateID: UInt64 = 0
    private let photoQueue = DispatchQueue(label: "gaya.photo-particles", qos: .userInitiated)
    
    // AI 语音输出相关
    var isAISpeaking: Bool = false
    var aiAudioIntensity: Float = 0.0
    private var smoothedAIIntensity: Float = 0.0
    private var smoothedAudioLow: Float = 0.0
    private var smoothedAudioMid: Float = 0.0
    private var smoothedAudioHigh: Float = 0.0

    let seedParticleCount = 4000  // 与参考代码一致
    private(set) var photoParticleCount: Int = 250000
    private var photoColorTexture: MTLTexture?
    private var photoMaskTexture: MTLTexture?
    private var photoDensityTexture: MTLTexture?
    private var photoEdgeTexture: MTLTexture?

    init(metalView: MTKView) {
        super.init()

        guard let device = metalView.device else {
            fatalError("Metal is not supported on this device")
        }

        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.textureLoader = MTKTextureLoader(device: device)
        self.photoParticleCount = Self.recommendedPhotoParticleCount()

        setupPipeline(metalView: metalView)
        setupComputePipeline()
        setupParticles()
    }

    func setupPipeline(metalView: MTKView) {
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat

        // 加法混合（与参考代码 AdditiveBlending 一致）
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }

    func setupComputePipeline() {
        let library = device.makeDefaultLibrary()
        guard let computeFunction = library?.makeFunction(name: "photoParticleKernel") else {
            fatalError("Missing photoParticleKernel function")
        }
        do {
            computePipelineState = try device.makeComputePipelineState(function: computeFunction)
        } catch {
            fatalError("Failed to create compute pipeline state: \(error)")
        }
    }

    private static func recommendedPhotoParticleCount() -> Int {
        let memoryGB = Float(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        var tier = 250000

        if memoryGB <= 3.2 {
            tier = 120000
        } else if memoryGB <= 5.8 {
            tier = 180000
        }

        let processInfo = ProcessInfo.processInfo
        if processInfo.isLowPowerModeEnabled {
            tier = tier >= 250000 ? 180000 : 120000
        }

        if processInfo.thermalState == .serious || processInfo.thermalState == .critical {
            tier = 120000
        }

        return tier
    }

    private func applyAttackRelease(current: Float, target: Float, attack: Float, release: Float) -> Float {
        let alpha = target > current ? attack : release
        return current + (target - current) * alpha
    }

    private func photoViewportAspectForLayout() -> Float {
        if viewportSize.width > 1.0, viewportSize.height > 1.0 {
            return Float(viewportSize.width / viewportSize.height)
        }
        let screenBounds = UIScreen.main.bounds
        return Float(screenBounds.width / max(screenBounds.height, 1.0))
    }

    func setupParticles() {
        particles = []
        
        // 严格复刻参考代码的粒子分布
        // 但调整半径范围，使其适合 Metal 的 NDC 坐标系 (-1 到 1)
        // 参考代码核心在 r=0.5~1.0，光晕在 r=1.0~2.5
        // Metal 屏幕空间：核心 r=0.1~0.2，光晕 r=0.2~0.5
        
        for _ in 0..<seedParticleCount {
            let theta = Float.random(in: 0...(2 * .pi))
            let phi = acos((Float.random(in: 0...1) * 2) - 1)

            let r: Float
            let size: Float
            
            if Float.random(in: 0...1) > 0.3 {
                // 70% 紧密核心
                let baseR = 0.1 + pow(Float.random(in: 0...1), 2) * 0.1
                r = baseR
                size = Float.random(in: 0.4...1.0)
            } else {
                // 30% 稀疏光晕
                let baseR = 0.2 + pow(Float.random(in: 0...1), 3) * 0.3
                r = baseR
                size = Float.random(in: 0.6...2.0)  // 光晕粒子更大
            }

            let x = r * sin(phi) * cos(theta)
            let y = r * sin(phi) * sin(theta)
            let z = r * cos(phi)

            let randomValue = Float.random(in: 0...1)

            let particle = Particle(
                position: SIMD3<Float>(x, y, z),
                velocity: SIMD3<Float>(0, 0, 0),
                size: size,
                randomValue: randomValue,
                color: SIMD4<Float>(1, 1, 1, 1)
            )
            particles.append(particle)
        }

        let bufferSize = particles.count * MemoryLayout<Particle>.stride
        particleBuffer = device.makeBuffer(bytes: particles, length: bufferSize, options: [])
        currentParticleCount = particles.count
        renderMode = .seed
    }

    func updateParticles() {
        time += 0.016  // ~60fps

        // ========== 音频强度平滑（Fast Attack, Slow Release）==========
        let isPhoto = renderMode == .photo
        let audioDanceEnabled = isPhoto && photoSettings.audioDance
        let speakingIntensity: Float = isAISpeaking ? aiAudioIntensity : 0.0
        let targetIntensity: Float
        if isPhoto {
            targetIntensity = audioDanceEnabled ? speakingIntensity : 0.0
        } else {
            targetIntensity = speakingIntensity
        }

        smoothedAIIntensity = applyAttackRelease(
            current: smoothedAIIntensity,
            target: targetIntensity,
            attack: 0.24,
            release: 0.06
        )

        let transient = max(0.0, targetIntensity - smoothedAIIntensity)
        smoothedAudioLow = applyAttackRelease(current: smoothedAudioLow, target: targetIntensity, attack: 0.12, release: 0.03)
        smoothedAudioMid = applyAttackRelease(current: smoothedAudioMid, target: targetIntensity, attack: 0.2, release: 0.055)
        smoothedAudioHigh = applyAttackRelease(
            current: smoothedAudioHigh,
            target: min(1.0, targetIntensity + transient * 0.55),
            attack: 0.34,
            release: 0.12
        )

        // ========== 扩张状态 ==========
        let targetExpansion: Float = seedState == .idle ? 0.0 : 0.3
        smoothedExpansion += (targetExpansion - smoothedExpansion) * 0.02
        expansion = smoothedExpansion

        // ========== 旋转 ==========
        let baseRotSpeed: Float = seedState == .idle ? 0.006 : 0.05
        let rotSpeed: Float = baseRotSpeed + (smoothedAIIntensity * 0.2)
        rotationY += rotSpeed * 0.01
        let zWaveAmplitude: Float = seedState == .idle ? 0.015 : 0.1
        rotationZ = sin(time * 0.2) * zWaveAmplitude
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }

    func draw(in view: MTKView) {
        updateParticles()

        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        if viewportSize == .zero {
            viewportSize = view.drawableSize
        }
        
        // 使用 height / width 作为校正因子，方便在着色器端只对 X 方向做统一缩放，
        // 保证不同屏幕比例下的粒子球都保持圆形。
        let aspectRatio = Float(viewportSize.height / viewportSize.width)
        
        // iOS 屏幕适配：
        // 在当前粒子分布（半径约 0.1~0.5）的前提下，
        // scale=1.0 时，视觉上中心粒子团直径约占屏幕宽度的一半，
        // 与你提供的“正常”截图一致。
        let scale: Float = 1.0
        
        // 屏幕像素密度因子（用于粒子大小）
        let screenScale = Float(UIScreen.main.scale)
        let isPhoto = renderMode == .photo
        let photoMode: Float = isPhoto ? 1.0 : 0.0

        let mappedDispersion: Float = isPhoto ? PhotoParticleScaling.dispersion(photoSettings.dispersion) : 0.0
        let mappedParticleSize: Float = isPhoto ? PhotoParticleScaling.particleSize(photoSettings.particleSize) : 1.0
        let mappedContrast: Float = isPhoto ? PhotoParticleScaling.contrast(photoSettings.contrast) : 1.0
        let mappedFlowSpeed: Float = isPhoto ? PhotoParticleScaling.flowSpeed(photoSettings.flowSpeed) : 0.0
        let mappedFlowAmplitude: Float = isPhoto ? PhotoParticleScaling.flowAmplitude(photoSettings.flowAmplitude) : 0.0
        let mappedDepthStrength: Float = isPhoto ? PhotoParticleScaling.depthStrength(photoSettings.depthStrength) : 0.0
        let mappedColorShiftSpeed: Float = isPhoto ? photoSettings.colorShiftSpeed : 0.0
        let mappedAudioDance: Float = (isPhoto && photoSettings.audioDance) ? 1.0 : 0.0
        let mappedDanceStrength: Float = isPhoto ? PhotoParticleScaling.danceStrength(photoSettings.danceStrength) : 0.0
        let mappedDepthWave: Float = isPhoto ? PhotoParticleScaling.depthWave(photoSettings.depthWave) : 0.0
        let mappedStructureRetention: Float = isPhoto ? PhotoParticleScaling.structureRetention(photoSettings.structureRetention) : 0.0
        let mappedMotionStrength: Float = isPhoto ? PhotoParticleScaling.motionStrength(photoSettings.motionStrength) : 0.0
        let seedMotionStrength: Float = seedState == .idle ? 0.06 : 1.0
        let audioBands = SIMD3<Float>(smoothedAudioLow, smoothedAudioMid, smoothedAudioHigh)

        var mousePosition = SIMD2<Float>(-2.0, -2.0)
        var mouseRadius: Float = 0.0
        if isPhoto, photoInteraction.isActive, let location = photoInteraction.location {
            mousePosition = PhotoParticleScaling.mousePositionNDC(
                location: location,
                viewportSize: viewportSize,
                screenScale: screenScale
            )
            mouseRadius = PhotoParticleScaling.mouseRadiusNDC(
                radiusPoints: photoSettings.mouseRadius,
                viewportSize: viewportSize,
                screenScale: screenScale
            )
        }

        var uniforms = Uniforms(
            time: time,
            rotationY: rotationY,
            rotationZ: rotationZ,
            audioIntensity: smoothedAIIntensity,
            audioBands: audioBands,
            expansion: expansion,
            seedMotionStrength: seedMotionStrength,
            aspectRatio: aspectRatio,
            scale: scale,
            screenScale: screenScale,
            photoMode: photoMode,
            photoDispersion: mappedDispersion,
            photoParticleSize: mappedParticleSize,
            photoContrast: mappedContrast,
            photoFlowSpeed: mappedFlowSpeed,
            photoFlowAmplitude: mappedFlowAmplitude,
            photoDepthStrength: mappedDepthStrength,
            photoMouseRadius: mouseRadius,
            photoMousePosition: mousePosition,
            photoColorShiftSpeed: mappedColorShiftSpeed,
            photoAudioDance: mappedAudioDance,
            photoDanceStrength: mappedDanceStrength,
            photoDepthWave: mappedDepthWave,
            photoZoom: isPhoto ? photoZoom : 1.0,
            photoStructureRetention: mappedStructureRetention,
            photoMotionStrength: mappedMotionStrength,
            photoPadding: SIMD2<Float>(0, 0)
        )

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: currentParticleCount)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Photo Particle Pipeline

    func updatePhoto(image: UIImage) {
        guard photoSessionActive else { return }
        photoUpdateID &+= 1
        let updateID = photoUpdateID
        let settingsSnapshot = photoSettings

        let cgImage: CGImage? = {
            if Thread.isMainThread {
                return normalizedCGImage(from: image)
            }
            var result: CGImage?
            DispatchQueue.main.sync {
                result = normalizedCGImage(from: image)
            }
            return result
        }()

        guard let cgImage else {
            print("🖼️ Photo normalize failed.")
            return
        }

        photoQueue.async { [weak self] in
            guard let self else { return }
            guard self.photoSessionActive, self.photoUpdateID == updateID else { return }

            let generatedMask = self.generateForegroundMask(from: cgImage)
            var usedFallbackMask = generatedMask == nil
            var maskBuffer = generatedMask ?? self.makeFullMask(width: cgImage.width, height: cgImage.height)
            guard let initialMask = maskBuffer else {
                print("🖼️ Mask generation failed.")
                return
            }

            var metrics = self.computeMaskMetrics(maskBuffer: initialMask)
            if metrics.coverage < 0.12, let fullMask = self.makeFullMask(width: cgImage.width, height: cgImage.height) {
                maskBuffer = fullMask
                metrics = self.computeMaskMetrics(maskBuffer: fullMask)
                usedFallbackMask = true
            }
            guard let maskBuffer = maskBuffer else {
                print("🖼️ Mask buffer missing after fallback.")
                return
            }

            guard let colorTexture = self.makeColorTexture(from: cgImage) else {
                print("🖼️ Color texture creation failed.")
                return
            }
            guard let maskTexture = self.makeMaskTexture(from: maskBuffer) else {
                print("🖼️ Mask texture creation failed.")
                return
            }
            guard let (densityTexture, edgeTexture) = self.makeFeatureTextures(
                from: maskBuffer,
                metrics: metrics
            ) else {
                print("🖼️ Density/edge texture creation failed.")
                return
            }

            let boundsWidth = max(0.02, metrics.boundsMax.x - metrics.boundsMin.x)
            let boundsHeight = max(0.02, metrics.boundsMax.y - metrics.boundsMin.y)
            let minBound = min(boundsWidth, boundsHeight)
            let roundness = PhotoParticleScaling.cornerRoundness(settingsSnapshot.cornerRoundness)
            let radiusRaw = minBound * (0.08 + roundness * 0.22)
            let maxRadius = max(0.001, minBound * 0.5 - 0.001)
            let cornerRadius = min(radiusRaw, maxRadius)
            let cornerSoftness = minBound * (0.014 + roundness * 0.055)
            let maskReliability: Float = {
                if usedFallbackMask { return 0.0 }
                let broadCoveragePenalty = (0.9 - metrics.coverage) / 0.45
                return min(max(broadCoveragePenalty, 0.35), 1.0)
            }()
            let viewportAspect = max(0.1, self.photoViewportAspectForLayout())
            let imageAspect = max(0.05, Float(cgImage.width) / Float(max(1, cgImage.height)))
            let layoutWidthLimit = 0.4 * max(1.0, viewportAspect)
            let layoutHeightLimit: Float = viewportAspect < 1.0
                ? (0.475 * imageAspect / viewportAspect)
                : (0.475 * imageAspect)
            let layoutBase = min(layoutWidthLimit, layoutHeightLimit)

            let params = PhotoParticleParams(
                width: UInt32(cgImage.width),
                height: UInt32(cgImage.height),
                particleCount: UInt32(self.photoParticleCount),
                center: metrics.center,
                maxRadius: metrics.maxRadius,
                focusRadius: metrics.focusRadius,
                edgeFalloff: 3.5,
                targetRadius: layoutBase,
                depthScale: 1.0,
                maskThreshold: 0.02,
                centerSize: 1.08,
                edgeSize: 2.45,
                boundsMin: metrics.boundsMin,
                boundsMax: metrics.boundsMax,
                cornerRadius: cornerRadius,
                cornerSoftness: cornerSoftness,
                maskReliability: maskReliability,
                seed: UInt32.random(in: 1...UInt32.max - 1),
                padding: 0
            )

            let bufferSize = self.photoParticleCount * MemoryLayout<Particle>.stride
            guard let newBuffer = self.device.makeBuffer(length: bufferSize, options: []) else {
                print("🖼️ Particle buffer creation failed.")
                return
            }

            self.encodePhotoParticles(
                colorTexture: colorTexture,
                maskTexture: maskTexture,
                densityTexture: densityTexture,
                edgeTexture: edgeTexture,
                particleBuffer: newBuffer,
                params: params
            )

            DispatchQueue.main.async {
                guard self.photoSessionActive, self.photoUpdateID == updateID else { return }
                self.photoColorTexture = colorTexture
                self.photoMaskTexture = maskTexture
                self.photoDensityTexture = densityTexture
                self.photoEdgeTexture = edgeTexture
                self.particleBuffer = newBuffer
                self.currentParticleCount = self.photoParticleCount
                self.renderMode = .photo
            }
        }
    }

    func resetToSeedIfNeeded() {
        guard renderMode == .photo else { return }
        photoColorTexture = nil
        photoMaskTexture = nil
        photoDensityTexture = nil
        photoEdgeTexture = nil
        setupParticles()
    }

    private func encodePhotoParticles(
        colorTexture: MTLTexture,
        maskTexture: MTLTexture,
        densityTexture: MTLTexture,
        edgeTexture: MTLTexture,
        particleBuffer: MTLBuffer,
        params: PhotoParticleParams
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        var params = params
        encoder.setComputePipelineState(computePipelineState)
        encoder.setTexture(colorTexture, index: 0)
        encoder.setTexture(maskTexture, index: 1)
        encoder.setTexture(densityTexture, index: 2)
        encoder.setTexture(edgeTexture, index: 3)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<PhotoParticleParams>.stride, index: 1)

        let threadWidth = computePipelineState.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: threadWidth, height: 1, depth: 1)
        let threads = MTLSize(width: Int(params.particleCount), height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func makeColorTexture(from cgImage: CGImage) -> MTLTexture? {
        if let texture = makeBGRA8Texture(from: cgImage) {
            return texture
        }
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft
        ]
        do {
            return try textureLoader.newTexture(cgImage: cgImage, options: options)
        } catch {
            print("🖼️ Texture loader error: \(error)")
        }
        if let rasterized = rasterizedCGImage(from: cgImage) {
            return try? textureLoader.newTexture(cgImage: rasterized, options: options)
        }
        return nil
    }

    private func makeMaskTexture(from maskBuffer: CVPixelBuffer) -> MTLTexture? {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return nil
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: baseAddress,
            bytesPerRow: bytesPerRow
        )

        return texture
    }

    private func makeFeatureTextures(
        from maskBuffer: CVPixelBuffer,
        metrics: PhotoMaskMetrics
    ) -> (MTLTexture, MTLTexture)? {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return nil
        }

        var maskValues = [Float](repeating: 0.0, count: width * height)
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                maskValues[y * width + x] = Float(row[x]) / 255.0
            }
        }

        let center = metrics.center
        let maxRadius = max(metrics.maxRadius, 0.001)
        let densityRatio: Float = 4.0  // center / edge target ratio
        let edgeDensityFloor = 1.0 / densityRatio

        var densityBytes = [UInt8](repeating: 0, count: width * height)
        var edgeBytes = [UInt8](repeating: 0, count: width * height)

        for y in 0..<height {
            let yMinus = max(0, y - 1)
            let yPlus = min(height - 1, y + 1)
            for x in 0..<width {
                let xMinus = max(0, x - 1)
                let xPlus = min(width - 1, x + 1)
                let idx = y * width + x

                let mask = maskValues[idx]
                if mask <= 0.001 { continue }

                let uv = SIMD2<Float>(
                    Float(x) / Float(max(1, width)),
                    Float(y) / Float(max(1, height))
                )
                let centered = uv - center
                let radial = min(1.0, simd_length(centered) / maxRadius)

                let centerBias = pow(max(0.0, 1.0 - radial), 0.82)
                var density = edgeDensityFloor + (1.0 - edgeDensityFloor) * centerBias
                density *= (0.42 + 0.58 * mask)
                density = min(max(density, 0.0), 1.0)

                let left = maskValues[y * width + xMinus]
                let right = maskValues[y * width + xPlus]
                let up = maskValues[yMinus * width + x]
                let down = maskValues[yPlus * width + x]
                let gradX = right - left
                let gradY = down - up
                let gradient = min(1.0, sqrt(gradX * gradX + gradY * gradY) * 2.4)
                let localMin = min(min(left, right), min(up, down))
                let boundary = min(max((mask - localMin) * 3.0, 0.0), 1.0)
                let edge = pow(min(max(gradient, boundary), 1.0), 0.72)
                let edgeDissolve = smoothstep(0.08, 0.88, edge)
                density *= (1.0 - edgeDissolve * 0.55)
                density = min(max(density, 0.0), 1.0)

                densityBytes[idx] = UInt8(min(max(Int(density * 255.0), 0), 255))
                edgeBytes[idx] = UInt8(min(max(Int(edge * 255.0), 0), 255))
            }
        }

        guard let densityTexture = makeR8Texture(width: width, height: height, bytes: densityBytes),
              let edgeTexture = makeR8Texture(width: width, height: height, bytes: edgeBytes) else {
            return nil
        }

        return (densityTexture, edgeTexture)
    }

    private func makeR8Texture(width: Int, height: Int, bytes: [UInt8]) -> MTLTexture? {
        guard bytes.count == width * height else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        bytes.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: baseAddress,
                    bytesPerRow: width
                )
            }
        }
        return texture
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / max(edge1 - edge0, 0.0001), 0.0), 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    private func generateForegroundMask(from cgImage: CGImage) -> CVPixelBuffer? {
        if #available(iOS 15.0, *) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first as? VNInstanceMaskObservation else {
                    return nil
                }
                return try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
            } catch {
                print("🖼️ Vision mask error: \(error)")
                return nil
            }
        }
        return nil
    }

    private func makeFullMask(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            attrs as CFDictionary,
            &buffer
        )
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            memset(baseAddress, 255, CVPixelBufferGetDataSize(buffer))
        }
        return buffer
    }

    private func computeMaskMetrics(maskBuffer: CVPixelBuffer) -> PhotoMaskMetrics {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return PhotoMaskMetrics(
                center: SIMD2<Float>(0.5, 0.5),
                maxRadius: 0.5,
                focusRadius: 0.2,
                coverage: 0.0,
                boundsMin: SIMD2<Float>(0.0, 0.0),
                boundsMax: SIMD2<Float>(1.0, 1.0)
            )
        }

        let threshold: UInt8 = 18
        var sum: Float = 0
        var sumX: Float = 0
        var sumY: Float = 0
        var count: Int = 0
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var hasForeground = false

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let value = row[x]
                if value > threshold {
                    let v = Float(value) / 255.0
                    sum += v
                    sumX += Float(x) * v
                    sumY += Float(y) * v
                    count += 1
                    if !hasForeground {
                        hasForeground = true
                        minX = x
                        maxX = x
                        minY = y
                        maxY = y
                    } else {
                        minX = min(minX, x)
                        maxX = max(maxX, x)
                        minY = min(minY, y)
                        maxY = max(maxY, y)
                    }
                }
            }
        }

        let centerX = sum > 0 ? sumX / sum : Float(width) * 0.5
        let centerY = sum > 0 ? sumY / sum : Float(height) * 0.5
        let center = SIMD2<Float>(centerX / Float(width), centerY / Float(height))

        var maxRadius: Float = 0.0
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let value = row[x]
                if value > threshold {
                    let nx = Float(x) / Float(width) - center.x
                    let ny = Float(y) / Float(height) - center.y
                    let dist = sqrt(nx * nx + ny * ny)
                    if dist > maxRadius {
                        maxRadius = dist
                    }
                }
            }
        }

        if maxRadius < 0.001 {
            maxRadius = 0.5
        }

        let focusRadius = max(0.08, min(maxRadius * 0.35, 0.45))
        let coverage = Float(count) / Float(max(1, width * height))
        let safeWidth = Float(max(1, width))
        let safeHeight = Float(max(1, height))
        let boundsMin: SIMD2<Float>
        let boundsMax: SIMD2<Float>
        if hasForeground {
            boundsMin = SIMD2<Float>(Float(minX) / safeWidth, Float(minY) / safeHeight)
            boundsMax = SIMD2<Float>(Float(maxX + 1) / safeWidth, Float(maxY + 1) / safeHeight)
        } else {
            boundsMin = SIMD2<Float>(0.0, 0.0)
            boundsMax = SIMD2<Float>(1.0, 1.0)
        }

        return PhotoMaskMetrics(
            center: center,
            maxRadius: maxRadius,
            focusRadius: focusRadius,
            coverage: coverage,
            boundsMin: boundsMin,
            boundsMax: boundsMax
        )
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        let downscaled = downscaledImage(image, maxDimension: 768)
        if downscaled.imageOrientation == .up, let cgImage = downscaled.cgImage {
            return cgImage
        }

        let renderer = UIGraphicsImageRenderer(size: downscaled.size)
        let normalized = renderer.image { _ in
            downscaled.draw(in: CGRect(origin: .zero, size: downscaled.size))
        }
        return normalized.cgImage
    }

    private func downscaledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func rasterizedCGImage(from cgImage: CGImage) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func makeBGRA8Texture(from cgImage: CGImage) -> MTLTexture? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height
        let rawData = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        defer { rawData.deallocate() }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: rawData,
            bytesPerRow: bytesPerRow
        )
        return texture
    }
}
