// Card grid ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// components/Notch/NotchClipboardView.swift (adaptive LazyVGrid,
// ClipboardGridCard: type icon or thumbnail, one-line preview, type + time
// ago, hover delete, copied checkmark) and managers/ClipboardManager.swift
// (ClipboardItemType icons and names). Ours: search, pin, Clear and
// "Passwords are never captured".

import SwiftUI

/// Clipboard history as a card grid: click to restore, hover to delete,
/// right-click to pin. Passwords are never captured.
struct ClipboardTabView: View {
    @EnvironmentObject var clipboard: ClipboardManager
    @EnvironmentObject var settings: SettingsStore
    @State private var search: String = ""
    @State private var hoveredID: UUID?
    @State private var justCopiedID: UUID?

    /// Atoll's `minCardWidth`: three columns across the 720 pt notch.
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: .infinity), spacing: 8)]

    private var filtered: [ClipboardItem] {
        guard !search.isEmpty else { return clipboard.items }
        return clipboard.items.filter { $0.preview.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Group {
            if settings.clipboardEnabled {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        TextField("Search…", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                        Text("\(clipboard.items.count)/\(settings.clipboardLimit)")
                            .font(.caption).foregroundStyle(Color.secondary)
                            .help("Items in history / maximum")
                        Button("Clear") { clipboard.clear() }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(clipboard.items.isEmpty)
                    }
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(filtered) { item in
                                    card(item)
                                }
                            }
                        }
                    }
                    Text("Passwords are never captured.")
                        .font(.caption2).foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            } else {
                Text("Clipboard disabled in Settings.")
                    .font(.callout).foregroundStyle(Color.secondary).padding()
            }
        }
    }

    private func card(_ item: ClipboardItem) -> some View {
        ClipboardGridCard(
            item: item,
            isHovered: hoveredID == item.id,
            justCopied: justCopiedID == item.id,
            onDelete: { clipboard.delete(item) }
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            // Entering the next card can fire before leaving this one.
            if hovering { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil }
        }
        .onTapGesture { restore(item) }
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin") { clipboard.togglePin(item) }
            Button("Delete", role: .destructive) { clipboard.delete(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ClipboardItemKind(item).name): \(item.preview)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { restore(item) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26))
                .foregroundStyle(.secondary.opacity(0.4))
            Text(search.isEmpty ? "No copies yet" : "No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func restore(_ item: ClipboardItem) {
        clipboard.restore(item)
        withAnimation { justCopiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if justCopiedID == item.id { withAnimation { justCopiedID = nil } }
        }
    }
}

/// Atoll's ClipboardItemType, worked out from what we store.
private enum ClipboardItemKind {
    case text, url, image

    init(_ item: ClipboardItem) {
        if item.isImage {
            self = .image
        } else if let url = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil
        {
            self = .url
        } else {
            self = .text
        }
    }

    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .image: return "photo"
        }
    }

    var name: String {
        switch self {
        case .text: return "Text"
        case .url: return "URL"
        case .image: return "Image"
        }
    }
}

/// One clipboard entry as a compact card (Atoll's ClipboardGridCard).
private struct ClipboardGridCard: View {
    let item: ClipboardItem
    let isHovered: Bool
    let justCopied: Bool
    let onDelete: () -> Void

    var body: some View {
        let kind = ClipboardItemKind(item)
        HStack(spacing: 10) {
            thumbnail(kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.isImage ? "Image" : item.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(
                        item.isImage
                            ? ByteCountFormatter.string(
                                fromByteCount: Int64(item.imageByteCount ?? 0), countStyle: .file)
                            : kind.name
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(Self.timeAgo(item.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchCardBackground(isHighlighted: isHovered))
        .clipShape(NotchStyle.cardShape)
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Delete this item")
                .padding(4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private func thumbnail(_ kind: ClipboardItemKind) -> some View {
        if let url = item.imageURL {
            ClipboardThumbnail(url: url)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                .overlay {
                    // Image cards keep their thumbnail; badge the checkmark on top.
                    if justCopied {
                        RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.5))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                    }
                }
        } else {
            Image(systemName: justCopied ? "checkmark.circle.fill" : kind.icon)
                .font(.system(size: 16))
                .foregroundStyle(justCopied ? .green : .blue)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private static func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

/// Small preview for an image item. Loaded once per card, downscaled off
/// the main thread.
private struct ClipboardThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.08)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: url) {
            image = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let cg = CGImageSourceCreateThumbnailAtIndex(
                        source, 0,
                        [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 96,
                        ] as CFDictionary)
                else { return nil }
                return NSImage(cgImage: cg, size: .zero)
            }.value
        }
    }
}
