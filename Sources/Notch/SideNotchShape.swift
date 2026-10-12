// Ported from CodeNotch (github.com/vinzdg/codenotch), MIT:
// Sources/Notch/SideNotchShape.swift (canonical right-edge path, `fluidTurn`,
// `turn`, `transform(for:depth:)`), Sources/Notch/NotchLayout.swift and
// Sources/DesignSystem/Design.swift (sizes). Window sizing follows
// Sources/Notch/NotchGeometry.swift (`panelFrame`). Only the plain side-edge case is
// kept: no camera cutout, no joins, no dip, no hover fold. The cell stack has
// no reference equivalent.

import SwiftUI

/// Screen edge the side notch sits on.
enum SideNotchEdge: String, CaseIterable {
    case left, right

    var title: String { self == .left ? "Left" : "Right" }
    var opposite: SideNotchEdge { self == .left ? .right : .left }
}

/// What a side notch cell holds. The order is the user's to pick
/// (Settings → Side Notch → Cells); no reference equivalent.
enum SideNotchCell: String, CaseIterable, Identifiable {
    case duo, bluetooth, keepAwake, system, network, disk, power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duo: return "DuoGlyph"
        case .bluetooth: return "Bluetooth"
        case .keepAwake: return "Keep Awake"
        case .system: return "System"
        case .network: return "Network"
        case .disk: return "Disks"
        case .power: return "Power"
        }
    }

    var icon: String {
        switch self {
        case .duo: return "wifi"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .keepAwake: return "moon.zzz.fill"
        case .system: return "cpu"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        }
    }

    var detail: String {
        switch self {
        case .duo: return "Battery, Wi-Fi and volume"
        case .bluetooth: return "Bluetooth menu"
        default: return "Opens " + title
        }
    }
}

/// CodeNotch's sizes. Every number is measured off CodeNotch's design frame
/// in pixels; `px` turns them into points (a 117 px ring is 44 pt).
enum SideNotchLayout {
    static func px(_ pixels: CGFloat) -> CGFloat { pixels * 44 / 117 }

    static let bodyDepth = px(186)
    static let curlRadius = px(103)
    static let cornerRadius = px(78.8)
    static let padTop = px(69.5)  // body top -> first ring
    static let cellSpacing = px(28)  // one ring -> the next (no labels here)
    static let ringDiameter = px(117)  // 44 pt

    /// What zoom 1× draws at: 75 % of CodeNotch's size, which is too big on
    /// the built-in display (ring 33 pt, shape about 52 × 243 pt).
    static let baseScale: CGFloat = 0.75

    /// Seven cells: connectivity and direct system sections,
    /// in `SettingsStore.sideNotchOrder`.
    static let cellCount = SideNotchCell.allCases.count

    /// The straight body, between the flares. No labels under the rings, so
    /// the bottom padding matches the top.
    static var bodyLength: CGFloat {
        2 * padTop + CGFloat(cellCount) * ringDiameter + CGFloat(cellCount - 1) * cellSpacing
    }

    /// Whole shape, flares included, at zoom 1.
    static var size: CGSize { CGSize(width: bodyDepth, height: bodyLength + 2 * curlRadius) }

    /// Whole-point dimensions keep AppKit's window and SwiftUI's shape on the same edge.
    static func windowSize(zoom: CGFloat) -> CGSize {
        CGSize(width: ceil(size.width * zoom), height: ceil(size.height * zoom))
    }

    /// Centre of cell `index`, measured from the shape's top, at zoom 1.
    static func cellCenterY(_ index: Int) -> CGFloat {
        curlRadius + padTop + ringDiameter / 2 + CGFloat(index) * (ringDiameter + cellSpacing)
    }
}

/// The notch body: a pill welded to a side edge, with inverse rounded
/// corners at each end that flare back out to the edge so it reads as part
/// of the bezel. Written once for the right edge, mirrored for the left.
/// `rect` is the whole shape including the flares; the screen edge is at
/// `maxX` (right) or `minX` (left).
struct SideNotchShape: Shape {
    var edge: SideNotchEdge = .right
    var curlRadius: CGFloat = SideNotchLayout.curlRadius
    var cornerRadius: CGFloat = SideNotchLayout.cornerRadius
    /// CodeNotch's `filletRamp`: share of the flare spent ramping its bend.
    var flareRamp: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        let canonical = canonicalPath(in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        return
            canonical
            .applying(Self.transform(for: edge, depth: rect.width))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    static func transform(for edge: SideNotchEdge, depth: CGFloat) -> CGAffineTransform {
        switch edge {
        case .right: return .identity
        // Mirrored: the flares point the other way.
        case .left: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: depth, ty: 0)
        }
    }

