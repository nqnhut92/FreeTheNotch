// Adapted from CodeNotch (MIT): Sources/Providers/ClaudeDesktopUsageCache.swift.
// Reads only usage responses, with bounded header/body reads and zstd decoding.

import Foundation

/// The most recently viewed Claude Desktop usage, dated rather than presented as a live OAuth reading.
struct ClaudeDesktopUsageCache {
    let directory: URL
    let profileURL: URL?
    private static let headerBytes = 24
    private static let maximumKeyBytes = 8192
    private static let maximumEntryBytes = 512 * 1024
    private static let maximumBodyBytes = 256 * 1024
    private static let maximumEntries = 400
    private static let maximumFutureSkew: TimeInterval = 30 * 60

    init(
        profileURL: URL? = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"),
        directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/Claude/Cache/Cache_Data")
    ) {
        self.directory = directory
        self.profileURL = profileURL
    }

    func read(now: Date) -> AIUsageSnapshot? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys))
        else { return nil }
        let entries = files.compactMap { url -> (URL, Date)? in
            guard url.lastPathComponent.hasSuffix("_0"), let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true, let size = values.fileSize, size <= Self.maximumEntryBytes,
                let date = values.contentModificationDate
            else { return nil }
            return (url, date)
        }.sorted { $0.1 > $1.1 }.prefix(Self.maximumEntries)
        let profileData = profileURL.flatMap { try? Data(contentsOf: $0) }
        var latest: AIUsageSnapshot?
        for (file, modified) in entries {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            guard var header = try? handle.read(upToCount: Self.headerBytes), header.count == Self.headerBytes else {
                continue
            }
            let length = Int(Self.integer(Array(header), offset: 12, count: 4))
            guard length > 0, length <= Self.maximumKeyBytes,
                let keyBytes = try? handle.read(upToCount: length), keyBytes.count == length
            else { continue }
            header.append(keyBytes)
            guard Self.usageKey(in: header) != nil else { continue }
            do {
                try handle.seek(toOffset: 0)
                guard let data = try handle.read(upToCount: Self.maximumEntryBytes),
                    var reading = Self.parse(data, modifiedAt: modified, now: now, profileData: profileData)
                else { continue }
                reading.quotaSource = "Claude Desktop cache"
                if latest == nil
                    || (reading.quotaCapturedAt ?? .distantPast) > (latest?.quotaCapturedAt ?? .distantPast)
                {
                    latest = reading
                }
            } catch { continue }
        }
        return latest
    }

    static func usageKey(in data: Data) -> String? {
        let bytes = Array(data)
        guard bytes.count >= headerBytes, integer(bytes, offset: 0, count: 8) == 0xfcfb_6d1b_a772_5c30 else {
            return nil
        }
        let length = Int(integer(bytes, offset: 12, count: 4))
        guard length > 0, length <= maximumKeyBytes, headerBytes + length <= bytes.count,
            let key = String(bytes: bytes[headerBytes..<(headerBytes + length)], encoding: .utf8),
            let start = key.range(of: "https://"), let url = URL(string: String(key[start.lowerBound...])),
            url.host == "claude.ai", url.pathComponents.count == 5,
            url.pathComponents[1] == "api", url.pathComponents[2] == "organizations", url.pathComponents[4] == "usage"
        else { return nil }
        return key
    }

    static func parse(_ data: Data, modifiedAt: Date, now: Date, profileData: Data? = nil) -> AIUsageSnapshot? {
        guard data.count <= maximumEntryBytes, let key = usageKey(in: data) else { return nil }
        let start = headerBytes + key.utf8.count
        guard data.count > start + 4 else { return nil }
        let frame = Data(data.dropFirst(start))
        let decoded: (Data, Int)? = frame.withUnsafeBytes { source in
            let compressedSize = ZSTD_findFrameCompressedSize(source.baseAddress, source.count)
            guard ZSTD_isError(compressedSize) == 0, compressedSize > 0, compressedSize <= source.count else {
                return nil
            }
            var output = Data(count: maximumBodyBytes)
            let size = output.withUnsafeMutableBytes { destination in
                ZSTD_decompress(destination.baseAddress, destination.count, source.baseAddress, compressedSize)
            }
            guard ZSTD_isError(size) == 0, size > 0, size <= maximumBodyBytes else { return nil }
            output.count = size
            return (output, compressedSize)
        }
        guard let (body, size) = decoded,
            var snapshot = try? AIUsageQuotaParser.parse(body, provider: .claude, now: now),
            snapshot.sessionLimit != nil || snapshot.weekLimit != nil
        else { return nil }
        let trailer = String(decoding: frame.dropFirst(size), as: UTF8.self)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let captured =
            trailer.split(separator: "\0").compactMap { line -> Date? in
                guard line.lowercased().hasPrefix("date:") else { return nil }
                return formatter.date(from: String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }.first ?? modifiedAt
        guard captured.timeIntervalSince(now) < maximumFutureSkew else { return nil }
        if let profileData, let start = key.range(of: "https://"),
            let url = URL(string: String(key[start.lowerBound...]))
        {
            snapshot.identity = AIUsageCredentials.claudeIdentity(
                profileData, matchingOrganization: url.pathComponents[3])
        }
        snapshot.quotaCapturedAt = captured
        snapshot.quotaSource = "Claude Desktop cache"
        return snapshot
    }

    private static func integer(_ bytes: [UInt8], offset: Int, count: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in (0..<count).reversed() { value = value << 8 | UInt64(bytes[offset + index]) }
        return value
    }
}
