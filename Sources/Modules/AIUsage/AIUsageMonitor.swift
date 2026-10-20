// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/LLMUsageManager.swift.

import Combine
import Foundation

/// Shared between displays; refreshes enabled accounts once a minute, including while the notch is closed.
/// Claude profiles from claude-multiprofile are re-read on every pass, so added or removed profiles follow.
@MainActor
final class AIUsageMonitor: ObservableObject {
    @Published private(set) var accounts: [AIUsageAccount] = []
    @Published private(set) var snapshots: [AIUsageAccount: AIUsageSnapshot] = [:]
    @Published private(set) var refreshing = Set<AIUsageAccount>()
    @Published private(set) var quotaAlert: AIQuotaAlertPolicy.Alert?
    private var alertPolicy = AIQuotaAlertPolicy()
    private var alertQueue: [AIQuotaAlertPolicy.Alert] = []
    private var alertTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private var hudSubscription: AnyCancellable?
    private var showsQuotaHUD = true
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let environment = ProcessInfo.processInfo.environment
    private let service: AIUsageService
    private var profiles: [ClaudeProfile] = []
    private var tasks: [AIUsageAccount: Task<Void, Never>] = [:]
    private static let refreshInterval: TimeInterval = 60

    private var enabledProviders = Set(AIUsageProvider.allCases)
    private var settingsSubscription: AnyCancellable?

    init(settings: SettingsStore) {
        let directories = AIUsageDirectories(
            home: FileManager.default.homeDirectoryForCurrentUser, environment: ProcessInfo.processInfo.environment)
        let store = AIUsageCredentialStore()
        service = AIUsageService(
            logRoots: directories.logRoots, desktopCache: ClaudeDesktopUsageCache()
        ) {
            account, allowPrompt in try await store.load(account, allowPrompt: allowPrompt)
        }
        settingsSubscription = Publishers.CombineLatest(settings.$codexUsageEnabled, settings.$claudeUsageEnabled)
            .sink { [weak self] codex, claude in
                guard let self else { return }
                enabledProviders = Set(AIUsageProvider.allCases.filter { $0 == .codex ? codex : claude })
                updateAccounts()
            }
        hudSubscription = settings.$aiQuotaHUDEnabled.sink { [weak self] enabled in
            guard let self else { return }
            showsQuotaHUD = enabled
            if !enabled {
                alertTask?.cancel()
                alertQueue = []
                quotaAlert = nil
            }
        }
        backgroundTask = Task { [weak self, home = self.home, environment = self.environment] in
            while !Task.isCancelled {
                let profiles = await Task.detached { ClaudeProfile.profiles(home: home, environment: environment) }
                    .value
                guard let self else { return }
                if profiles != self.profiles {
                    self.profiles = profiles
                    updateAccounts()
                }
                for account in accounts { refresh(account) }
                do { try await Task.sleep(for: .seconds(Self.refreshInterval)) } catch { return }
            }
        }
    }

    func accounts(for provider: AIUsageProvider) -> [AIUsageAccount] {
        accounts.filter { $0.provider == provider }
    }

    func refresh(_ provider: AIUsageProvider, force: Bool = false, allowPrompt: Bool = false) {
        for account in accounts(for: provider) { refresh(account, force: force, allowPrompt: allowPrompt) }
    }

    /// Keeps cards, readings and alerts only for enabled providers and profiles still in the registry.
    private func updateAccounts() {
        let previous = Set(accounts)
        accounts = AIUsageAccount.all(profiles: profiles).filter { enabledProviders.contains($0.provider) }
        let current = Set(accounts)
        for account in previous.subtracting(current) {
            tasks[account]?.cancel()
            tasks[account] = nil
            refreshing.remove(account)
            snapshots[account] = nil
            alertQueue.removeAll { $0.account == account }
            if quotaAlert?.account == account {
                alertTask?.cancel()
                quotaAlert = nil
                presentNextAlert()
            }
        }
        Task { [service] in await service.retainAccounts(current) }
        for account in current.subtracting(previous) { refresh(account, force: true) }
    }

    /// Preview uses the normal presentation queue without changing quota or warning history.
    func triggerQuotaHUDTest(_ provider: AIUsageProvider) {
        guard showsQuotaHUD, enabledProviders.contains(provider) else { return }
        alertQueue.append(
            .init(
                account: AIUsageAccount(provider: provider), window: .session,
                usedPercent: AIQuotaAlertPolicy.threshold))
        presentNextAlert()
    }

    private func presentNextAlert() {
        guard quotaAlert == nil, !alertQueue.isEmpty else { return }
        quotaAlert = alertQueue.removeFirst()
        alertTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(AIQuotaAlertPolicy.presentationDuration)) } catch { return }
            guard let self else { return }
            quotaAlert = nil
            presentNextAlert()
        }
    }

    deinit {
        backgroundTask?.cancel()
        alertTask?.cancel()
        for task in tasks.values { task.cancel() }
    }

    func refresh(_ account: AIUsageAccount, force: Bool = false, allowPrompt: Bool = false) {
        guard accounts.contains(account), !refreshing.contains(account) else { return }
        if !force, let last = snapshots[account]?.updatedAt,
            Date().timeIntervalSince(last) < Self.refreshInterval
        {
            return
        }
        refreshing.insert(account)
        tasks[account] = Task { [weak self, service] in
            let snapshot = await service.snapshot(
                account, allowPrompt: allowPrompt, now: Date(), calendar: .current)
            guard let self, !Task.isCancelled else { return }
            snapshots[account] = snapshot
            if showsQuotaHUD {
                alertQueue.append(contentsOf: alertPolicy.alerts(account: account, snapshot: snapshot, now: Date()))
                presentNextAlert()
            }
            refreshing.remove(account)
            tasks[account] = nil
        }
    }
}
