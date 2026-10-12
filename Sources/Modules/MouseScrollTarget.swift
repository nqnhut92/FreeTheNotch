// Adapted from Vorssaint: Services/MouseExceptions/MouseAppExceptions.swift.
// Copyright (C) 2026 Vorssaint. SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A cached pointer target lets the event tap avoid synchronous window-server calls.
struct MouseScrollTarget {
    static let cacheLifetime: TimeInterval = 0.25
    let bundleIdentifier: String?
    let region: CGRect?
    let point: CGPoint
    let resolvedAt: TimeInterval

    func contains(_ pointer: CGPoint, now: TimeInterval) -> Bool {
        guard now >= resolvedAt, now - resolvedAt <= Self.cacheLifetime else { return false }
        return namesWindow(at: pointer)
    }
    func namesWindow(at pointer: CGPoint) -> Bool {
        region?.contains(pointer) ?? (point == pointer)
    }
}
