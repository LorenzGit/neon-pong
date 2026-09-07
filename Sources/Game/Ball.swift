import SpriteKit
import UIKit

/// A ball in play. Holds its own motion state and the modifiers a power-up can
/// stick onto it; the scene owns collision and scoring.
final class Ball: SKNode {

    var velocity = CGVector.zero
    let radius: CGFloat = Arena.ballRadius

    /// Who returned it last. Decides who claims a power-up it runs into.
    var lastHitBy: PlayerSlot?
    /// How many paddle hits this rally has seen.
    var rallyHits = 0

    /// FIREBALL: faster, hotter, and worth two points.
    private(set) var isFireball = false
    /// GHOST BALL: fades out on the opponent's half.
    var ghostOwner: PlayerSlot?
    /// MAGNET: bends towards the owner's paddle on their half.
    var magnetOwner: PlayerSlot?
    /// True for the extra balls spawned by MULTIBALL.
    var isExtra = false

    private let core: SKSpriteNode
    private let glow: GlowSprite
    private var trail: SKEmitterNode?
    private var fireTrail: SKEmitterNode?

    /// SKNode already defines `speed` as an action multiplier, so the ball's
    /// linear speed needs its own name.
    var currentSpeed: CGFloat { sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy) }

    init(trailTarget: SKNode) {
        core = SKSpriteNode(texture: TextureFactory.disc(diameter: 96, color: .white),
                            size: CGSize(width: radius * 2, height: radius * 2))
        glow = GlowSprite(color: .white, diameter: 190, intensity: 0.85, falloff: 2.4)
        super.init()
        addChild(glow)
        addChild(core)
        zPosition = 6

        let emitter = Effects.ballTrail(color: .white, target: trailTarget)
        addChild(emitter)
        trail = emitter
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Serving

    /// Launches from the centre towards `slot`'s side at a shallow angle.
    func serve(towards slot: PlayerSlot, speed: CGFloat) {
        position = CGPoint(x: Arena.centerX, y: Arena.centerY)
        // Keep the opening angle shallow so the first return is fair.
        let angle = CGFloat.random(in: -0.30...0.30)
        let direction: CGFloat = slot.isLeft ? -1 : 1
        velocity = CGVector(dx: cos(angle) * speed * direction, dy: sin(angle) * speed)
        rallyHits = 0
        lastHitBy = nil
        setScale(0.2)
        alpha = 0
        run(.group([
            .scale(to: 1, duration: 0.24).eased(.easeOut),
            .fadeIn(withDuration: 0.18)
        ]))
    }

    /// Multiball spawns fan out from an existing ball.
    func launch(from origin: CGPoint, angle: CGFloat, speed: CGFloat, lastHitBy: PlayerSlot?) {
        position = origin
        velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
        self.lastHitBy = lastHitBy
        isExtra = true
        setScale(0.1)
        run(.scale(to: 1, duration: 0.2).eased(.easeOut))
    }

    // MARK: - Modifiers

    func setFireball(_ on: Bool) {
        guard isFireball != on else { return }
        isFireball = on
        if on {
            trail?.particleBirthRate = 0
            let fire = Effects.fireTrail(target: parent ?? self)
            addChild(fire)
            fireTrail = fire
            core.color = UIColor(hex: 0xFFCE4A)
            core.colorBlendFactor = 1
            glow.color = UIColor(hex: 0xFF7A26)
            glow.setScale(1.35)
            core.run(.pulse(scale: 1.18, duration: 0.35), withKey: "firePulse")
        } else {
            fireTrail?.particleBirthRate = 0
            fireTrail?.run(.sequence([.wait(forDuration: 0.6), .removeFromParent()]))
            fireTrail = nil
            trail?.particleBirthRate = 260
            core.removeAction(forKey: "firePulse")
            core.setScale(1)
            core.colorBlendFactor = 0
            glow.color = .white
            glow.setScale(1)
        }
    }

    /// Tints the trail towards whoever last touched the ball, so you can read
    /// ownership at a glance during a scramble.
    func tintTrail(_ color: UIColor) {
        guard !isFireball else { return }
        trail?.particleColor = color
        glow.color = color.mixed(with: .white, 0.55)
    }

    /// Applies the GHOST BALL fade based on which half the ball is on.
    func updateGhostVisibility(dt: CGFloat) {
        guard let owner = ghostOwner else {
            if alpha < 1, action(forKey: "ghost") == nil { alpha = 1 }
            return
        }
        // Invisible on the victim's half, fully visible on the owner's.
        let victimIsLeft = owner.opponent.isLeft
        let onVictimHalf = victimIsLeft
            ? position.x < Arena.centerX
            : position.x > Arena.centerX
        let target: CGFloat = onVictimHalf ? 0.12 : 1.0
        alpha = damp(alpha, target, rate: 9, dt: dt)
    }

    func clearModifiers() {
        setFireball(false)
        ghostOwner = nil
        magnetOwner = nil
        alpha = 1
    }

    /// Removes the ball with a small implosion. Used when a multiball extra is
    /// cleaned up without conceding a point.
    func vanish() {
        removeAllActions()
        run(.sequence([
            .group([.scale(to: 0.1, duration: 0.16), .fadeOut(withDuration: 0.16)]),
            .removeFromParent()
        ]))
    }
}
