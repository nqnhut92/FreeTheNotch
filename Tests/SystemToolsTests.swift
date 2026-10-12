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
