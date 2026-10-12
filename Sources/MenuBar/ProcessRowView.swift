import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One row of a per-app breakdown list: icon + name + value.
/// Vorssaint's ProcessUsageRow: click brings the app forward, right-click
/// offers Force Quit, hover shows the full name.
struct ProcessRowView: View {
    var row: ProcessRow
    /// Formats `row.value`: percent, bytes, or rate.
    var valueText: String

    /// Rows carry the responsible app's pid (ProcessMonitor groups by owner).
    private var app: NSRunningApplication? {
        row.pid > 0 ? NSRunningApplication(processIdentifier: row.pid) : nil
    }

    var body: some View {
        Group {
            if let app, app.activationPolicy == .regular {
                Button {
                    app.activate()
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .contextMenu {
            Button("Force Quit", role: .destructive) {
                app?.forceTerminate()
            }
            .disabled(app == nil || app?.processIdentifier == ProcessInfo.processInfo.processIdentifier)
        }
        .help(row.name)
    }

    private var content: some View {
        HStack(spacing: 7) {
            if let icon = row.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(for: .unixExecutable))
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            Text(row.name)
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(valueText)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.panelSecondary)
        }
        .contentShape(Rectangle())
    }
}
