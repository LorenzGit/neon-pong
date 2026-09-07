import SpriteKit
import UIKit

/// One player's bat. Owns its own visuals, its size and speed modifiers, and the
/// optional shield that sits on its goal line.
final class Paddle: SKNode {

    let slot: PlayerSlot
    private let core: SKSpriteNode
    private let glow: GlowSprite
    private let shieldNode: SKSpriteNode
    private let shieldGlow: GlowSprite

    /// Multiplier applied to the base height by EXPAND / SHRINK RAY.
    var sizeScale: CGFloat = 1 {
        didSet { applySize() }
    }
    /// Multiplier applied to travel speed by DEEP FREEZE.
    var speedScale: CGFloat = 1

    /// Vertical velocity from the last frame, used to add spin to a return.
    private(set) var velocityY: CGFloat = 0

    /// True while a SHIELD pickup is still unspent.
    private(set) var hasShield = false

    private var baseHeight: CGFloat { Arena.paddleHeight }

    var height: CGFloat { baseHeight * sizeScale }
    var halfHeight: CGFloat { height / 2 }
    var centerY: CGFloat { position.y }

    /// Highest and lowest the paddle centre may sit.
    var minCenterY: CGFloat { Arena.minY + halfHeight }
    var maxCenterY: CGFloat { Arena.maxY - halfHeight }

    init(slot: PlayerSlot) {
        self.slot = slot
        let color = Theme.color(for: slot)

        core = SKSpriteNode(texture: TextureFactory.capsule(
            size: CGSize(width: Arena.paddleWidth * 2, height: Arena.paddleHeight * 2),
            color: color),
                            size: CGSize(width: Arena.paddleWidth, height: Arena.paddleHeight))
        glow = GlowSprite(color: color, diameter: 360, intensity: 0.55, falloff: 2.6)
        glow.xScale = 0.30
        glow.yScale = 0.85

        let shieldSize = CGSize(width: 14, height: Arena.field.height * 0.62)
        shieldNode = SKSpriteNode(texture: TextureFactory.capsule(size: CGSize(width: 28, height: 400),
                                                                 color: UIColor(hex: 0x7CC4FF)),
                                  size: shieldSize)
        shieldNode.alpha = 0
        shieldGlow = GlowSprite(color: UIColor(hex: 0x7CC4FF), diameter: 520, intensity: 0.0, falloff: 3.0)
        shieldGlow.xScale = 0.30
        shieldGlow.yScale = shieldSize.height / 520 * 1.2

        super.init()

        addChild(glow)
        addChild(core)
        position = CGPoint(x: Arena.paddleX(slot), y: Arena.centerY)
        applySize()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The shield lives on the goal line, not on the paddle, so it is parented
    /// to the arena instead of to this node.
    func attachShield(to parent: SKNode) {
        let x = Arena.goalLine(slot) + (slot.isLeft ? 16 : -16)
        shieldNode.position = CGPoint(x: x, y: Arena.centerY)
        shieldGlow.position = shieldNode.position
        shieldNode.zPosition = 4
        shieldGlow.zPosition = 3
        parent.addChild(shieldGlow)
        parent.addChild(shieldNode)
    }

    private func applySize() {
        let target = CGSize(width: Arena.paddleWidth, height: height)
        core.removeAction(forKey: "resize")
        core.run(.resize(toWidth: target.width, height: target.height, duration: 0.18).eased(),
                 withKey: "resize")
        glow.yScale = height / 360 * 1.35
        // Keep the paddle legal after a size change.
        position.y = clamp(position.y, minCenterY, maxCenterY)
    }

    // MARK: - Movement

    /// Steers the paddle for one frame.
    /// `axis` is velocity-style input, `absolute` an optional 0...1 target from a
    /// touch surface. Absolute wins when present because it is a direct mapping.
    func steer(axis: CGFloat, absolute: CGFloat?, dt: CGFloat) {
        let before = position.y
        let speed = Arena.paddleSpeed * speedScale

        if let absolute {
            let target = lerp(minCenterY, maxCenterY, absolute)
            // Smoothed rather than snapped, and still capped by the paddle's speed.
            let smoothed = damp(position.y, target, rate: 16, dt: dt)
            let step = clamp(smoothed - position.y, -speed * dt, speed * dt)
            position.y += step
        } else if axis != 0 {
            position.y += axis * speed * dt
        }

        position.y = clamp(position.y, minCenterY, maxCenterY)
        velocityY = dt > 0 ? (position.y - before) / dt : 0
    }

    /// Snaps to a position without producing spin. Used by the CPU and on reset.
    func moveTo(y: CGFloat, dt: CGFloat, maxSpeed: CGFloat) {
        let before = position.y
        let step = clamp(y - position.y, -maxSpeed * dt, maxSpeed * dt)
        position.y = clamp(position.y + step, minCenterY, maxCenterY)
        velocityY = dt > 0 ? (position.y - before) / dt : 0
    }

    func resetForServe() {
        removeAction(forKey: "hitFlash")
        run(.move(to: CGPoint(x: Arena.paddleX(slot), y: Arena.centerY), duration: 0.3).eased())
        velocityY = 0
    }

    // MARK: - Feedback

    /// Squash-and-stretch plus a flash when the ball comes off this paddle.
    func playHitFeedback(power: CGFloat) {
        core.removeAction(forKey: "hitFlash")
        let squash = SKAction.sequence([
            .group([
                .scaleX(to: 1 + 0.9 * power, duration: 0.05),
                .scaleY(to: 1 - 0.16 * power, duration: 0.05)
            ]),
            .group([
                .scaleX(to: 1, duration: 0.16).eased(.easeOut),
                .scaleY(to: 1, duration: 0.16).eased(.easeOut)
            ])
        ])
        core.run(squash, withKey: "hitFlash")

        glow.removeAction(forKey: "flash")
        glow.run(.sequence([
            .fadeAlpha(to: min(1, 0.55 + 0.6 * power), duration: 0.04),
            .fadeAlpha(to: 0.55, duration: 0.28)
        ]), withKey: "flash")
    }

    // MARK: - Shield

    func giveShield() {
        hasShield = true
        shieldNode.removeAllActions()
        shieldGlow.removeAllActions()
        shieldNode.run(.fadeAlpha(to: 0.55, duration: 0.25))
        shieldGlow.run(.fadeAlpha(to: 0.35, duration: 0.25))
        shieldNode.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.35, duration: 0.9).eased(.easeInEaseOut),
            .fadeAlpha(to: 0.6, duration: 0.9).eased(.easeInEaseOut)
        ])), withKey: "breathe")
    }

    /// Consumes the shield. Returns false when there was nothing to spend.
    @discardableResult
    func consumeShield() -> Bool {
        guard hasShield else { return false }
        hasShield = false
        shieldNode.removeAction(forKey: "breathe")
        shieldNode.run(.sequence([
            .fadeAlpha(to: 1, duration: 0.05),
            .fadeAlpha(to: 0, duration: 0.35)
        ]))
        shieldGlow.run(.sequence([
            .fadeAlpha(to: 0.9, duration: 0.05),
            .fadeAlpha(to: 0, duration: 0.35)
        ]))
        return true
    }

    /// Y position of the shield plane, for spawning its break effect.
    var shieldX: CGFloat { shieldNode.position.x }
}
