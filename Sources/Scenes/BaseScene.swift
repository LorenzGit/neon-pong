import SpriteKit
import UIKit

/// Shared plumbing for every screen: atmosphere, the CRT overlay, the toast
/// host, controller polling and Menu-button routing.
class BaseScene: SKScene, ControllerHubDelegate, AchievementTrackerDelegate {

    /// Everything that may be shaken by an impact.
    let world = SKNode()
    /// Fixed chrome: vignette, scanlines, toasts.
    let chrome = SKNode()

    private(set) var toasts: ToastHost!
    private var lastUpdateTime: TimeInterval = 0
    private(set) var sceneTime: TimeInterval = 0

    var hub: ControllerHub { ControllerHub.shared }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = Theme.background
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        removeAllChildren()
        addChild(world)
        addChild(chrome)
        chrome.zPosition = 800

        toasts = ToastHost(anchor: CGPoint(x: Theme.sceneSize.width / 2, y: Arena.toastY))
        chrome.addChild(toasts)

        buildAtmosphere()
        buildOverlay()

        hub.delegate = self
        AchievementTracker.shared.delegate = self

        build()
    }

    override func willMove(from view: SKView) {
        if hub.delegate === self { hub.delegate = nil }
        if AchievementTracker.shared.delegate === self { AchievementTracker.shared.delegate = nil }
    }

    /// Subclass entry point. Called once the shared chrome exists.
    func build() {}

    /// Per-frame hook with a clamped delta.
    func tick(dt: CGFloat) {}

    /// Menu navigation for this frame, aggregated across every controller.
    func handle(menu: MenuInput) {}

    /// Return true to consume the Menu / Back button. Returning false at the
    /// root screen lets tvOS take the user home, which the platform expects.
    func handleMenuButton() -> Bool { false }

    /// Single entry point for the Menu button, reached both from `UIPress` and
    /// from polling the pad. The hub gates the two so one press acts once, and
    /// so a press that goes unhandled at the root still reaches tvOS.
    @discardableResult
    func requestMenuButton() -> Bool {
        hub.gateMenuButton { self.handleMenuButton() }
    }

    // MARK: - Atmosphere

    /// Deep-space gradient, drifting motes and two slow colour washes. Subclasses
    /// that need the play field add it on top.
    private func buildAtmosphere() {
        let bg = SKSpriteNode(color: Theme.backgroundDeep, size: Theme.sceneSize)
        bg.position = CGPoint(x: Theme.sceneSize.width / 2, y: Theme.sceneSize.height / 2)
        bg.zPosition = -100
        world.addChild(bg)

        for (color, x, duration) in [(Theme.p1, CGFloat(360), 17.0),
                                     (Theme.p2, CGFloat(1560), 21.0)] {
            let wash = GlowSprite(color: color, diameter: 1500, intensity: 0.13, falloff: 2.6)
            wash.position = CGPoint(x: x, y: Theme.sceneSize.height * 0.52)
            wash.zPosition = -99
            wash.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 90, duration: duration / 2).eased(.easeInEaseOut),
                .moveBy(x: 0, y: -90, duration: duration / 2).eased(.easeInEaseOut)
            ])))
            wash.run(.breathe(from: 0.10, to: 0.19, duration: duration * 0.6))
            world.addChild(wash)
        }

        let dust = Effects.ambientDust(size: Theme.sceneSize, color: Theme.p1.mixed(with: .white, 0.5))
        dust.position = CGPoint(x: Theme.sceneSize.width / 2, y: Theme.sceneSize.height / 2)
        dust.zPosition = -98
        world.addChild(dust)
    }

    /// Vignette plus optional scanlines. Both sit above gameplay but below toasts.
    private func buildOverlay() {
        let vignette = SKSpriteNode(texture: TextureFactory.vignette(size: Theme.sceneSize),
                                    size: Theme.sceneSize)
        vignette.position = CGPoint(x: Theme.sceneSize.width / 2, y: Theme.sceneSize.height / 2)
        vignette.zPosition = 10
        vignette.alpha = 0.72
        chrome.addChild(vignette)

        if SaveStore.shared.crtEnabled {
            let scanlines = SKSpriteNode(
                texture: TextureFactory.scanlines(size: Theme.sceneSize),
                size: Theme.sceneSize)
            scanlines.texture?.filteringMode = .nearest
            scanlines.position = CGPoint(x: Theme.sceneSize.width / 2,
                                         y: Theme.sceneSize.height / 2)
            scanlines.zPosition = 11
            scanlines.alpha = 0.5
            chrome.addChild(scanlines)
        }
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        // Clamp so a hitch or a resume from background cannot teleport the ball.
        let dt = clamp(currentTime - lastUpdateTime, 0, 1.0 / 20.0)
        lastUpdateTime = currentTime
        sceneTime += dt

        hub.poll(dt: dt)
        let menu = hub.menuInput
        if menu.menuButton { requestMenuButton() }
        if !menu.isEmpty { handle(menu: menu) }
        tick(dt: CGFloat(dt))
    }

    // MARK: - Hub delegate

    func hubDidUpdateDevices(_ hub: ControllerHub) {}

    func hub(_ hub: ControllerHub, seatDidLoseDevice slot: PlayerSlot, name: String) {
        SoundEngine.shared.play(.controllerLost)
        toasts.showNotice("\(slot.longName) CONTROLLER LOST",
                          subtitle: "\(name) disconnected",
                          tint: Theme.danger,
                          symbol: "exclamationmark.triangle.fill",
                          duration: 3.2)
    }

    func hub(_ hub: ControllerHub, seatDidRegainDevice slot: PlayerSlot, name: String) {
        SoundEngine.shared.play(.controllerJoin)
        toasts.showNotice("\(slot.longName) READY",
                          subtitle: name,
                          tint: Theme.color(for: slot),
                          symbol: "gamecontroller.fill")
    }

    // MARK: - Achievements

    func achievementTracker(_ tracker: AchievementTracker, didUnlock achievement: Achievement) {
        SoundEngine.shared.play(.achievement)
        hub.rumbleAll(intensity: 0.5, sharpness: 0.4, duration: 0.16)
        toasts.show(Toast(title: achievement.title,
                          subtitle: nil,
                          style: .achievement(achievement),
                          duration: 3.0))
    }

    // MARK: - Helpers

    /// Standard "PRESS x TO y" hint line built from the live controller's glyphs.
    func hintRow(_ pairs: [(symbol: String, fallback: String, label: String)],
                 color: UIColor = Theme.inkDim) -> SKNode {
        let row = SKNode()
        var x: CGFloat = 0
        for (index, pair) in pairs.enumerated() {
            if index > 0 { x += 44 }
            if let icon = SymbolNode(pair.symbol, pointSize: 30, color: color) {
                icon.position = CGPoint(x: x + icon.size.width / 2, y: 0)
                row.addChild(icon)
                x += icon.size.width + 12
            } else {
                let badge = NeonLabel(pair.fallback, style: .caption, color: color,
                                      align: .left, glow: 0.3)
                badge.position = CGPoint(x: x, y: 0)
                row.addChild(badge)
                x += badge.contentWidth + 12
            }
            let label = NeonLabel(pair.label, style: .caption, color: color,
                                  align: .left, glow: 0.25)
            label.position = CGPoint(x: x, y: 0)
            row.addChild(label)
            x += label.contentWidth
        }
        // Centre the assembled row on its own origin.
        row.children.forEach { $0.position.x -= x / 2 }
        return row
    }

    /// Profile used to label button hints. Prefers a full gamepad over the Siri
    /// Remote, whose two-button vocabulary cannot describe most of the prompts.
    var hintProfile: ControllerProfile? {
        if let seated = hub.device(for: .one)?.profile, !seated.isRemote { return seated }
        let devices = hub.devices
        return (devices.first { !$0.profile.isRemote } ?? devices.first)?.profile
    }

    /// "Press <Options> to go back", in whatever dialect the pad speaks.
    func menuHint(_ label: String) -> (symbol: String, fallback: String, label: String) {
        (symbol: hintProfile?.menuSymbol ?? "line.3.horizontal.circle.fill",
         fallback: hintProfile?.menuFallback ?? "MENU",
         label: label)
    }
}
