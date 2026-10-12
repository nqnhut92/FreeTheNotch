import SwiftUI

/// Small connection notification panel dropping down from the notch.
/// Appears automatically when a Bluetooth device connects, showing the
/// device icon and name. Auto-dismisses with the live device signal.
struct BluetoothPopupView: View {
    let device: BTDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.kind.symbolName)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // Text centered between the icon and the checkmark; the icons
            // keep their places at the edges.
            VStack(alignment: .center, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Connected")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.12))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
    }
}
