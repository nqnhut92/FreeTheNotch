import SwiftUI

/// Offline QR generator (Core Image). Replaces the "QR Converter" browser
/// extension: paste text/URL, generate, copy image, download PNG.
struct QRTabView: View {
    @State private var input: String = ""
    @State private var qrImage: NSImage?
    @State private var status: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Paste URL or text…", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(generate)
                Button("Generate", action: generate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            Group {
                if let qrImage {
                    Image(nsImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .background(Color.white)
                        .clipShape(.rect(cornerRadius: 8))
                } else {
                    Text("Your QR code appears here — no browser extension needed.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .frame(height: 150)
                }
            }

            if qrImage != nil {
                HStack(spacing: 8) {
                    Button("Copy image") { copyImage() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Download PNG") { savePNG() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            if let status {
                Text(status).font(.caption).foregroundStyle(Color.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private func generate() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Enter some text first."
            return
        }
        qrImage = QRGenerator.makeQRCode(from: input, size: 600)
        status = qrImage == nil ? "Could not generate a code." : nil
    }

    private func copyImage() {
        guard let qrImage, let png = QRGenerator.pngData(for: qrImage) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        status = "Copied to clipboard."
    }

    private func savePNG() {
        guard let qrImage, let png = QRGenerator.pngData(for: qrImage) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "qr.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            status = "Saved."
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }
}
