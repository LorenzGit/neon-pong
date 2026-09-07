import SpriteKit
import UIKit

// MARK: - Neon label

/// A text node with a neon bloom behind it.
///
/// Large display type uses a real gaussian blur; body copy stacks slightly
/// enlarged additive copies instead, because forty simultaneous CIGaussianBlur
/// passes is more than one screen should ask for.
///
/// The stacked copies are NOT scaled up. Scaling displaces every glyph in
/// proportion to its distance from the anchor, so on a short label it passes for
/// a halo but on a long one it reads as a legible second copy sitting outside
/// the first — and on a modal, spilling past the panel edge. The outward haze
/// comes from a stretched radial glow behind the text instead, which has no
/// geometry to double.
///
/// The bloom also sits at a negative zPosition: the view runs with
/// `ignoresSiblingOrder`, so without an explicit z the crisp glyphs can be drawn
/// over their own glow and the label silently loses its bloom.
final class NeonLabel: SKNode {

    private let crisp = SKLabelNode()
    private var bloomHost: SKEffectNode?
    private var bloomLabels: [SKLabelNode] = []
    /// Soft coloured haze behind the glyphs, sized to the text.
    private var haze: GlowSprite?

    private let style: Theme.TextStyle
    private var align: SKLabelHorizontalAlignmentMode = .center
    private var tint: UIColor
    /// Bloom strength, 0 disables the glow entirely.
    private let glowAlpha: CGFloat

    var text: String = "" {
        didSet { guard text != oldValue else { return }; applyText() }
    }

    var color: UIColor {
        get { tint }
        set { tint = newValue; applyText() }
    }

    /// Width of the rendered text, for laying out adjacent nodes.
    var contentWidth: CGFloat { crisp.frame.width }
    var contentHeight: CGFloat { crisp.frame.height }

    /// Only display-sized type is worth a real blur.
    private static func usesBlur(_ style: Theme.TextStyle) -> Bool {
        switch style {
        case .hero, .title, .score: return true
        default: return false
        }
    }

    /// Alpha of each stacked copy. All sit exactly on the crisp glyphs.
    private static let stackAlphas: [CGFloat] = [0.42, 0.30]

    init(_ text: String,
         style: Theme.TextStyle,
         color: UIColor = Theme.ink,
         align: SKLabelHorizontalAlignmentMode = .center,
         vertical: SKLabelVerticalAlignmentMode = .center,
         glow: CGFloat = 0.85,
         blurRadius: CGFloat? = nil) {
        self.style = style
        self.tint = color
        self.glowAlpha = glow
        super.init()

        crisp.horizontalAlignmentMode = align
        crisp.verticalAlignmentMode = vertical
        crisp.zPosition = 1
        self.align = align

        if glow > 0 {
            if Self.usesBlur(style) {
                let host = SKEffectNode()
                let radius = blurRadius ?? max(6, style.size * 0.16)
                host.filter = CIFilter(name: "CIGaussianBlur",
                                       parameters: ["inputRadius": radius])
                host.shouldEnableEffects = true
                host.blendMode = .add
                host.alpha = glow
                host.zPosition = 0
                let label = SKLabelNode()
                label.horizontalAlignmentMode = align
                label.verticalAlignmentMode = vertical
                host.addChild(label)
                bloomLabels.append(label)
                bloomHost = host
                addChild(host)
            } else {
                let haze = GlowSprite(color: color, diameter: 128,
                                      intensity: 0.34 * glow, falloff: 2.1)
                haze.zPosition = -1
                addChild(haze)
                self.haze = haze

                for alpha in Self.stackAlphas {
                    let label = SKLabelNode()
                    label.horizontalAlignmentMode = align
                    label.verticalAlignmentMode = vertical
                    label.blendMode = .add
                    label.alpha = alpha * glow
                    label.zPosition = 0
                    bloomLabels.append(label)
                    addChild(label)
                }
            }
        }
        addChild(crisp)

        self.text = text
        applyText()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyText() {
        crisp.attributedText = Self.attributed(text, style: style, color: tint)
        guard glowAlpha > 0 else { return }
        // The bloom copies are drawn slightly transparent so the additive pass
        // does not blow saturated colours out to white.
        let bloomText = Self.attributed(text, style: style,
                                        color: tint.withAlphaComponent(0.9))
        bloomLabels.forEach { $0.attributedText = bloomText }
        resizeHaze()
        // Force the effect node to re-render its cached texture.
        if let bloomHost {
            bloomHost.shouldRasterize = false
            bloomHost.shouldRasterize = true
        }
    }

    /// Stretches the haze over the rendered text, centred on it whatever the
    /// alignment.
    private func resizeHaze() {
        guard let haze else { return }
        let width = crisp.frame.width
        let height = crisp.frame.height
        guard width > 0, height > 0 else { return }
        haze.size = CGSize(width: width * 1.35 + height, height: height * 2.6)
        let centre: CGFloat
        switch align {
        case .left:  centre = width / 2
        case .right: centre = -width / 2
        default:     centre = 0
        }
        haze.position = CGPoint(x: centre, y: 0)
        haze.color = tint
    }

    static func attributed(_ string: String,
                           style: Theme.TextStyle,
                           color: UIColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: Theme.font(style),
            .foregroundColor: color,
            .kern: style.tracking
        ])
    }

    /// Scales the label down so it never runs past `width`. Returns self for
    /// chaining at the call site.
    @discardableResult
    func fitting(width: CGFloat) -> NeonLabel {
        let measured = contentWidth
        guard measured > width, measured > 0 else {
            setScale(1)
            return self
        }
        setScale(width / measured)
        return self
    }

    /// Quick attention pulse, used when a value changes.
    func pop(scale: CGFloat = 1.16, duration: TimeInterval = 0.22) {
        removeAction(forKey: "pop")
        setScale(1)
        run(.sequence([
            .scale(to: scale, duration: duration * 0.35),
            .scale(to: 1.0, duration: duration * 0.65)
        ]), withKey: "pop")
    }
}

