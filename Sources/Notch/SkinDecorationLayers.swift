// Skin decorations: our own drawings (not in Atoll), no image assets.

import AppKit
import QuartzCore

/// Builds a decoration as Core Animation layers from `SkinDecorationGeometry`:
/// still parts drawn once, moving parts animated by keyframes that the render
/// server plays. The app does no work per frame, where a `Canvas` in a
/// `TimelineView` redrew everything and made every frame commit the window's
/// whole layer tree, Lottie layers included.
///
/// Layers expect a y-down parent (`SkinDecorationView` flips it).
enum SkinDecorationLayers {
    /// Keyframes per period; the render server interpolates between them.
    private static let keyframeCount = 60

    /// - Parameter frameRate: frames per second asked of the render server;
    ///   nil builds the decoration at rest (Reduce Motion).
    static func make(_ decoration: SkinDecoration, shapeSize: CGSize, frameRate: Float?) -> [CALayer] {
        let island = SkinDecorationGeometry.island(for: shapeSize)
        let animator = Animator(frameRate: frameRate)
        switch decoration {
        case .vines: return vines(island: island, animator: animator)
        case .lights: return lights(island: island, animator: animator)
        case .blossoms: return blossoms(island: island, animator: animator)
        }
    }

    // MARK: Vines

    private static let leafDark = NSColor(red: 0.16, green: 0.5, blue: 0.2, alpha: 1).cgColor
    private static let leafLight = NSColor(red: 0.42, green: 0.78, blue: 0.3, alpha: 1).cgColor
    private static let stem = NSColor(red: 0.2, green: 0.38, blue: 0.14, alpha: 1).cgColor

    private static func vines(island: CGRect, animator: Animator) -> [CALayer] {
        typealias Geometry = SkinDecorationGeometry
        var layers: [CALayer] = [stroke(Geometry.edgeVine(island: island).cgPath, color: stem, width: 2)]
        layers += Geometry.edgeLeaves(island: island).map { leaf in
            let holder = CALayer()
            holder.position = leaf.base
            holder.setValue(leaf.angle, forKeyPath: "transform.rotation.z")
            holder.addSublayer(fluttering(leaf, animator: animator))
            return holder
        }
        let swayPeriod = 2 * .pi / Geometry.swaySpeed
        let times = animator.sampleTimes(period: swayPeriod)
        for index in Geometry.strands.indices {
            let strand = stroke(Geometry.strand(index, island: island, time: 0).cgPath, color: stem, width: 1.4)
            animator.animate(
                strand, keyPath: "path", period: swayPeriod,
                values: times.map { Geometry.strand(index, island: island, time: $0).cgPath })
            layers.append(strand)
            // Each leaf rides the swaying strand (holder) and flutters on it.
            let poses = times.map { Geometry.strandLeaves(index, island: island, time: $0) }
            for (leafIndex, leaf) in Geometry.strandLeaves(index, island: island, time: 0).enumerated() {
                let holder = CALayer()
                holder.position = leaf.base
                holder.setValue(leaf.angle, forKeyPath: "transform.rotation.z")
                animator.animate(
                    holder, keyPath: "position", period: swayPeriod,
                    values: poses.map { NSValue(point: $0[leafIndex].base) })
                animator.animate(
                    holder, keyPath: "transform.rotation.z", period: swayPeriod,
                    values: poses.map { $0[leafIndex].angle })
                holder.addSublayer(fluttering(leaf, animator: animator))
                layers.append(holder)
            }
        }
        return layers
    }

    /// A gradient leaf with a vein, its base on its holder's origin,
    /// fluttering about it.
    private static func fluttering(_ leaf: SkinDecorationGeometry.Leaf, animator: Animator) -> CALayer {
        let width = leaf.width
        let height = leaf.height
        let shape = CGMutablePath()
        shape.move(to: CGPoint(x: 0, y: height / 2))
        shape.addQuadCurve(to: CGPoint(x: width, y: height / 2), control: CGPoint(x: width / 2, y: -height / 2))
        shape.addQuadCurve(to: CGPoint(x: 0, y: height / 2), control: CGPoint(x: width / 2, y: height * 1.5))

        let leafLayer = CALayer()
        leafLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        leafLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        leafLayer.position = .zero
        let fill = CAGradientLayer()
        fill.frame = leafLayer.bounds
        fill.colors = [leafDark, leafLight]
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        let mask = CAShapeLayer()
        mask.path = shape
        fill.mask = mask
        leafLayer.addSublayer(fill)
        let vein = CGMutablePath()
        vein.move(to: CGPoint(x: width * 0.1, y: height / 2))
        vein.addLine(to: CGPoint(x: width * 0.85, y: height / 2))
        leafLayer.addSublayer(stroke(vein, color: stem.copy(alpha: 0.6) ?? stem, width: 0.5))
        // Only the transform changes: draw the leaf once.
        leafLayer.shouldRasterize = true

        let period = 2 * .pi / SkinDecorationGeometry.flutterSpeed
        animator.animate(
            leafLayer, keyPath: "transform.rotation.z", period: period,
            values: animator.sampleTimes(period: period).map {
                sin($0 * SkinDecorationGeometry.flutterSpeed + leaf.flutterPhase)
                    * SkinDecorationGeometry.flutterAmplitude
            })
        return leafLayer
    }

