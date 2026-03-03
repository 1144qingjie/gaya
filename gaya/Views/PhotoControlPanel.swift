import SwiftUI

struct PhotoControlPanel: View {
    @ObservedObject var settings: PhotoParticleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FloatSliderRow(title: "GRAIN SIZE", value: $settings.particleSize, range: 0.5...5.0, format: "%.1f")
            FloatSliderRow(title: "FORM RETAIN", value: $settings.structureRetention, range: 0.5...1.0, format: "%.2f")
            FloatSliderRow(title: "MOTION", value: $settings.motionStrength, range: 0.0...0.6, format: "%.2f")
            FloatSliderRow(title: "CORNER ROUND", value: $settings.cornerRoundness, range: 0.2...1.0, format: "%.2f")
            FloatSliderRow(title: "DEPTH STRENGTH", value: $settings.depthStrength, range: 10.0...100.0, format: "%.0f")
            FloatSliderRow(title: "DEPTH WAVE", value: $settings.depthWave, range: 0.0...10.0, format: "%.1f")
            FloatSliderRow(title: "TOUCH RADIUS", value: $settings.mouseRadius, range: 40.0...200.0, format: "%.0f")
            ToggleRow(title: "AUDIO DANCE", isOn: $settings.audioDance)
            FloatSliderRow(title: "DANCE STRENGTH", value: $settings.danceStrength, range: 0.0...6.0, format: "%.1f")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct FloatSliderRow: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Float($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .tint(Color(red: 0.38, green: 0.82, blue: 0.74))
        }
    }
}

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.38, green: 0.82, blue: 0.74)))
        }
    }
}
