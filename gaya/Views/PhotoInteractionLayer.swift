import SwiftUI

struct PhotoInteractionLayer: View {
    var isEnabled: Bool
    @Binding var interaction: PhotoInteractionState
    @Binding var zoom: CGFloat

    private let zoomRange: ClosedRange<CGFloat> = 0.6...2.2
    @State private var baseZoom: CGFloat = 1.0

    var body: some View {
        GeometryReader { _ in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            interaction = PhotoInteractionState(location: value.location, isActive: true)
                        }
                        .onEnded { _ in
                            interaction = .inactive
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newZoom = clamp(baseZoom * value)
                            zoom = newZoom
                        }
                        .onEnded { _ in
                            baseZoom = zoom
                        }
                )
        }
        .allowsHitTesting(isEnabled)
        .onAppear {
            baseZoom = zoom
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }
}
