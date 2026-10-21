import AppKit
import CoreImage
import Foundation
import Testing

struct SubprocessTests {
    @Test func returnsStandardOutputAndStatus() throws {
        let output = try #require(Subprocess.run("/bin/echo", arguments: ["hello", "world"], timeout: 5))
        #expect(output.status == 0)
        #expect(output.succeeded)
        #expect(!output.timedOut)
        #expect(output.text == "hello world\n")
    }

    @Test func reportsAFailingStatus() throws {
        let output = try #require(Subprocess.run("/usr/bin/false", timeout: 5))
        #expect(output.status == 1)
        #expect(!output.succeeded)
    }

    /// More than the ~64 KB pipe buffer: waiting before reading would deadlock.
    @Test func drainsOutputLargerThanThePipeBuffer() throws {
        let output = try #require(
            Subprocess.run("/usr/bin/head", arguments: ["-c", "300000", "/dev/zero"], timeout: 10))
        #expect(output.succeeded)
        #expect(output.data.count == 300_000)
    }

    @Test func stopsAToolThatRunsPastTheTimeout() throws {
        let started = Date()
        let output = try #require(Subprocess.run("/bin/sleep", arguments: ["30"], timeout: 0.5))
        #expect(output.timedOut)
        #expect(!output.succeeded)
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func missingToolCannotLaunch() {
        #expect(Subprocess.run("/nonexistent/tool", timeout: 1) == nil)
    }
}

struct DiskMonitorTests {
    @Test(arguments: [
        (String?.some("disk0s2"), String?.some("disk0")),
        ("disk3", "disk3"),
        ("disk10s1", "disk10"),
        ("disk3s1s1", "disk3"),
        ("disk", nil),
        ("nvme0", nil),
        (nil, nil),
    ])
    func physicalWholeDisk(_ identifier: String?, expected: String?) {
        #expect(DiskMonitor.physicalWholeDisk(identifier) == expected)
    }

    /// System Settings → Storage on a 994.66 GB disk: 403.8 GB used,
    /// 590.86 GB available, of which 241 GB is purgeable (raw free 349.86 GB).
    /// Counting purgeable space as used would give 644.8 GB, 65 %.
    @Test func purgeableSpaceCountsAsAvailableLikeSystemSettings() {
        let space = DiskSpace(total: 994_660_000_000, available: 590_860_000_000, rawFree: 349_860_000_000)
        #expect(space.used == 403_800_000_000)
        #expect(space.available == 590_860_000_000)
        #expect(space.purgeable == 241_000_000_000)
    }

    @Test func withoutARawFreeValueNothingIsPurgeable() {
        let space = DiskSpace(total: 500, available: 200, rawFree: nil)
        #expect(space == DiskSpace(total: 500, available: 200, rawFree: 200))
        #expect(space.purgeable == 0)
    }

    /// The sealed system snapshot can report more free space than its size.
    @Test func availableNeverExceedsTheTotal() {
        let space = DiskSpace(total: 500, available: 800, rawFree: 800)
        #expect(space.used == 0)
        #expect(space.available == 500)
    }
}

struct QRGeneratorTests {
    @Test func generatedCodeReadsBack() throws {
        let message = "https://github.com/ftn?q=Xin chào"
        let image = try #require(QRGenerator.makeQRCode(from: message, size: 240))
        #expect(abs(image.size.width - 240) < 0.01)
        let png = try #require(QRGenerator.pngData(for: image))
        let ciImage = try #require(CIImage(data: png))
        let detector = try #require(
            CIDetector(
                ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let decoded = detector.features(in: ciImage).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(decoded == [message])
    }
}
