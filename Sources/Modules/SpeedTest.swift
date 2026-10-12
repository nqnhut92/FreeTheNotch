import Foundation

// Internet speed test via Cloudflare's speed-test backend
// (speed.cloudflare.com). Measures latency (best of 5 HTTPS round trips),
// then a single-stream download and upload.
final class SpeedTest: ObservableObject {
    enum Phase: Equatable {
        case idle, testing, done, failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var latencyMs: Double?
    @Published private(set) var downMbps: Double?
    @Published private(set) var upMbps: Double?
    @Published private(set) var errorMessage: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    func run() {
        guard phase != .testing else { return }
        phase = .testing
        latencyMs = nil
        downMbps = nil
        upMbps = nil
        errorMessage = nil
        Task.detached { [weak self] in await self?.perform() }
    }

    private func perform() async {
        do {
            let latency = try await measureLatency()
            await MainActor.run { self.latencyMs = latency }
            let down = try await measureDownload()
            await MainActor.run { self.downMbps = down }
            let up = try await measureUpload()
            await MainActor.run {
                self.upMbps = up
                self.phase = .done
            }
        } catch {
            await MainActor.run {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.phase = .failed
            }
        }
    }

    private func measureLatency() async throws -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<5 {
            let start = Date()
            let (_, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw TestError.badResponse
            }
            best = min(best, Date().timeIntervalSince(start) * 1000)
        }
        return best
    }

    private func measureDownload() async throws -> Double {
        // 25 MB single stream.
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!
        let start = Date()
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw TestError.badResponse
        }
        guard let mbps = Self.megabitsPerSecond(bytes: data.count, seconds: Date().timeIntervalSince(start)) else {
            throw TestError.badResponse
        }
        return mbps
    }

    private func measureUpload() async throws -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__up")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = Data(repeating: 0, count: 8_000_000)
        let start = Date()
        let (_, response) = try await session.upload(for: request, from: body)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TestError.badResponse
        }
        guard let mbps = Self.megabitsPerSecond(bytes: body.count, seconds: Date().timeIntervalSince(start)) else {
            throw TestError.badResponse
        }
        return mbps
    }

    /// Decimal megabits per second, as speed tests report them; nil for a
    /// transfer that took no measurable time.
    static func megabitsPerSecond(bytes: Int, seconds: TimeInterval) -> Double? {
        guard seconds > 0 else { return nil }
        return Double(bytes) * 8 / seconds / 1_000_000
    }

    private enum TestError: LocalizedError {
        case badResponse
        var errorDescription: String? { "Speed test failed" }
    }
}
