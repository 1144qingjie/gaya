import SwiftUI
import UIKit

final class PhotoParticleSettings: ObservableObject {
    @Published var dispersion: Float = 0.55
    @Published var particleSize: Float = 2.4
    @Published var contrast: Float = 1.3
    @Published var flowSpeed: Float = 1.0
    @Published var flowAmplitude: Float = 1.0
    @Published var depthStrength: Float = 32.0
    @Published var mouseRadius: Float = 110.0
    @Published var colorShiftSpeed: Float = 2.0
    @Published var audioDance: Bool = true
    @Published var danceStrength: Float = 1.2
    @Published var depthWave: Float = 1.4
    @Published var structureRetention: Float = 0.93
    @Published var motionStrength: Float = 0.16
    @Published var cornerRoundness: Float = 0.88

    var snapshot: PhotoParticleSettingsValue {
        PhotoParticleSettingsValue(
            dispersion: dispersion,
            particleSize: particleSize,
            contrast: contrast,
            flowSpeed: flowSpeed,
            flowAmplitude: flowAmplitude,
            depthStrength: depthStrength,
            mouseRadius: mouseRadius,
            colorShiftSpeed: colorShiftSpeed,
            audioDance: audioDance,
            danceStrength: danceStrength,
            depthWave: depthWave,
            structureRetention: structureRetention,
            motionStrength: motionStrength,
            cornerRoundness: cornerRoundness
        )
    }
}

enum PolaroidPaperStyle: String, CaseIterable, Identifiable {
    case glacierBlue
    case coralPink
    case meadowGreen
    case sunsetOrange
    case champagneGold
    case seaSaltCyan

    var id: String { rawValue }

    static let defaultStyle: PolaroidPaperStyle = .glacierBlue

    var displayName: String {
        switch self {
        case .glacierBlue:
            return "冰川蓝"
        case .coralPink:
            return "珊瑚粉"
        case .meadowGreen:
            return "森林绿"
        case .sunsetOrange:
            return "日落橙"
        case .champagneGold:
            return "香槟金"
        case .seaSaltCyan:
            return "海盐青"
        }
    }

    var selectionTopColor: Color {
        switch self {
        case .glacierBlue:
            return .polaroidHex(0x65CDF8)
        case .coralPink:
            return .polaroidHex(0xFF8E82)
        case .meadowGreen:
            return .polaroidHex(0x84C27D)
        case .sunsetOrange:
            return .polaroidHex(0xFFB067)
        case .champagneGold:
            return .polaroidHex(0xEFD99E)
        case .seaSaltCyan:
            return .polaroidHex(0x74DBCF)
        }
    }

    var selectionBottomColor: Color {
        switch self {
        case .glacierBlue:
            return .polaroidHex(0xA7F0EA)
        case .coralPink:
            return .polaroidHex(0xF59EC8)
        case .meadowGreen:
            return .polaroidHex(0xA6C966)
        case .sunsetOrange:
            return .polaroidHex(0xFFD28F)
        case .champagneGold:
            return .polaroidHex(0xEAC77E)
        case .seaSaltCyan:
            return .polaroidHex(0xA0DFD7)
        }
    }

    var frontTopColor: Color {
        switch self {
        case .glacierBlue:
            return .polaroidHex(0xE7F7FF)
        case .coralPink:
            return .polaroidHex(0xFFF0EB)
        case .meadowGreen:
            return .polaroidHex(0xEEF8E9)
        case .sunsetOrange:
            return .polaroidHex(0xFFF3E4)
        case .champagneGold:
            return .polaroidHex(0xFFF9EA)
        case .seaSaltCyan:
            return .polaroidHex(0xEAF9F6)
        }
    }

    var frontBottomColor: Color {
        switch self {
        case .glacierBlue:
            return .polaroidHex(0xC9EEF8)
        case .coralPink:
            return .polaroidHex(0xFFDCE8)
        case .meadowGreen:
            return .polaroidHex(0xDDEFCB)
        case .sunsetOrange:
            return .polaroidHex(0xFFE2BE)
        case .champagneGold:
            return .polaroidHex(0xF4E9C8)
        case .seaSaltCyan:
            return .polaroidHex(0xCDEDE6)
        }
    }

    var backTopColor: Color {
        switch self {
        case .glacierBlue:
            return .polaroidHex(0xE5F6FF)
        case .coralPink:
            return .polaroidHex(0xFFEDE8)
        case .meadowGreen:
            return .polaroidHex(0xECF7E6)
        case .sunsetOrange:
            return .polaroidHex(0xFFF1DF)
        case .champagneGold:
            return .polaroidHex(0xFFF8E6)
        case .seaSaltCyan:
            return .polaroidHex(0xE6F7F4)
        }
    }

    var backBottomColor: Color {
        switch self {
        case .glacierBlue:
            return .polaroidHex(0xC6EEF9)
        case .coralPink:
            return .polaroidHex(0xFFD8E5)
        case .meadowGreen:
            return .polaroidHex(0xD7EDC2)
        case .sunsetOrange:
            return .polaroidHex(0xFFDBB0)
        case .champagneGold:
            return .polaroidHex(0xF1E3BF)
        case .seaSaltCyan:
            return .polaroidHex(0xC7E9E2)
        }
    }