// MARK: - Glow sprite

/// An additive radial light. Layered behind solid shapes to fake bloom cheaply.
final class GlowSprite: SKSpriteNode {
    init(color: UIColor, diameter: CGFloat, intensity: CGFloat = 0.9, falloff: CGFloat = 2.2) {
        let texture = TextureFactory.radialGlow(diameter: 256, color: .white, falloff: falloff)
        super.init(texture: texture, color: color, size: CGSize(width: diameter, height: diameter))
        colorBlendFactor = 1
        blendMode = .add
        alpha = intensity
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Panel

/// Rounded neon container used by every dialog, card and list.
final class PanelNode: SKNode {

    private let body: SKSpriteNode
    private let rim: GlowSprite
    let size: CGSize

    init(size: CGSize,
         corner: CGFloat = 28,
         fill: UIColor = Theme.panelFill,
         stroke: UIColor = Theme.panelStroke,
         lineWidth: CGFloat = 3,
         rimGlow: CGFloat = 0.22) {
        self.size = size
        body = SKSpriteNode(texture: TextureFactory.panel(size: size, corner: corner,
                                                          fill: fill, stroke: stroke,
                                                          lineWidth: lineWidth),
                            size: size)
        rim = GlowSprite(color: stroke, diameter: max(size.width, size.height) * 1.35,
                         intensity: rimGlow, falloff: 3.2)
        super.init()
        addChild(rim)
        addChild(body)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setStrokeColor(_ color: UIColor, fill: UIColor = Theme.panelFill,
                        corner: CGFloat = 28, lineWidth: CGFloat = 3) {
        body.texture = TextureFactory.panel(size: size, corner: corner,
                                            fill: fill, stroke: color, lineWidth: lineWidth)
        rim.color = color
    }
}

// MARK: - SF Symbol node

/// Renders an SF Symbol as a tinted sprite. Falls back to an empty node when the
/// symbol name is unavailable on this tvOS version.
final class SymbolNode: SKSpriteNode {

    init?(_ systemName: String, pointSize: CGFloat, color: UIColor,
          weight: UIImage.SymbolWeight = .semibold) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: config)
        else { return nil }

        // Flatten the tint into real pixels. `withTintColor` only resolves when
        // the image is drawn into a UIKit context, and SKTexture never gives it
        // one, which left every symbol rendering black.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let flattened = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
            symbol.withTintColor(color, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: symbol.size))
        }
        let texture = SKTexture(image: flattened)
        super.init(texture: texture, color: .clear, size: symbol.size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Layout helpers

extension SKNode {
    @discardableResult
    func placed(at point: CGPoint, z: CGFloat? = nil) -> Self {
        position = point
        if let z { zPosition = z }
        return self
    }

    func fadeIn(after delay: TimeInterval = 0, duration: TimeInterval = 0.25, to target: CGFloat = 1) {
        alpha = 0
        run(.sequence([.wait(forDuration: delay), .fadeAlpha(to: target, duration: duration)]))
    }

    /// Slide up into place while fading in. The standard entrance for panels.
    func riseIn(after delay: TimeInterval = 0, distance: CGFloat = 34,
                duration: TimeInterval = 0.32, to target: CGFloat = 1) {
        let final = position
        position = CGPoint(x: final.x, y: final.y - distance)
        alpha = 0
        run(.sequence([
            .wait(forDuration: delay),
            .group([
                .fadeAlpha(to: target, duration: duration),
                .move(to: final, duration: duration).eased()
            ])
        ]))
    }
}

extension SKAction {
    /// Ease-out on any action; SpriteKit defaults to linear.
    func eased(_ mode: SKActionTimingMode = .easeOut) -> SKAction {
        timingMode = mode
        return self
    }

    static func pulse(scale: CGFloat, duration: TimeInterval) -> SKAction {
        .repeatForever(.sequence([
            .scale(to: scale, duration: duration / 2).eased(.easeInEaseOut),
            .scale(to: 1.0, duration: duration / 2).eased(.easeInEaseOut)
        ]))
    }

    static func breathe(from: CGFloat, to: CGFloat, duration: TimeInterval) -> SKAction {
        .repeatForever(.sequence([
            .fadeAlpha(to: to, duration: duration / 2).eased(.easeInEaseOut),
            .fadeAlpha(to: from, duration: duration / 2).eased(.easeInEaseOut)
        ]))
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    var length: CGFloat { sqrt(x * x + y * y) }
    var normalized: CGPoint { let l = length; return l > 0 ? CGPoint(x: x / l, y: y / l) : .zero }
}
