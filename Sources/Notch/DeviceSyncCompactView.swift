import SwiftUI

/// Device-sync live activity: the device's name in the left ear and a
/// turning sync icon in the right, leaving the camera cutout empty.
struct DeviceSyncCompactView: View {
    let label: String
    /// Width the name gets; a longer one is truncated.
    let labelSlotWidth: CGFloat

    private static let iconSize: CGFloat = 14
    private static let edgePadding: CGFloat = 4
    private static let turn = Animation.linear(duration: 1.4).repeatForever(autoreverses: false)

    @State private var isTurning = false

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: DeviceSyncActivity.labelFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelSlotWidth, alignment: .leading)
                .padding(.leading, Self.edgePadding)
            Spacer(minLength: 0)
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: Self.iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isTurning ? 360 : 0))
                .animation(Self.turn, value: isTurning)
                .padding(.trailing, Self.edgePadding)
        }
        .onAppear { isTurning = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Syncing \(label)")
    }
}
