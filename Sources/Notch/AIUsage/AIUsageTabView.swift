// Adapted from Atoll (GPL-3.0-or-later): components/Notch/NotchLLMUsageView.swift
// (provider cards, quota gauges, reset times and compact Today/Week totals).
// Stacking one full-width card per account has no reference equivalent.

import SwiftUI

/// One card per account, stacked: who it is on the left, quota and local token and cost estimates on the right.
struct AIUsageTabView: View {
    @EnvironmentObject private var monitor: AIUsageMonitor

    /// Cards that share the 290 pt page; more accounts scroll at a fixed card height.
    private static let cardsWithoutScrolling = 3
    private static let cardSpacing: CGFloat = 6
    private static let scrollingListHeight =
        CGFloat(cardsWithoutScrolling) * AIUsageAccountCard.scrollingHeight
        + CGFloat(cardsWithoutScrolling - 1) * cardSpacing

    var body: some View {
        VStack(spacing: Self.cardSpacing) {
            if monitor.accounts.count > Self.cardsWithoutScrolling {
                ScrollView { cards(fillsHeight: false) }.frame(height: Self.scrollingListHeight)
                Spacer(minLength: 0)
            } else {
                // Cards stretch to share the page, so the footer sits at the bottom with no gap above it.
                cards(fillsHeight: true).frame(maxHeight: .infinity)
            }
            footer
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, AIUsageAccountCard.outerPadding)
        .padding(.top, Self.cardSpacing)
        .task {
            for account in monitor.accounts { monitor.refresh(account) }
        }
    }

    private func cards(fillsHeight: Bool) -> some View {
        VStack(spacing: Self.cardSpacing) {
            ForEach(monitor.accounts) { account in
                AIUsageAccountCard(account: account, snapshot: monitor.snapshots[account]) {
                    monitor.refresh(account, force: true, allowPrompt: true)
                }
                .frame(height: fillsHeight ? nil : AIUsageAccountCard.scrollingHeight)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("Estimated API cost · local logs · not your subscription bill")
            Spacer(minLength: 0)
            if monitor.refreshing.isEmpty {
                Button {
                    for account in monitor.accounts { monitor.refresh(account, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh AI usage")
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
}

/// Account on the left (30 %), usage on the right (70 %). Widths derive from the fixed expanded notch width, never
/// from a measurement, and text shrinks slightly rather than truncating.
private struct AIUsageAccountCard: View {
    let account: AIUsageAccount
    let snapshot: AIUsageSnapshot?
    let connect: () -> Void

    static let outerPadding: CGFloat = 14
    static let scrollingHeight: CGFloat = 80
    private static let horizontalPadding: CGFloat = 12
    private static let verticalPadding: CGFloat = 8
    private static let columnSpacing: CGFloat = 14
    private static let identityShare: CGFloat = 0.3
    private static let identityWidth =
        ((DisplayGeometry.expandedWidth - 2 * outerPadding - 2 * horizontalPadding - columnSpacing) * identityShare)
        .rounded()
    private static let windowLabelWidth: CGFloat = 50
    /// Room for "100% used · Resets Oct 28 at 8:42 AM" at the card's font size.
    private static let statusWidth: CGFloat = 206
    private static let minimumTextScale: CGFloat = 0.8
    private static let lineSpacing: CGFloat = 5

    var body: some View {
        HStack(alignment: .center, spacing: Self.columnSpacing) {
            identity.frame(width: Self.identityWidth, alignment: .leading)
            usage.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchCardBackground())
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(account.provider.title).font(.system(size: 14, weight: .semibold))
                if let profile = account.profile {
                    Text(profile.name)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            }
            if let name = snapshot?.identity?.name {
                Text(name).font(.system(size: 12))
            }
            if let email = snapshot?.identity?.email {
                Text(email).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(Self.minimumTextScale)
    }

    @ViewBuilder private var usage: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: Self.lineSpacing) {
                if snapshot.sessionLimit != nil || snapshot.weekLimit != nil {
                    if let limit = snapshot.sessionLimit { window("Session", limit, snapshot) }
                    if let limit = snapshot.weekLimit { window("Week", limit, snapshot) }
                } else if let message = snapshot.quotaMessage {
                    HStack(spacing: 8) {
                        Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if snapshot.requiresConnection {
                            Button("Connect", action: connect).controlSize(.mini)
                        }
                    }
                }
                totals(snapshot)
            }
            .font(.system(size: 11))
        } else {
            Text("Reading usage…").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// An old Desktop cache reading turns its status orange instead of carrying a separate source line.
    private func window(_ title: String, _ limit: AIUsageLimit, _ snapshot: AIUsageSnapshot) -> some View {
        let now = Date()
        var status = limit.fraction.formatted(.percent.precision(.fractionLength(0))) + " used"
        if let reset = limit.resetsAt { status += " · Resets " + AIUsageResetFormat.text(reset, now: now) }
        return HStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary).frame(width: Self.windowLabelWidth, alignment: .leading)
            AIUsageQuotaBar(fraction: limit.fraction)
            Text(status)
                .monospacedDigit()
                .foregroundStyle(snapshot.isQuotaStale(at: now) ? .orange : .primary)
                .lineLimit(1)
                .minimumScaleFactor(Self.minimumTextScale)
                .frame(width: Self.statusWidth, alignment: .leading)
        }
    }

    /// A Desktop-only profile never has its own logs, so it shows no totals line at all.
    @ViewBuilder private func totals(_ snapshot: AIUsageSnapshot) -> some View {
        if snapshot.hasLocalLogs {
            HStack(spacing: 18) {
                totalsText("Today", snapshot.today)
                totalsText("7 days", snapshot.week)
            }
            .lineLimit(1)
            .minimumScaleFactor(Self.minimumTextScale)
        } else if account.profile?.codeConfigDirectory != nil || account.profile == nil {
            Text(snapshot.logsMessage ?? "No local usage logs").foregroundStyle(.secondary)
        }
    }

    private func totalsText(_ title: String, _ totals: AIUsageTotals) -> Text {
        let cost =
            totals.hasUnpricedModel ? "Cost unavailable" : totals.estimatedCostUSD.formatted(.currency(code: "USD"))
        return Text(title + " ").foregroundStyle(.secondary)
            + Text(totals.totalTokens.formatted(.number.notation(.compactName)) + " tokens · " + cost)
    }
}

/// A thin fixed-height gauge; the system linear ProgressView is taller than a three-line card allows.
private struct AIUsageQuotaBar: View {
    let fraction: Double

    private static let height: CGFloat = 5

    private var tint: Color { fraction >= 0.9 ? .red : fraction >= 0.7 ? .orange : .green }

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.12))
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule().fill(tint)
                        .frame(width: max(Self.height, geometry.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: Self.height)
    }
}
