import SpriteKit
import UIKit

/// All particle work lives here. Emitters are built in code rather than .sks
/// files so their parameters are readable and tweakable next to their use.
enum Effects {

    // MARK: - Paddle and wall impacts

    /// A tight cone of sparks thrown off a paddle or wall hit.
    static func sparks(color: UIColor, direction: CGVector, power: CGFloat = 1) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = TextureFactory.spark(diameter: 64)
        emitter.particleBirthRate = 2600
        emitter.numParticlesToEmit = Int(26 * power)
        emitter.particleLifetime = 0.34
        emitter.particleLifetimeRange = 0.22
        emitter.emissionAngle = atan2(direction.dy, direction.dx)
        emitter.emissionAngleRange = .pi * 0.55
        emitter.particleSpeed = 620 * power
        emitter.particleSpeedRange = 380
        emitter.particleAlpha = 1
        emitter.particleAlphaSpeed = -3.0
        emitter.particleScale = 0.28 * power
        emitter.particleScaleRange = 0.16
        emitter.particleScaleSpeed = -0.55
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.yAcceleration = -260
        emitter.run(.sequence([.wait(forDuration: 0.9), .removeFromParent()]))
        return emitter
    }

    /// The big one: sparks, smoke and a shockwave, used when a goal is scored.
    static func explosion(color: UIColor, power: CGFloat = 1) -> SKNode {
        let container = SKNode()

        let core = SKEmitterNode()
        core.particleTexture = TextureFactory.spark(diameter: 64)
        core.particleBirthRate = 6000
        core.numParticlesToEmit = Int(70 * power)
        core.particleLifetime = 0.55
        core.particleLifetimeRange = 0.4
        core.emissionAngleRange = .pi * 2
        core.particleSpeed = 900 * power
        core.particleSpeedRange = 620
        core.particleAlpha = 1
        core.particleAlphaSpeed = -1.8
        core.particleScale = 0.42 * power
        core.particleScaleRange = 0.3
        core.particleScaleSpeed = -0.6
        core.particleColorBlendFactor = 1
        core.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [UIColor.white, color, color.withBrightness(0.45)],
            times: [0, 0.25, 1])
        core.particleBlendMode = .add
        container.addChild(core)

        let smoke = SKEmitterNode()
        smoke.particleTexture = TextureFactory.smoke(diameter: 96)
        smoke.particleBirthRate = 900
        smoke.numParticlesToEmit = Int(22 * power)
        smoke.particleLifetime = 1.1
        smoke.particleLifetimeRange = 0.6
        smoke.emissionAngleRange = .pi * 2
        smoke.particleSpeed = 240 * power
        smoke.particleSpeedRange = 190
        smoke.particleAlpha = 0.5
        smoke.particleAlphaSpeed = -0.5
        smoke.particleScale = 0.9 * power
        smoke.particleScaleRange = 0.5
        smoke.particleScaleSpeed = 0.9
        smoke.particleColor = color.withBrightness(0.55)
        smoke.particleColorBlendFactor = 1
        smoke.particleBlendMode = .alpha
        smoke.zPosition = -1
        container.addChild(smoke)

        container.addChild(shockwave(color: color, radius: 340 * power))
        container.run(.sequence([.wait(forDuration: 2.2), .removeFromParent()]))
        return container
    }

    /// Expanding ring that sells the force of an impact.
    static func shockwave(color: UIColor, radius: CGFloat, duration: TimeInterval = 0.5) -> SKNode {
        let ring = SKSpriteNode(texture: TextureFactory.ring(diameter: 512, thickness: 26),
                                color: color,
                                size: CGSize(width: radius * 2, height: radius * 2))
        ring.colorBlendFactor = 1
        ring.blendMode = .add
        ring.setScale(0.05)
        ring.run(.sequence([
            .group([
                .scale(to: 1, duration: duration).eased(.easeOut),
                .sequence([
                    .fadeAlpha(to: 0.95, duration: duration * 0.12),
                    .fadeAlpha(to: 0, duration: duration * 0.88)
                ])
            ]),
            .removeFromParent()
        ]))
        return ring
    }

    // MARK: - Ball trails

    /// Continuous comet trail welded to a ball.
    static func ballTrail(color: UIColor, target: SKNode) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = TextureFactory.radialGlow(diameter: 128, color: .white, falloff: 2.0)
        emitter.particleBirthRate = 260
        emitter.particleLifetime = 0.42
        emitter.particleLifetimeRange = 0.14
        emitter.particleAlpha = 0.75
        emitter.particleAlphaSpeed = -1.9
        emitter.particleScale = 0.34
        emitter.particleScaleSpeed = -0.7
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.particleSpeed = 0
        emitter.targetNode = target
        emitter.zPosition = -1
        return emitter
    }

    /// Hotter, angrier trail for the fireball modifier.
    static func fireTrail(target: SKNode) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = TextureFactory.smoke(diameter: 96)
        emitter.particleBirthRate = 420
        emitter.particleLifetime = 0.5
        emitter.particleLifetimeRange = 0.2
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -2.0
        emitter.particleScale = 0.5
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.5
        emitter.particleColorBlendFactor = 1
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [UIColor.white,
                             UIColor(hex: 0xFFD23A),
                             UIColor(hex: 0xFF5A1E),
                             UIColor(hex: 0x6A1400)],
            times: [0, 0.2, 0.55, 1])
        emitter.particleBlendMode = .add
        emitter.particleSpeed = 60
        emitter.particleSpeedRange = 90
        emitter.emissionAngleRange = .pi * 2
        emitter.targetNode = target
        emitter.zPosition = -1
        return emitter
    }

    // MARK: - Pickups and celebration

    /// Burst thrown when a power-up capsule is claimed.
    static func pickupBurst(color: UIColor) -> SKNode {
        let container = SKNode()
        let emitter = SKEmitterNode()
        emitter.particleTexture = TextureFactory.spark(diameter: 64)
        emitter.particleBirthRate = 3000
        emitter.numParticlesToEmit = 44
        emitter.particleLifetime = 0.5
        emitter.particleLifetimeRange = 0.3
        emitter.emissionAngleRange = .pi * 2
        emitter.particleSpeed = 560
        emitter.particleSpeedRange = 320
        emitter.particleAlpha = 1
        emitter.particleAlphaSpeed = -2.1
        emitter.particleScale = 0.3
        emitter.particleScaleRange = 0.18
        emitter.particleScaleSpeed = -0.5
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        container.addChild(emitter)
        container.addChild(shockwave(color: color, radius: 190, duration: 0.4))
        container.run(.sequence([.wait(forDuration: 1.4), .removeFromParent()]))
        return container
    }

    /// Falling neon confetti for the winner screen.
    static func confetti(width: CGFloat, colors: [UIColor]) -> SKNode {
        let container = SKNode()
        for color in colors {
            let emitter = SKEmitterNode()
            emitter.particleTexture = TextureFactory.confettiStrip()
            emitter.particleBirthRate = 7
            emitter.particleLifetime = 4.6
            emitter.particleLifetimeRange = 1.4
            emitter.particlePositionRange = CGVector(dx: width, dy: 40)
            emitter.emissionAngle = -.pi / 2
            emitter.emissionAngleRange = 0.5
            emitter.particleSpeed = 240
            emitter.particleSpeedRange = 170
            emitter.yAcceleration = -180
            emitter.particleAlpha = 0.8
            emitter.particleAlphaSpeed = -0.18
            emitter.particleScale = 0.62
            emitter.particleScaleRange = 0.28
            emitter.particleRotationRange = .pi * 2
            emitter.particleRotationSpeed = 3.4
            emitter.particleColor = color
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .add
            container.addChild(emitter)
        }
        return container
    }

    /// Slow drifting motes that keep the menus from feeling static.
    static func ambientDust(size: CGSize, color: UIColor) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = TextureFactory.radialGlow(diameter: 128, color: .white, falloff: 2.4)
        emitter.particleBirthRate = 9
        emitter.particleLifetime = 12
        emitter.particleLifetimeRange = 5
        emitter.particlePositionRange = CGVector(dx: size.width, dy: size.height)
        emitter.particleSpeed = 16
        emitter.particleSpeedRange = 14
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 0.16
        emitter.particleAlphaRange = 0.1
        emitter.particleScale = 0.14
        emitter.particleScaleRange = 0.1
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        // Pre-roll so the field is already populated on the first frame.
        emitter.advanceSimulationTime(12)
        return emitter
    }
}

// MARK: - Screen shake

/// Decaying positional shake applied to a container node each frame.
final class ScreenShake {

    private weak var node: SKNode?
    private let origin: CGPoint
    private var trauma: CGFloat = 0

    init(node: SKNode) {
        self.node = node
        self.origin = node.position
    }

    /// `amount` is 0...1. Repeated hits stack up to the cap.
    func add(_ amount: CGFloat) {
        guard SaveStore.shared.screenShakeEnabled else { return }
        trauma = min(1, trauma + amount)
    }

    func update(dt: CGFloat) {
        guard let node else { return }
        guard trauma > 0.001 else {
            if node.position != origin { node.position = origin }
            return
        }
        // Squaring the trauma makes small hits subtle and big hits violent.
        let shake = trauma * trauma
        let maxOffset: CGFloat = 46
        node.position = CGPoint(
            x: origin.x + .random(in: -1...1) * maxOffset * shake,
            y: origin.y + .random(in: -1...1) * maxOffset * shake)
        trauma = max(0, trauma - dt * 1.9)
    }
}
