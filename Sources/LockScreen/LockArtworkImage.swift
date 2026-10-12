import CoreImage

/// The wallpaper made from an artwork: Atoll's blurred fill
/// (FullScreenArtworkWindowManager.encodeBlurredWallpaperPNG: radius 28 at
/// screen size, colour controls) with the artwork sharp, never bigger than
/// its own pixels and at most 34 % of the screen height, centred 36 % down
/// (the clock sits over its top, as on iOS), leaving room under it for
/// LockScreenArtworkControls above macOS's user picture. Feathered into
/// the fill. Atoll uses the raw artwork, which macOS stretches to the
/// screen and pixelates. Core Image; call `render` off the main thread.
enum LockArtworkImage {
    /// Artwork centre, from the top, and its largest side, as screen-height
    /// fractions. LockScreenLayout.artworkControlsTop places the controls
    /// under it.
    static let centerFromTop: CGFloat = 0.36
    static let maxSideFraction: CGFloat = 0.34
    /// The feathered edge eats this much of the artwork's shorter side on
    /// each side; the corners are rounded by `cornerFraction` of it.
    static let insetFraction: CGFloat = 0.08
    static let cornerFraction: CGFloat = 0.1
    /// Blur of the feathered edge, as a fraction of the shorter side.
    static let featherFraction: CGFloat = 0.07
    /// Atoll's fill blur radius at its reference width (a 1512 pt screen).
    static let fillBlurRadius: CGFloat = 28
    static let fillBlurReferenceWidth: CGFloat = 1512

    /// Shared: a CIContext is expensive to create, and render runs once per song.
    private static let context = CIContext(options: nil)

    /// The sharp artwork's rect on a canvas (pixels, from the top-left)
    /// and its shorter side.
    static func artRect(artworkSize: CGSize, canvas: CGSize) -> (rect: CGRect, side: CGFloat) {
        let short = min(artworkSize.width, artworkSize.height)
        guard short > 0, canvas.width > 0, canvas.height > 0 else { return (.zero, 0) }
        let side = min(short, canvas.height * maxSideFraction)
        let fit = side / short
        let size = CGSize(width: artworkSize.width * fit, height: artworkSize.height * fit)
        let rect = CGRect(
            x: (canvas.width - size.width) / 2, y: canvas.height * centerFromTop - size.height / 2,
            width: size.width, height: size.height)
        return (rect, side)
    }

    /// Where the sharp artwork shows (inside its feathered edge) on a
    /// screen, in points from the top-left, and its corner radius: a click
    /// there turns the artwork wallpaper off. `scale` is the canvas pixels
    /// per point `render` was given.
    static func visibleRect(artworkPixels: CGSize, screenSize: CGSize, scale: CGFloat) -> (
        rect: CGRect, cornerRadius: CGFloat
    ) {
        guard artworkPixels.width > 0, artworkPixels.height > 0, scale > 0 else { return (.zero, 0) }
        let canvas = CGSize(width: screenSize.width * scale, height: screenSize.height * scale)
        let (rect, side) = artRect(artworkSize: artworkPixels, canvas: canvas)
        let inset = rect.insetBy(dx: side * insetFraction, dy: side * insetFraction)
        return (
            CGRect(
                x: inset.minX / scale, y: inset.minY / scale,
                width: inset.width / scale, height: inset.height / scale),
            side * cornerFraction / scale
        )
    }

    /// The canvas for a screen: its size in pixels.
    static func canvas(pointSize: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: (pointSize.width * scale).rounded(), height: (pointSize.height * scale).rounded())
    }

    static func render(_ art: CGImage, canvas: CGSize) -> CGImage? {
        let rect = CGRect(origin: .zero, size: canvas)
        let source = CIImage(cgImage: art)
        let extent = source.extent
        guard extent.width > 0, extent.height > 0, canvas.width > 0, canvas.height > 0 else { return nil }

        let fill = max(canvas.width / extent.width, canvas.height / extent.height)
        let background =
            source
            .transformed(by: CGAffineTransform(scaleX: fill, y: fill))
            .transformed(
                by: CGAffineTransform(
                    translationX: (canvas.width - extent.width * fill) / 2,
                    y: (canvas.height - extent.height * fill) / 2)
            )
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: fillBlurRadius * canvas.width / fillBlurReferenceWidth]
            )
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 0.92,
                    kCIInputBrightnessKey: -0.03,
                    kCIInputContrastKey: 0.98,
                ]
            )
            .cropped(to: rect)

        let (topLeftRect, side) = artRect(artworkSize: extent.size, canvas: canvas)
        let fit = side / min(extent.width, extent.height)
        // Core Image's y runs up.
        let artRect = CGRect(
            x: topLeftRect.minX, y: canvas.height - topLeftRect.maxY,
            width: topLeftRect.width, height: topLeftRect.height)
        let foreground =
            source
            .transformed(by: CGAffineTransform(scaleX: fit, y: fit))
            .transformed(by: CGAffineTransform(translationX: artRect.minX, y: artRect.minY))

        guard
            let maskContext = CGContext(
                data: nil, width: Int(canvas.width), height: Int(canvas.height),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        maskContext.setFillColor(gray: 0, alpha: 1)
        maskContext.fill(rect)
        maskContext.setFillColor(gray: 1, alpha: 1)
        let inset = artRect.insetBy(dx: side * insetFraction, dy: side * insetFraction)
        let corner = side * cornerFraction
        maskContext.addPath(CGPath(roundedRect: inset, cornerWidth: corner, cornerHeight: corner, transform: nil))
        maskContext.fillPath()
        guard let maskImage = maskContext.makeImage() else { return nil }
        let feather = CIImage(cgImage: maskImage)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: side * featherFraction])
            .cropped(to: rect)

        let composed = foreground.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: feather,
            ])
        return context.createCGImage(composed, from: rect)
    }
}
