import CoreGraphics
import Testing

struct LockArtworkImageTests {
    private static let screen = CGSize(width: 1512, height: 982)

    private static func approximately(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.001 && abs(a.minY - b.minY) < 0.001
            && abs(a.width - b.width) < 0.001 && abs(a.height - b.height) < 0.001
    }

    @Test(arguments: [
        (CGSize.zero, CGFloat(2)),
        (CGSize(width: 0, height: 300), 2),
        (CGSize(width: 300, height: 300), 0),
    ])
    func nothingToHitWithoutAnArtworkOrScale(_ artwork: CGSize, scale: CGFloat) {
        let hit = LockArtworkImage.visibleRect(artworkPixels: artwork, screenSize: Self.screen, scale: scale)
        #expect(hit.rect == .zero)
        #expect(hit.cornerRadius == 0)
    }

    @Test func emptyArtworkHasNoRect() {
        let art = LockArtworkImage.artRect(artworkSize: .zero, canvas: CGSize(width: 100, height: 100))
        #expect(art.rect == .zero)
        #expect(art.side == 0)
    }

    /// A 300 px cover on a 2× 14" screen stays 300 px: never upscaled.
    @Test func smallCoverIsNeverUpscaled() {
        let canvas = LockArtworkImage.canvas(pointSize: Self.screen, scale: 2)
        #expect(canvas == CGSize(width: 3024, height: 1964))
        let art = LockArtworkImage.artRect(artworkSize: CGSize(width: 300, height: 300), canvas: canvas)
        #expect(art.side == 300)
        #expect(Self.approximately(art.rect, CGRect(x: 1362, y: 1964 * 0.36 - 150, width: 300, height: 300)))
    }

    /// A 3000 px cover is capped at 34 % of the canvas height.
    @Test func largeCoverIsCappedAtAThirdOfTheHeight() {
        let art = LockArtworkImage.artRect(
            artworkSize: CGSize(width: 3000, height: 3000), canvas: CGSize(width: 1000, height: 1000))
        #expect(abs(art.side - 340) < 0.001)
        #expect(Self.approximately(art.rect, CGRect(x: 330, y: 190, width: 340, height: 340)))
    }

    /// The shorter side decides; a wide cover keeps its proportions.
    @Test func nonSquareArtKeepsItsAspect() {
        let art = LockArtworkImage.artRect(
            artworkSize: CGSize(width: 600, height: 300), canvas: CGSize(width: 1000, height: 1000))
        #expect(art.side == 300)
        #expect(Self.approximately(art.rect, CGRect(x: 200, y: 210, width: 600, height: 300)))
    }

    /// The click target is the sharp artwork inside its 8 % feathered edge,
    /// in points, with the 10 % corner radius.
    @Test func visibleRectIsInsetAndInPoints() {
        let hit = LockArtworkImage.visibleRect(
            artworkPixels: CGSize(width: 300, height: 300), screenSize: Self.screen, scale: 2)
        let top = (1964 * 0.36 - 150 + 24) / 2
        #expect(Self.approximately(hit.rect, CGRect(x: 693, y: top, width: 126, height: 126)))
        #expect(abs(hit.cornerRadius - 15) < 0.001)
    }

    @Test func renderFillsTheCanvas() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        let art = try #require(context.makeImage())
        let image = try #require(LockArtworkImage.render(art, canvas: CGSize(width: 120, height: 80)))
        #expect(image.width == 120)
        #expect(image.height == 80)
        #expect(LockArtworkImage.render(art, canvas: .zero) == nil)
    }
}
