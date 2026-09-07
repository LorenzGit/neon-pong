import SpriteKit
import UIKit

/// The floating capsule a ball can run into. Claimed by whoever last returned
/// that ball.
final class PowerUpNode: SKNode {

    let kind: PowerUpKind
    /// Collision radius, a little generous so hits feel fair at speed.
    let radius: CGFloat = 52

    private let ring: SKShapeNode
    private let plate: SKSpriteNode
    private let glow: GlowSprite
    private var claimed = false

    init(kind: PowerUpKind) {
        self.kind = kind
        let tint = kind.tint

        ring = SKShapeNode(circleOfRadius: radius)
        ring.strokeColor = tint
        ring.lineWidth = 4
        ring.glowWidth = 6
        ring.fillColor = UIColor(hex: 0x060B18, alpha: 0.85)

        plate = SKSpriteNode(texture: TextureFactory.disc(diameter: 128, color: tint),
                             size: CGSize(width: radius * 1.36, height: radius * 1.36))
        plate.alpha = 0.16

        glow = GlowSprite(color: tint, diameter: 300, intensity: 0.5, falloff: 2.6)

        super.init()
        zPosition = 5
        addChild(glow)
        addChild(ring)
        addChild(plate)

        if let symbol = SymbolNode(kind.symbol, pointSize: 42, color: .white, weight: .bold) {
            symbol.zPosition = 2
            addChild(symbol)
        } else {
            let fallback = NeonLabel(kind.glyphFallback, style: .heading, color: .white, glow: 0.6)
            fallback.zPosition = 2
            addChild(fallback)
        }

        // Entrance: pop in and settle.
        setScale(0)
        alpha = 0
        run(.group([
            .scale(to: 1, duration: 0.34).eased(.easeOut),
            .fadeIn(withDuration: 0.24)
        ]))

        // Idle: gentle bob plus a rotating outer ring so it reads as "live".
        run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 16, duration: 1.5).eased(.easeInEaseOut),
            .moveBy(x: 0, y: -16, duration: 1.5).eased(.easeInEaseOut)
        ])), withKey: "bob")
        ring.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 8)))
        glow.run(.breathe(from: 0.35, to: 0.7, duration: 1.6))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Starts a warning flash when the capsule is about to expire.
    func startExpiryWarning() {
        run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.25, duration: 0.22),
            .fadeAlpha(to: 1.0, duration: 0.22)
        ])), withKey: "expiring")
    }

    /// Marks the pickup as taken. Returns false if it was already claimed this
    /// frame, which stops two balls collecting the same capsule.
    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        removeAction(forKey: "bob")
        removeAction(forKey: "expiring")
        run(.sequence([
            .group([
                .scale(to: 1.7, duration: 0.18).eased(.easeOut),
                .fadeOut(withDuration: 0.18)
            ]),
            .removeFromParent()
        ]))
        return true
    }

    func expire() {
        guard !claimed else { return }
        claimed = true
        removeAllActions()
        run(.sequence([
            .group([.scale(to: 0.1, duration: 0.22), .fadeOut(withDuration: 0.22)]),
            .removeFromParent()
        ]))
    }

    var isClaimed: Bool { claimed }
}
