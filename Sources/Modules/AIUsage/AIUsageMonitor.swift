// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/LLMUsageManager.swift.

import Combine
import Foundation

/// Shared between displays; refreshes enabled providers once a minute, including while the notch is closed.
@MainActor
final class AIUsageMonitor: ObservableObject {
    @Published private(set) var snapshots: [AIUsageProvider: AIUsageSnapshot] = [:]
    @Published private(set) var refreshing = Set<AIUsageProvider>()
    @Published private(set) var quotaAlert: AIQuotaAlertPolicy.Alert?
    private var alertPolicy = AIQuotaAlertPolicy()
    private var alertQueue: [AIQuotaAlertPolicy.Alert] = []
    private var alertTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private var hudSubscription: AnyCancellable?
    private var showsQuotaHUD = true
    private let service: AIUsageService
    private var tasks: [AIUsageProvider: Task<Void, Never>] = [:]
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
            provider, allowPrompt in try await store.load(provider, allowPrompt: allowPrompt)
        }
        settingsSubscription = Publishers.CombineLatest(settings.$codexUsageEnabled, settings.$claudeUsageEnabled)
            .sink { [weak self] codex, claude in
                guard let self else { return }
                let previous = enabledProviders
                enabledProviders = Set(AIUsageProvider.allCases.filter { $0 == .codex ? codex : claude })
                for provider in AIUsageProvider.allCases where !enabledProviders.contains(provider) {
                    tasks[provider]?.cancel()
                    tasks[provider] = nil
                    refreshing.remove(provider)
                    snapshots[provider] = nil
                    alertQueue.removeAll { $0.provider == provider }
                    if quotaAlert?.provider == provider {
                        alertTask?.cancel()
                        quotaAlert = nil
                        presentNextAlert()
                    }
                }
                for provider in enabledProviders.subtracting(previous) { refresh(provider, force: true) }
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
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshEnabledProviders()
                do { try await Task.sleep(for: .seconds(Self.refreshInterval)) } catch { return }
            }
        }
    }

    private func refreshEnabledProviders() {
        for provider in enabledProviders { refresh(provider) }
    }

    /// Preview uses the normal presentation queue without changing quota or warning history.
    func triggerQuotaHUDTest(_ provider: AIUsageProvider) {
        guard showsQuotaHUD, enabledProviders.contains(provider) else { return }
        alertQueue.append(.init(provider: provider, window: .session, usedPercent: AIQuotaAlertPolicy.threshold))
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

    func refresh(_ provider: AIUsageProvider, force: Bool = false, allowPrompt: Bool = false) {
        guard enabledProviders.contains(provider), !refreshing.contains(provider) else { return }
        if !force, let last = snapshots[provider]?.updatedAt,
            Date().timeIntervalSince(last) < Self.refreshInterval
        {
            return
        }
        refreshing.insert(provider)
        tasks[provider] = Task { [weak self, service] in
            let snapshot = await service.snapshot(provider, allowPrompt: allowPrompt, now: Date(), calendar: .current)
            guard let self, !Task.isCancelled else { return }
            snapshots[provider] = snapshot
            if showsQuotaHUD {
                alertQueue.append(contentsOf: alertPolicy.alerts(provider: provider, snapshot: snapshot, now: Date()))
                presentNextAlert()
            }
            refreshing.remove(provider)
            tasks[provider] = nil
        }
    }
}