    var borderColor: Color {
        switch self {
        case .glacierBlue:
            return .polaroidHex(0x71CAE7)
        case .coralPink:
            return .polaroidHex(0xE788AA)
        case .meadowGreen:
            return .polaroidHex(0x84B26F)
        case .sunsetOrange:
            return .polaroidHex(0xDEA05C)
        case .champagneGold:
            return .polaroidHex(0xC8AB6A)
        case .seaSaltCyan:
            return .polaroidHex(0x6CAFAB)
        }
    }

    var backLineColor: Color {
        switch self {
        case .glacierBlue:
            return .polaroidHex(0x5D8FA3)
        case .coralPink:
            return .polaroidHex(0xA97383)
        case .meadowGreen:
            return .polaroidHex(0x69855D)
        case .sunsetOrange:
            return .polaroidHex(0x9D7C57)
        case .champagneGold:
            return .polaroidHex(0x8C7B57)
        case .seaSaltCyan:
            return .polaroidHex(0x608681)
        }
    }

    var inkColor: Color {
        switch self {
        case .glacierBlue:
            return .polaroidHex(0x2F3F46)
        case .coralPink:
            return .polaroidHex(0x4C363B)
        case .meadowGreen:
            return .polaroidHex(0x334031)
        case .sunsetOrange:
            return .polaroidHex(0x4C3A2D)
        case .champagneGold:
            return .polaroidHex(0x4D4232)
        case .seaSaltCyan:
            return .polaroidHex(0x31433F)
        }
    }

    var canvasBackgroundUIColor: UIColor {
        switch self {
        case .glacierBlue:
            return .polaroidHex(0xDDF1F6)
        case .coralPink:
            return .polaroidHex(0xF9E5EB)
        case .meadowGreen:
            return .polaroidHex(0xE5EFE0)
        case .sunsetOrange:
            return .polaroidHex(0xF7E9D8)
        case .champagneGold:
            return .polaroidHex(0xF5EBD1)
        case .seaSaltCyan:
            return .polaroidHex(0xDFEFEA)
        }
    }
}

private extension Color {
    static func polaroidHex(_ hex: UInt32, opacity: Double = 1) -> Color {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

private extension UIColor {
    static func polaroidHex(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct PhotoParticleSettingsValue: Equatable {
    var dispersion: Float
    var particleSize: Float
    var contrast: Float
    var flowSpeed: Float
    var flowAmplitude: Float
    var depthStrength: Float
    var mouseRadius: Float
    var colorShiftSpeed: Float
    var audioDance: Bool
    var danceStrength: Float
    var depthWave: Float
    var structureRetention: Float
    var motionStrength: Float
    var cornerRoundness: Float

    static let `default` = PhotoParticleSettingsValue(
        dispersion: 0.55,
        particleSize: 2.4,
        contrast: 1.3,
        flowSpeed: 1.0,
        flowAmplitude: 1.0,
        depthStrength: 32.0,
        mouseRadius: 110.0,
        colorShiftSpeed: 2.0,
        audioDance: true,
        danceStrength: 1.2,
        depthWave: 1.4,
        structureRetention: 0.93,
        motionStrength: 0.16,
        cornerRoundness: 0.88
    )
}

struct PhotoInteractionState: Equatable {
    var location: CGPoint?
    var isActive: Bool

    static let inactive = PhotoInteractionState(location: nil, isActive: false)
}

enum PhotoParticleScaling {
    static func dispersion(_ value: Float) -> Float { value * 0.015 }
    static func particleSize(_ value: Float) -> Float { value * 0.35 }
    static func contrast(_ value: Float) -> Float { value }
    static func flowSpeed(_ value: Float) -> Float { value }
    static func flowAmplitude(_ value: Float) -> Float { value * 0.04 }
    static func depthStrength(_ value: Float) -> Float { value * 0.018 }
    static func depthWave(_ value: Float) -> Float { value * 0.006 }
    static func danceStrength(_ value: Float) -> Float { value * 0.02 }
    static func structureRetention(_ value: Float) -> Float { min(max(value, 0.0), 1.0) }
    static func motionStrength(_ value: Float) -> Float { min(max(value, 0.0), 1.0) }
    static func cornerRoundness(_ value: Float) -> Float { min(max(value, 0.0), 1.0) }

    static func mouseRadiusNDC(radiusPoints: Float, viewportSize: CGSize, screenScale: Float) -> Float {
        let minDimension = max(CGFloat(1.0), min(viewportSize.width, viewportSize.height))
        let radiusPixels = CGFloat(radiusPoints) * CGFloat(screenScale)
        return Float(radiusPixels / (minDimension * 0.5))
    }

    static func mousePositionNDC(location: CGPoint, viewportSize: CGSize, screenScale: Float) -> SIMD2<Float> {
        let width = max(CGFloat(1.0), viewportSize.width)
        let height = max(CGFloat(1.0), viewportSize.height)
        let x = (location.x * CGFloat(screenScale)) / width
        let y = (location.y * CGFloat(screenScale)) / height
        return SIMD2<Float>(Float(x) * 2.0 - 1.0, 1.0 - Float(y) * 2.0)
    }
}