    // MARK: Christmas lights

    private static let bulbColors: [NSColor] = [
        NSColor(red: 1, green: 0.25, blue: 0.25, alpha: 1), NSColor(red: 0.25, green: 0.9, blue: 0.4, alpha: 1),
        NSColor(red: 1, green: 0.82, blue: 0.2, alpha: 1), NSColor(red: 0.3, green: 0.6, blue: 1, alpha: 1),
        NSColor(red: 1, green: 0.45, blue: 0.85, alpha: 1),
    ]
    private static let wire = NSColor(red: 0.12, green: 0.25, blue: 0.12, alpha: 1).cgColor

    private static func lights(island: CGRect, animator: Animator) -> [CALayer] {
        let wirePath = CGMutablePath()
        for piece in SkinDecorationGeometry.lightsWire(island: island) { wirePath.addPath(piece.cgPath) }
        var layers: [CALayer] = [stroke(wirePath, color: wire, width: 1.3)]
        let period = 2 * .pi / SkinDecorationGeometry.twinkleSpeed
        let times = animator.sampleTimes(period: period)
        for (index, bulb) in SkinDecorationGeometry.bulbs(island: island).enumerated() {
            let color = bulbColors[index % bulbColors.count]
            let twinkle = times.map { 0.55 + 0.45 * sin($0 * SkinDecorationGeometry.twinkleSpeed + bulb.twinklePhase) }
            let holder = CALayer()
            holder.position = bulb.point
            holder.setValue(bulb.angle, forKeyPath: "transform.rotation.z")

            let glow = CAGradientLayer()
            glow.type = .radial
            glow.frame = CGRect(x: -8, y: -2, width: 16, height: 18)
            glow.colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor]
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 0.5 + 9.0 / 16, y: 0.5 + 9.0 / 18)
            glow.opacity = Float(twinkle[0])
            animator.animate(glow, keyPath: "opacity", period: period, values: twinkle)
            holder.addSublayer(glow)