    /// The handle reach that makes a cubic Bézier trace a circle.
    private static let circleReach: CGFloat = 0.5523

    /// A quarter turn whose bend ramps in from nothing at both ends, walked
    /// out as a polyline (CodeNotch's `fluidTurn`).
    private func fluidTurn(
        _ path: inout Path, to: CGPoint,
        leaving: CGVector, arriving: CGVector, ramp: CGFloat
    ) {
        guard let from = path.currentPoint else { return }
        let alongReach = (to.x - from.x) * leaving.dx + (to.y - from.y) * leaving.dy
        let acrossReach = (to.x - from.x) * arriving.dx + (to.y - from.y) * arriving.dy
        guard alongReach != 0, acrossReach != 0 else {
            path.addLine(to: to)
            return
        }
        let p = min(max(ramp, 0), 0.5)
        let bend = (CGFloat.pi / 2) / (1 - p)
        let steps = 96
        var heading: CGFloat = 0
        var u: CGFloat = 0
        var v: CGFloat = 0
        var walk: [(CGFloat, CGFloat)] = [(0, 0)]
        for i in 0..<steps {
            let s = (CGFloat(i) + 0.5) / CGFloat(steps)
            let share = p <= 0 ? 1 : (s < p ? s / p : (s > 1 - p ? (1 - s) / p : 1))
            heading += bend * share / CGFloat(steps)
            u += cos(heading) / CGFloat(steps)
            v += sin(heading) / CGFloat(steps)
            walk.append((u, v))
        }
        let (endU, endV) = walk[walk.count - 1]
        let alongScale = alongReach / endU
        let acrossScale = acrossReach / endV
        for (wu, wv) in walk.dropFirst() {
            path.addLine(
                to: CGPoint(
                    x: from.x + leaving.dx * wu * alongScale + arriving.dx * wv * acrossScale,
                    y: from.y + leaving.dy * wu * alongScale + arriving.dy * wv * acrossScale))
        }
    }

    /// A circular quarter turn from the current point to `to`.
    private func turn(_ path: inout Path, to: CGPoint, leaving: CGVector, arriving: CGVector) {
        guard let from = path.currentPoint else { return }
        let delta = CGVector(dx: to.x - from.x, dy: to.y - from.y)
        let out = abs(delta.dx * leaving.dx + delta.dy * leaving.dy)
        let into = abs(delta.dx * arriving.dx + delta.dy * arriving.dy)
        guard out > 0, into > 0 else {
            path.addLine(to: to)
            return
        }
        path.addCurve(
            to: to,
            control1: CGPoint(
                x: from.x + leaving.dx * out * Self.circleReach,
                y: from.y + leaving.dy * out * Self.circleReach),
            control2: CGPoint(
                x: to.x - arriving.dx * into * Self.circleReach,
                y: to.y - arriving.dy * into * Self.circleReach))
    }

    private func canonicalPath(in rect: CGRect) -> Path {
        // The corner is claimed first, out of half the depth, and the flare
        // takes what is left (CodeNotch's ordering).
        let wanted = max(0, min(cornerRadius, rect.width / 2))
        let curl = max(0, min(curlRadius, rect.width - wanted))
        let corner = max(0, min(wanted, (rect.height - 2 * curl) / 2))
        let bodyTop = rect.minY + curl
        let bodyBottom = rect.maxY - curl
        let far = rect.minX

        var path = Path()
        // Screen edge, above the body; flare inward and down onto the top edge.
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        fluidTurn(
            &path, to: CGPoint(x: rect.maxX - curl, y: bodyTop),
            leaving: CGVector(dx: 0, dy: 1), arriving: CGVector(dx: -1, dy: 0), ramp: flareRamp)
        path.addLine(to: CGPoint(x: far + corner, y: bodyTop))
        turn(
            &path, to: CGPoint(x: far, y: bodyTop + corner),
            leaving: CGVector(dx: -1, dy: 0), arriving: CGVector(dx: 0, dy: 1))
        path.addLine(to: CGPoint(x: far, y: bodyBottom - corner))
        turn(
            &path, to: CGPoint(x: far + corner, y: bodyBottom),
            leaving: CGVector(dx: 0, dy: 1), arriving: CGVector(dx: 1, dy: 0))
        path.addLine(to: CGPoint(x: rect.maxX - curl, y: bodyBottom))
        // Flare back out to the screen edge.
        fluidTurn(
            &path, to: CGPoint(x: rect.maxX, y: rect.maxY),
            leaving: CGVector(dx: 1, dy: 0), arriving: CGVector(dx: 0, dy: 1), ramp: flareRamp)
        path.closeSubpath()
        return path
    }
}
