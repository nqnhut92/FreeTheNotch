// Adapted from CodeNotch (MIT): Sources/Sessions/CodexActivityMonitor.swift,
// ClaudeTranscript.swift and ProcessLiveness.swift. See THIRD_PARTY_NOTICES.md.

import Darwin
import Foundation

/// All file and process inspection stays off the main actor. Only changed tails are decoded.
actor AIActivityReader {
    private struct Cached {
        let modified: Date
        let size: Int
        let turn: AIActivityParser.Turn?
        let isHelper: Bool
    }
    private let roots: [AIUsageProvider: URL]
    private let claudeSessions: URL
    private var cache: [URL: Cached] = [:]
    private var candidates: [AIUsageProvider: [URL]] = [:]
    private var lastDiscovery = Date.distantPast
    private static let tailBytes = 1024 * 1024
    private static let discoveryInterval: TimeInterval = 15
    private static let discoveryLookback: TimeInterval = 24 * 3600
    private static let metadataBytes = 64 * 1024
    private static let processReuseTolerance: TimeInterval = 5 * 60
    private static let processListPadding = 16
    private static let descriptorListPadding = 8

    init(roots: [AIUsageProvider: URL], claudeSessions: URL) {
        self.roots = roots
        self.claudeSessions = claudeSessions
    }

    func read(
        providers: Set<AIUsageProvider>, now: Date, openCodexFiles: Set<URL>? = nil,
        processLiveness: (@Sendable (Int32, Date?) -> Bool)? = nil
    ) -> [AIActivity] {
        let open =
            providers.contains(.codex)
            ? (openCodexFiles.map { Set($0.map { $0.resolvingSymlinksInPath() }) } ?? openCodexRollouts()) : []
        if now.timeIntervalSince(lastDiscovery) >= Self.discoveryInterval {
            lastDiscovery = now
            for provider in providers {
                guard let root = roots[provider] else { continue }
                let files = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
                candidates[provider] = (files?.compactMap { $0 as? URL } ?? []).filter {
                    guard $0.pathExtension == "jsonl",
                        let modified = try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                            .contentModificationDate
                    else { return false }
                    return now.timeIntervalSince(modified) < Self.discoveryLookback
                }.map { $0.resolvingSymlinksInPath() }
            }
        }
        candidates[.codex] = Array(Set(candidates[.codex] ?? []).union(open))
        var results: [String: AIActivity] = [:]
        var retained: Set<URL> = []
        var transcriptStates: [String: AIActivity] = [:]
        for provider in providers {
            let paths = Set(candidates[provider] ?? []).union(provider == .codex ? open : [])
            for url in paths {
                retained.insert(url)
                guard let cached = cachedActivity(at: url, provider: provider) else { continue }
                let modified = cached.modified
                guard !cached.isHelper else { continue }
                let live = open.contains(url) || now.timeIntervalSince(modified) < AIActivity.recentWriteInterval
                // CodeNotch's bounded-tail fallback: a lifecycle start can be megabytes behind ongoing writes.
                let inferred = provider == .codex && live ? AIActivityParser.Turn(state: .working, timestamp: nil) : nil
                guard let turn = cached.turn ?? inferred else { continue }
                let activity = AIActivity(
                    id: provider.rawValue + "." + url.deletingPathExtension().lastPathComponent,
                    provider: provider, state: turn.state, changedAt: turn.timestamp ?? modified)
                transcriptStates[activity.id] = activity
                if activity.isVisible(at: now, isLive: live) { results[activity.id] = activity }
            }
        }
        if providers.contains(.claude) {
            let files =
                (try? FileManager.default.contentsOfDirectory(
                    at: claudeSessions, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for url in files where url.pathExtension == "json" {
                guard let data = Self.tail(url, bytes: Self.metadataBytes),
                    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                    let pid = json["pid"] as? Int32, pid > 0,
                    (processLiveness ?? { Self.isAlive(pid: $0, started: $1) })(
                        pid, (json["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) })
                else { continue }
                if let record = AIActivityParser.claudeRegistry(data, fallback: now) {
                    let id = record.activity.id
                    if record.activity.state == .idle {
                        if results[id]?.state != .completed { results[id] = nil }
                        continue
                    }
                    if let transcript = transcriptStates[id],
                        transcript.state == .stopped || transcript.state == .completed,
                        transcript.changedAt >= record.activity.changedAt
                    {
                        continue
                    }
                    if record.activity.state == .waiting || results[id] == nil {
                        results[id] = record.activity
                    }
                } else if let id = json["sessionId"] as? String, let cwd = json["cwd"] as? String,
                    let projects = roots[.claude]
                {
                    let slug = String(cwd.map { $0 == "/" || $0 == "." ? "-" : $0 })
                    let transcript = projects.appendingPathComponent(slug).appendingPathComponent(id + ".jsonl")
                    retained.insert(transcript)
                    guard let cached = cachedActivity(at: transcript, provider: .claude),
                        let turn = cached.turn
                    else { continue }
                    let activity = AIActivity(
                        id: "claude." + id, provider: .claude, state: turn.state,
                        changedAt: turn.timestamp ?? cached.modified)
                    if activity.isVisible(at: now, isLive: true) { results[activity.id] = activity }
                }
            }
        }
        cache = cache.filter { retained.contains($0.key) }
        return results.values.sorted {
            if $0.state == .completed && $1.state != .completed { return false }
            if $1.state == .completed && $0.state != .completed { return true }
            return $0.changedAt == $1.changedAt ? $0.id < $1.id : $0.changedAt > $1.changedAt
        }
    }

    private func cachedActivity(at url: URL, provider: AIUsageProvider) -> Cached? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let modified = attributes[.modificationDate] as? Date,
            let size = attributes[.size] as? Int
        else { return nil }
        if let previous = cache[url], previous.modified == modified, previous.size == size { return previous }
        let turn = Self.tail(url, bytes: Self.tailBytes).flatMap {
            provider == .codex ? AIActivityParser.codex($0) : AIActivityParser.claude($0)
        }
        let helper = provider == .codex && Self.isCodexHelper(url)
        let reading = Cached(modified: modified, size: size, turn: turn, isHelper: helper)
        cache[url] = reading
        return reading
    }

    static func tail(_ url: URL, bytes: Int) -> Data? {
        guard bytes > 0 else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(bytes) ? end - UInt64(bytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        let expectedBytes = Int(end - start)
        var data = Data()
        while data.count < expectedBytes {
            guard let chunk = try? handle.read(upToCount: expectedBytes - data.count) else { return nil }
            guard !chunk.isEmpty else { break }
            data.append(chunk)
        }
        if start > 0, let newline = data.firstIndex(of: 10) { data.removeSubrange(...newline) }
        return data
    }

    private static func isCodexHelper(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.metadataBytes), let line = data.split(separator: 10).first,
            let record = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
            let payload = record["payload"] as? [String: Any],
            let source = payload["source"] as? [String: Any]
        else { return false }
        return source["subagent"] != nil
    }

    private static func isAlive(pid: Int32, started: Date?) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        guard let started else { return true }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return true }
        let time = info.kp_proc.p_starttime
        let actual = Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
        return abs(actual.timeIntervalSince(started)) < Self.processReuseTolerance
    }

    private func openCodexRollouts() -> Set<URL> {
        guard let root = roots[.codex] else { return [] }
        let prefix = root.resolvingSymlinksInPath().path + "/"
        let capacity = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) / MemoryLayout<pid_t>.stride + Self.processListPadding)
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard count > 0 else { return [] }
        var found = Set<URL>()
        for pid in pids.prefix(Int(count) / MemoryLayout<pid_t>.stride) where pid > 0 {
            var process = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &process, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else {
                continue
            }
            let name = withUnsafePointer(to: &process.pbi_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { String(cString: $0) }
            }
            guard name == "codex" else { continue }
            let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard bytes > 0 else { continue }
            var descriptors = [proc_fdinfo](
                repeating: proc_fdinfo(),
                count: Int(bytes) / MemoryLayout<proc_fdinfo>.stride + Self.descriptorListPadding)
            let read = proc_pidinfo(
                pid, PROC_PIDLISTFDS, 0, &descriptors, Int32(descriptors.count * MemoryLayout<proc_fdinfo>.stride))
            guard read > 0 else { continue }
            for descriptor in descriptors.prefix(Int(read) / MemoryLayout<proc_fdinfo>.stride)
            where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
                var info = vnode_fdinfowithpath()
                let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
                guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else {
                    continue
                }
                let path = withUnsafePointer(to: &info.pvip.vip_path) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
                }
                if path.hasPrefix(prefix), path.hasSuffix(".jsonl") { found.insert(URL(fileURLWithPath: path)) }
            }
        }
        return found
    }
}
