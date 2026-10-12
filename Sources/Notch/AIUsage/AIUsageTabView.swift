// Adapted from Atoll (GPL-3.0-or-later): components/Notch/NotchLLMUsageView.swift
// (provider cards, quota gauges, reset times and compact Today/Week totals).

import SwiftUI

/// Account quota above local token and API-equivalent cost estimates.
struct AIUsageTabView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var monitor: AIUsageMonitor

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(settings.enabledAIUsageProviders) { provider in card(provider) }
            }
            Text("Estimated API cost · local logs · not your subscription bill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .task {
            for provider in settings.enabledAIUsageProviders { monitor.refresh(provider) }
        }
    }

    private func card(_ provider: AIUsageProvider) -> some View {
        let snapshot = monitor.snapshots[provider]
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(provider.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                if monitor.refreshing.contains(provider) {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        monitor.refresh(provider, force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh " + provider.title + " usage")
                }
            }
            if let snapshot {
                if let identity = snapshot.identity {
                    Text(identity.label).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(identity.label)
                }
                if let limit = snapshot.sessionLimit {
                    gauge("Session", limit: limit, isStale: snapshot.isQuotaStale(at: Date()))
                }
                if let limit = snapshot.weekLimit {
                    gauge("Week", limit: limit, isStale: snapshot.isQuotaStale(at: Date()))
                }
                if let message = snapshot.quotaMessage {
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                    if snapshot.requiresConnection {
                        Button("Connect") { monitor.refresh(provider, force: true, allowPrompt: true) }
                            .controlSize(.mini)
                            .disabled(monitor.refreshing.contains(provider))
                    }
                }
                if let source = snapshot.quotaSource, let captured = snapshot.quotaCapturedAt {
                    Text(
                        (snapshot.isQuotaStale(at: Date()) ? "Old data" : source) + " · "
                            + captured.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(snapshot.isQuotaStale(at: Date()) ? .orange : .secondary)
                }
                Divider()
                if snapshot.hasLocalLogs {
                    totals("Today", snapshot.today)
                    totals("7 days", snapshot.week)
                } else {
                    Text(snapshot.logsMessage ?? "No local usage logs")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Text("Reading usage…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 174, alignment: .topLeading)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func gauge(_ title: String, limit: AIUsageLimit, isStale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text("\(limit.fraction.formatted(.percent.precision(.fractionLength(0)))) used")
            }
            .font(.system(size: 11, weight: .medium))
            ProgressView(value: limit.fraction)
                .tint(limit.fraction >= 0.9 ? .red : limit.fraction >= 0.7 ? .orange : .green)
            if let date = limit.resetsAt {
                Text(
                    "\(isStale ? "Recorded reset" : "Resets") \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
                )
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func totals(_ title: String, _ totals: AIUsageTotals) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(totals.totalTokens.formatted(.number.notation(.compactName))) tokens")
                .help("Input: \(totals.inputTokens.formatted()), output: \(totals.outputTokens.formatted()) tokens")
            Text(
                totals.hasUnpricedModel ? "Cost unavailable" : totals.estimatedCostUSD.formatted(.currency(code: "USD"))
            )
            .foregroundStyle(.secondary)
            .help("API-equivalent estimate from OpenRouter model prices; cache rates included where available.")
        }
        .font(.system(size: 10))
    }
}
