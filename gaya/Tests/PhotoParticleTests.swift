import Foundation
import CoreGraphics

/// 粒子化参数测试用例
/// 调用 PhotoParticleTests.shared.runAllTests() 即可
final class PhotoParticleTests {
    static let shared = PhotoParticleTests()

    private init() {}

    func runAllTests() {
        print("🧪 ========== 开始照片粒子化测试 ==========")
        testScalingDefaults()
        testMouseMapping()
        print("🧪 ========== 照片粒子化测试结束 ==========")
    }

    private func testScalingDefaults() {
        assertApprox(PhotoParticleScaling.dispersion(1.5), 0.0225, accuracy: 0.0001, label: "dispersion")
        assertApprox(PhotoParticleScaling.particleSize(2.8), 0.98, accuracy: 0.0001, label: "particleSize")
        assertApprox(PhotoParticleScaling.depthStrength(50.0), 0.9, accuracy: 0.0001, label: "depthStrength")
        assertApprox(PhotoParticleScaling.depthWave(5.0), 0.03, accuracy: 0.0001, label: "depthWave")
        assertApprox(PhotoParticleScaling.danceStrength(3.5), 0.07, accuracy: 0.0001, label: "danceStrength")
        assertApprox(PhotoParticleScaling.structureRetention(0.82), 0.82, accuracy: 0.0001, label: "structureRetention")
        assertApprox(PhotoParticleScaling.motionStrength(0.42), 0.42, accuracy: 0.0001, label: "motionStrength")
        assertApprox(PhotoParticleScaling.cornerRoundness(0.72), 0.72, accuracy: 0.0001, label: "cornerRoundness")
    }

    private func testMouseMapping() {
        let viewport = CGSize(width: 1000, height: 2000)
        let position = CGPoint(x: 250, y: 500)
        let ndc = PhotoParticleScaling.mousePositionNDC(location: position, viewportSize: viewport, screenScale: 2.0)
        assertApprox(ndc.x, 0.0, accuracy: 0.0001, label: "mouseNDC.x")
        assertApprox(ndc.y, 0.0, accuracy: 0.0001, label: "mouseNDC.y")

        let radius = PhotoParticleScaling.mouseRadiusNDC(radiusPoints: 100, viewportSize: viewport, screenScale: 2.0)
        assertApprox(radius, 0.4, accuracy: 0.0001, label: "mouseRadiusNDC")
    }

    private func assertApprox(_ value: Float, _ expected: Float, accuracy: Float, label: String) {
        let diff = abs(value - expected)
        if diff <= accuracy {
            print("✅ \(label) = \(value)")
        } else {
            print("❌ \(label) expected \(expected) got \(value)")
        }
    }
}
