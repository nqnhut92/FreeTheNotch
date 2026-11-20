import SwiftUI

/// The record and the tonearm, drawn in a 300 × 300 space and scaled to the space the view is given.
struct TurntableView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    /// Called when the tonearm is lowered (true) or lifted (false) by dragging or clicking it.
    let setPlaying: (Bool) -> Void

    private static let recordCenter = CGPoint(x: 130, y: 150)
    private static let recordDiameter = 248.0

    var body: some View {
        GeometryReader { proxy in
            let side = TonearmGeometry.canvasSide
            ZStack(alignment: .topLeading) {
                VinylRecordView(artwork: artwork, isSpinning: isPlaying)
                    .frame(width: Self.recordDiameter, height: Self.recordDiameter)
                    .position(Self.recordCenter)
                TonearmView(isPlaying: isPlaying, setPlaying: setPlaying)
            }
            .frame(width: side, height: side)
            .coordinateSpace(.named(TonearmView.coordinateSpaceName))
            .scaleEffect(min(proxy.size.width, proxy.size.height) / side, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Record player")
    }
}
