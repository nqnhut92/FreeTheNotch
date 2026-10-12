import Combine
import Foundation

/// Publishes agent lifecycle states separately from quota and token accounting.
@MainActor
final class AIActivityMonitor: ObservableObject {
    typealias ActivityLoader = @Sendable (Set<AIUsageProvider>, Date) async -> [AIActivity]

    @Published private(set) var activities: [AIActivity] = []
    private let pollingInterval: Duration
    private var polling: Task<Void, Never>?
    private var preview: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private static let previewWorkingDuration: Duration = .seconds(3)

    convenience init(settings: SettingsStore) {
        let directories = AIUsageDirectories(
            home: FileManager.default.homeDirectoryForCurrentUser, environment: ProcessInfo.processInfo.environment)
        let reader = AIActivityReader(roots: directories.logRoots, claudeSessions: directories.claudeSessions)
        self.init(settings: settings) { providers, now in
            await reader.read(providers: providers, now: now)
        }
    }

    init(
        settings: SettingsStore, pollingInterval: Duration = .seconds(2),
        loadActivities: @escaping ActivityLoader
    ) {
        self.pollingInterval = pollingInterval
        subscription = Publishers.CombineLatest3(
            settings.$aiLiveActivitiesEnabled, settings.$codexUsageEnabled, settings.$claudeUsageEnabled
        ).sink { [weak self] enabled, codex, claude in
            guard let self else { return }
            polling?.cancel()
            preview?.cancel()
            preview = nil
            activities = []
            let providers = Set(AIUsageProvider.allCases.filter { $0 == .codex ? codex : claude })
            guard enabled, !providers.isEmpty else { return }
            polling = Task { [weak self] in
                while !Task.isCancelled {
                    let found = await loadActivities(providers, Date())
                    guard let self, !Task.isCancelled else { return }
                    if preview == nil, activities != found { activities = found }
                    do { try await Task.sleep(for: pollingInterval) } catch { return }
                }
            }
        }
    }

    /// Exercises the same compact UI without creating a real provider session.
    func triggerTest(provider: AIUsageProvider) {
        preview?.cancel()
        let id = "preview." + provider.rawValue
        activities = [AIActivity(id: id, provider: provider, state: .working, changedAt: Date())]
        preview = Task { [weak self] in
            do { try await Task.sleep(for: Self.previewWorkingDuration) } catch { return }
            guard let self else { return }
            activities = [AIActivity(id: id, provider: provider, state: .completed, changedAt: Date())]
            do { try await Task.sleep(for: .seconds(AIActivity.completionDuration)) } catch { return }
            activities = []
            preview = nil
        }
    }

    deinit {
        polling?.cancel()
        preview?.cancel()
    }
}
