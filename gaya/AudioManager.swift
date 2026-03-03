import AVFoundation
import Combine

class AudioManager: NSObject, ObservableObject {
    @Published var audioLevel: Float = 0.0
    @Published var isRecording = false

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var smoothedLevel: Float = 0.0
    private var targetLevel: Float = 0.0

    override init() {
        super.init()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 使用可录可播的模式，避免系统音量被锁定
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetoothHFP])
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        print("🎤 AudioManager: Requesting microphone permission...")

        // 使用 iOS 17+ 的新 API
        if #available(iOS 17.0, *) {
            let currentStatus = AVAudioApplication.shared.recordPermission
            print("📊 Current permission status: \(currentStatus.rawValue)")
            
            switch currentStatus {
            case .granted:
                print("✅ Permission already granted")
                completion(true)
            case .denied:
                print("❌ Permission previously denied")
                completion(false)
            case .undetermined:
                print("❓ Permission undetermined, showing system dialog...")
                AVAudioApplication.requestRecordPermission { granted in
                    print("🔔 System dialog result: \(granted)")
                    DispatchQueue.main.async {
                        completion(granted)
                    }
                }
            @unknown default:
                print("⚠️ Unknown permission status")
                completion(false)
            }
        } else {
            // iOS 16 及以下的旧 API
            let currentStatus = AVAudioSession.sharedInstance().recordPermission
            print("📊 Current permission status: \(currentStatus.rawValue)")

            switch currentStatus {
            case .granted:
                print("✅ Permission already granted")
                completion(true)
            case .denied:
                print("❌ Permission previously denied")
                completion(false)
            case .undetermined:
                print("❓ Permission undetermined, showing system dialog...")
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    print("🔔 System dialog result: \(granted)")
                    DispatchQueue.main.async {
                        completion(granted)
                    }
                }
            @unknown default:
                print("⚠️ Unknown permission status")
                completion(false)
            }
        }
    }

    func startMonitoring() -> Bool {
        guard !isRecording else { return true }

        setupAudioSession()

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return false }

        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else { return false }

        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let channelData = buffer.floatChannelData?[0]
            let channelDataCount = Int(buffer.frameLength)

            guard let channelData = channelData else { return }

            var sum: Float = 0
            for i in 0..<channelDataCount {
                let sample = channelData[i]
                sum += sample * sample
            }

            let rms = sqrt(sum / Float(channelDataCount))
            let avgPower = 20 * log10(rms)

            // 原始算法 - 参考 App.tsx
            // targetLevel = Math.min(avg / 40.0, 1.5)
            let normalizedLevel = max(0.0, min(1.5, (avgPower + 50) / 40))

            DispatchQueue.main.async {
                self.targetLevel = normalizedLevel

                // Smooth interpolation (matching App.tsx: 0.1)
                let lerpFactor: Float = 0.1
                self.smoothedLevel = self.smoothedLevel + (self.targetLevel - self.smoothedLevel) * lerpFactor

                self.audioLevel = self.smoothedLevel
            }
        }

        do {
            try audioEngine.start()
            isRecording = true
            return true
        } catch {
            return false
        }
    }

    func stopMonitoring() {
        guard isRecording else { return }

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        isRecording = false
        audioLevel = 0.0
        smoothedLevel = 0.0
        targetLevel = 0.0
    }

    deinit {
        stopMonitoring()
    }
}
