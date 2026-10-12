// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// DynamicIsland/components/Live activities/MarqueeTextView.swift.

import AppKit
import SwiftUI

struct MarqueeSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MarqueeMeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear.preference(key: MarqueeSizePreferenceKey.self, value: geometry.size)
            })
    }
}

/// Atoll's marquee text: static when the text fits; scrolls in a seamless
/// loop (pause, slide one copy's width, snap back) when it overflows.
struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    /// The same font as `font`, as an NSFont: SwiftUI's Font has no metrics,
    /// and the row's height is derived from this one's point size.
    let nsFont: NSFont
    let textColor: Color
    let backgroundColor: Color
    /// Pause before each scroll, in seconds.
    let minDuration: Double
    let frameWidth: CGFloat
    /// Where a text that fits rests; a scrolling one starts at the leading
    /// edge. The lock screen's artwork controls centre it.
    let alignment: HorizontalAlignment
    /// No scrolling while true: the Settings preview stops its animations
    /// when its window is not in front (`lockAnimationsPaused`).
    let paused: Bool

    /// Gap between the two copies of the text that make up the scrolling loop.
    static let loopSpacing: CGFloat = 20
    /// Scroll speed, in points per second.
    static let scrollSpeed: CGFloat = 30
    /// Settling time after a change before a scroll starts.
    private static let startDelay: TimeInterval = 0.1

    /// Recovers the width of a single copy of the text from the measured loop.
    static func textWidth(fromLoopWidth loopWidth: CGFloat) -> CGFloat {
        max(0, (loopWidth - loopSpacing) / 2)
    }

    /// Seconds one pass of the scroll takes.
    static func scrollDuration(textWidth: CGFloat) -> Double {
        Double(textWidth / scrollSpeed)
    }

    /// How far one pass moves: one copy plus the gap, so the second copy
    /// lands where the first started.
    static func scrollDistance(textWidth: CGFloat) -> CGFloat {
        textWidth + loopSpacing
    }

    /// Offset of a text that fits: the loop's hidden second copy still
    /// takes room, so centring is an offset, not the frame's alignment.
    static func restingOffset(textWidth: CGFloat, frameWidth: CGFloat, alignment: HorizontalAlignment) -> CGFloat {
        guard textWidth <= frameWidth, alignment == .center else { return 0 }
        return max(0, (frameWidth - textWidth) / 2)
    }

    /// Height the row takes for a font of `pointSize`.
    static func rowHeight(pointSize: CGFloat) -> CGFloat {
        max(1, pointSize * 1.3)
    }

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isAnimating = false
    /// Each restart bumps this, and a loop whose id is stale stops, so two
    /// loops never fight over `offset` after a quick restart.
    @State private var loopID = 0

    init(
        _ text: Binding<String>, font: Font = .body, nsFont: NSFont = .preferredFont(forTextStyle: .body),
        textColor: Color = .primary, backgroundColor: Color = .clear,
        minDuration: Double = 3.0, frameWidth: CGFloat = 200,
        alignment: HorizontalAlignment = .leading, paused: Bool = false
    ) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = max(frameWidth, 1)
        self.alignment = alignment
        self.paused = paused
    }

    private var needsScrolling: Bool {
        textWidth > frameWidth
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: Self.loopSpacing) {
                Text(text)
                Text(text)
                    .opacity(needsScrolling ? 1 : 0)
            }
            .id(text)
            .font(font)
            .foregroundStyle(textColor)
            .fixedSize(horizontal: true, vertical: false)
            .offset(
                x: offset + Self.restingOffset(textWidth: textWidth, frameWidth: frameWidth, alignment: alignment)
            )
            .background(backgroundColor)
            .modifier(MarqueeMeasureSizeModifier())
            .onPreferenceChange(MarqueeSizePreferenceKey.self) { size in
                let measuredWidth = Self.textWidth(fromLoopWidth: size.width)
                // Parents re-render every second (playback updates); only a
                // real size change restarts the scroll.
                guard abs(measuredWidth - textWidth) > 0.5 else { return }
                textWidth = measuredWidth
                resetAndStart()
            }
            .onChange(of: text) { _, _ in
                resetAndStart()
            }
            .onChange(of: paused) { _, _ in
                resetAndStart()
            }
            .onAppear {
                resetAndStart()
            }
            .onDisappear {
                isAnimating = false
                loopID &+= 1
            }
        }
        .frame(width: frameWidth, alignment: .leading)
        .clipped()
        .frame(height: Self.rowHeight(pointSize: nsFont.pointSize))
    }

    private func resetAndStart() {
        loopID &+= 1
        let id = loopID
        isAnimating = false
        withAnimation(.none) {
            offset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startDelay) {
            guard id == loopID, needsScrolling, !paused else { return }
            isAnimating = true
            scrollPass(id: id)
        }
    }

    /// One pass: wait `minDuration`, slide, snap back, then the next pass.
    private func scrollPass(id: Int) {
        guard isAnimating && needsScrolling && id == loopID else { return }
        let duration = Self.scrollDuration(textWidth: textWidth)
        DispatchQueue.main.asyncAfter(deadline: .now() + minDuration) {
            guard isAnimating && id == loopID else { return }
            withAnimation(.linear(duration: duration)) {
                offset = -Self.scrollDistance(textWidth: textWidth)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                guard isAnimating && id == loopID else { return }
                withAnimation(.none) {
                    offset = 0
                }
                scrollPass(id: id)
            }
        }
    }
}