            holder.addSublayer(
                fill(
                    CGPath(
                        roundedRect: CGRect(x: -1.8, y: 0, width: 3.6, height: 3), cornerWidth: 0.8, cornerHeight: 0.8,
                        transform: nil),
                    color: NSColor(white: 0.35, alpha: 1).cgColor))
            let glass = fill(
                CGPath(ellipseIn: CGRect(x: -2.8, y: 2.4, width: 5.6, height: 7.5), transform: nil),
                color: color.cgColor)
            glass.opacity = Float(0.45 + 0.55 * twinkle[0])
            animator.animate(glass, keyPath: "opacity", period: period, values: twinkle.map { 0.45 + 0.55 * $0 })
            holder.addSublayer(glass)
            let shine = fill(
                CGPath(ellipseIn: CGRect(x: -1.2, y: 3.6, width: 1.6, height: 2.4), transform: nil),
                color: NSColor(white: 1, alpha: 0.7).cgColor)
            shine.opacity = Float(twinkle[0])
            animator.animate(shine, keyPath: "opacity", period: period, values: twinkle)
            holder.addSublayer(shine)
            layers.append(holder)
        }
        return layers
    }

    // MARK: Sakura

    private static let petalPink = NSColor(red: 1, green: 0.72, blue: 0.8, alpha: 1)
    private static let petalDeep = NSColor(red: 0.96, green: 0.5, blue: 0.64, alpha: 1)
    private static let bark = NSColor(red: 0.36, green: 0.22, blue: 0.16, alpha: 1).cgColor
    private static let pollen = NSColor(red: 1, green: 0.88, blue: 0.4, alpha: 1).cgColor

    private static func blossoms(island: CGRect, animator: Animator) -> [CALayer] {
        let (twig, shoot) = SkinDecorationGeometry.twig(island: island)
        var layers: [CALayer] = [
            stroke(twig.cgPath, color: bark, width: 2.2), stroke(shoot.cgPath, color: bark, width: 1.5),
        ]
        let wobblePeriod = 2 * .pi / SkinDecorationGeometry.wobbleSpeed
        for flower in SkinDecorationGeometry.flowers(island: island) {
            let layer = flowerLayer(size: flower.size)
            layer.position = flower.point
            layer.setValue(flower.rotation, forKeyPath: "transform.rotation.z")
            if let phase = flower.wobblePhase {
                animator.animate(
                    layer, keyPath: "transform.rotation.z", period: wobblePeriod,
                    values: animator.sampleTimes(period: wobblePeriod).map {
                        flower.rotation + sin($0 * SkinDecorationGeometry.wobbleSpeed + phase)
                            * SkinDecorationGeometry.wobbleAmplitude
                    })
            }
            layers.append(layer)
        }
        for index in 0..<SkinDecorationGeometry.Petal.count {
            layers.append(fallingPetal(SkinDecorationGeometry.Petal(index: index), island: island, animator: animator))
        }
        return layers
    }

    private static func petalPath(size: CGFloat) -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: size))
        path.addQuadCurve(to: CGPoint(x: -size * 0.3, y: -size), control: CGPoint(x: -size, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -size * 0.7))
        path.addLine(to: CGPoint(x: size * 0.3, y: -size))
        path.addQuadCurve(to: CGPoint(x: 0, y: size), control: CGPoint(x: size, y: 0))
        return path
    }

    /// Five petals around a two-tone centre, centred on the layer's origin.
    private static func flowerLayer(size: CGFloat) -> CALayer {
        let flower = CALayer()
        for (alpha, petals) in [(1.0, [0, 2, 4]), (0.9, [1, 3])] {
            let path = CGMutablePath()
            for petal in petals {
                let placement = CGAffineTransform(translationX: 0, y: -size * 0.9)
                    .concatenating(CGAffineTransform(rotationAngle: CGFloat(petal) * 72 * .pi / 180))
                path.addPath(petalPath(size: size * 0.75), transform: placement)
            }
            flower.addSublayer(fill(path, color: petalPink.withAlphaComponent(alpha).cgColor))
        }
        for (radius, color) in [(size * 0.32, petalDeep.cgColor), (size * 0.14, pollen)] {
            flower.addSublayer(
                fill(
                    CGPath(
                        ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
                        transform: nil),
                    color: color))
        }
        return flower
    }

    private static func fallingPetal(
        _ petal: SkinDecorationGeometry.Petal, island: CGRect, animator: Animator
    ) -> CALayer {
        let size = SkinDecorationGeometry.Petal.size
        let layer = CAGradientLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: size * 2, height: size * 2)
        layer.colors = [petalPink.cgColor, petalDeep.cgColor]
        // From y = -4 to y = 4 around the centre.
        layer.startPoint = CGPoint(x: 0.5, y: (size - 4) / (size * 2))
        layer.endPoint = CGPoint(x: 0.5, y: (size + 4) / (size * 2))
        let mask = CAShapeLayer()
        mask.path = petalPath(size: size).copy(using: [CGAffineTransform(translationX: size, y: size)])
        layer.mask = mask
        layer.shouldRasterize = true

        let offset = petal.startOffset
        // Where the petal is at time 0, the pose held with Reduce Motion.
        let rest = petal.state(progress: offset / petal.period, island: island)
        layer.position = rest.center
        layer.opacity = Float(rest.opacity)
        layer.setAffineTransform(
            CGAffineTransform(scaleX: 1, y: rest.scaleY).concatenating(CGAffineTransform(rotationAngle: rest.rotation)))
        let states = animator.sampleProgress().map { petal.state(progress: $0, island: island) }
        animator.animate(
            layer, keyPath: "position", period: petal.period, values: states.map { NSValue(point: $0.center) },
            timeOffset: offset)
        animator.animate(
            layer, keyPath: "transform", period: petal.period,
            values: states.map { state in
                NSValue(
                    caTransform3D: CATransform3DMakeAffineTransform(
                        CGAffineTransform(scaleX: 1, y: state.scaleY)
                            .concatenating(CGAffineTransform(rotationAngle: state.rotation))))
            }, timeOffset: offset)
        animator.animate(
            layer, keyPath: "opacity", period: petal.period, values: states.map { Float($0.opacity) },
            timeOffset: offset)
        return layer
    }

    // MARK: Shapes

    private static func stroke(_ path: CGPath, color: CGColor, width: CGFloat) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.strokeColor = color
        layer.fillColor = nil
        layer.lineWidth = width
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    private static func fill(_ path: CGPath, color: CGColor) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = color
        return layer
    }

    // MARK: Animation

    /// Adds looping keyframe animations at one frame rate, or none at all.
    private struct Animator {
        let frameRate: Float?

        /// Times (seconds) of the keyframes over one period, both ends
        /// included so the loop closes.
        func sampleTimes(period: Double) -> [Double] {
            sampleProgress().map { $0 * period }
        }

        func sampleProgress() -> [Double] {
            (0...keyframeCount).map { Double($0) / Double(keyframeCount) }
        }

        func animate(_ layer: CALayer, keyPath: String, period: Double, values: [Any], timeOffset: Double = 0) {
            guard let frameRate else { return }
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.duration = period
            animation.timeOffset = timeOffset
            animation.repeatCount = .infinity
            animation.calculationMode = .linear
            animation.isRemovedOnCompletion = false
            animation.preferredFrameRateRange = CAFrameRateRange(
                minimum: frameRate, maximum: frameRate, preferred: frameRate)
            layer.add(animation, forKey: keyPath)
        }
    }
}
