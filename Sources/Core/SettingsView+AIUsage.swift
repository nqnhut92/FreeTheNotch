import SwiftUI

extension SettingsView {
    var aiUsageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageTitle("AI Usage")
            SettingsGroupHeader("Notch Tab")
            SettingsCard {
                SettingsToggleRow(
                    "Show AI Usage", description: "Quota, reset times, local tokens and estimated API cost",
                    isOn: Binding(
                        get: { settings.isNotchTabVisible(.aiUsage) },
                        set: { settings.setNotchTabVisible(.aiUsage, isVisible: $0) }), showDivider: false
                )
                .disabled(settings.enabledAIUsageProviders.isEmpty)
            }
            SettingsGroupHeader("Accounts")
            SettingsCard {
                ForEach(AIUsageProvider.allCases) { provider in
                    SettingsToggleRow(
                        "Show " + provider.title,
                        isOn: provider == .codex ? $settings.codexUsageEnabled : $settings.claudeUsageEnabled)
                    ForEach(aiUsageRows(provider)) { account in
                        SettingsRow(
                            account.title, description: aiUsageStatus(account),
                            showDivider: account != aiUsageRows(.claude).last
                        ) {
                            if aiUsage.refreshing.contains(account) {
                                ProgressView().controlSize(.small)
                                Text("Checking…").font(.system(size: 11)).foregroundStyle(.secondary)
                            } else {
                                Button("Refresh") { aiUsage.refresh(account, force: true) }
                                Button("Connect") { aiUsage.refresh(account, force: true, allowPrompt: true) }
                            }
                        }
                        .disabled(!settings.enabledAIUsageProviders.contains(provider))
                    }
                }
            }
            SettingsFootnote(
                "For Claude Desktop, open Settings → Usage in Claude, then refresh here. Codex and Claude Code use their saved login; Connect allows a Keychain prompt if needed. Profiles made with claude-multiprofile get their own row."
            )
            SettingsGroupHeader("Notch Notifications")
            SettingsCard {
                SettingsToggleRow("AI session Live Activities", isOn: $settings.aiLiveActivitiesEnabled)
                SettingsToggleRow("Quota HUD at 80%", isOn: $settings.aiQuotaHUDEnabled, showDivider: false)
            }
            SettingsFootnote(
                "Enabled accounts refresh every minute. Old Claude cache readings remain visible but never raise a new quota warning."
            )
            SettingsGroupHeader("Local Usage")
            SettingsCard {
                SettingsRow(
                    "Token history", description: "Read from local Codex and Claude Code logs; nothing is uploaded",
                    showDivider: false
                ) {
                    EmptyView()
                }
                SettingsRow(
                    "Estimated cost",
                    description: "USD API-equivalent prices from OpenRouter. This is not your subscription bill.",
                    showDivider: false
                ) {
                    EmptyView()
                }
            }
        }
        .onAppear { for account in aiUsage.accounts { aiUsage.refresh(account) } }
    }

    /// A disabled provider still shows its default row, so the page keeps its shape.
    private func aiUsageRows(_ provider: AIUsageProvider) -> [AIUsageAccount] {
        let accounts = aiUsage.accounts(for: provider)
        return accounts.isEmpty ? [AIUsageAccount(provider: provider)] : accounts
    }

    private func aiUsageStatus(_ account: AIUsageAccount) -> String {
        guard settings.enabledAIUsageProviders.contains(account.provider) else { return "Disabled" }
        guard let snapshot = aiUsage.snapshots[account] else { return "Not checked yet" }
        let account = snapshot.identity.map { $0.label + "\n" } ?? ""
        if let message = snapshot.quotaMessage { return account + message }
        if let source = snapshot.quotaSource, let captured = snapshot.quotaCapturedAt {
            return account + (snapshot.isQuotaStale(at: Date()) ? "Old data · " : source + " · Captured ")
                + captured.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return account + "Connected · Updated " + snapshot.updatedAt.formatted(.dateTime.hour().minute())
    }
}
