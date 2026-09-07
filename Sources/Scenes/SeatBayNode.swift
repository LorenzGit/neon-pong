import SpriteKit
import UIKit

/// One player's slot in the controller lobby. Shows who is sitting there, what
/// they are holding, and a live paddle preview so you can confirm at a glance
/// that the controller in your hands is the one lighting up on screen.
final class SeatBayNode: SKNode {

    enum State {
        case empty
        case controller(ControllerDevice)
        case cpu(CPUDifficulty)
    }

    static let size = CGSize(width: 700, height: 452)

    let slot: PlayerSlot
    private(set) var state: State = .empty

    private let panel: PanelNode
    private let dashedBorder: SKShapeNode
    private let header: NeonLabel
    private let body = SKNode()
    private let footer = SKNode()

    private let previewTrack = SKNode()
    private let previewPaddle: SKSpriteNode
    private let previewGlow: GlowSprite
    private var previewY: CGFloat = 0
    private static let trackHalfHeight: CGFloat = 116

    private var tint: UIColor { Theme.color(for: slot) }

    init(slot: PlayerSlot) {
        self.slot = slot
        panel = PanelNode(size: SeatBayNode.size, corner: 30,
                          fill: UIColor(hex: 0x0C162E, alpha: 0.92),
                          stroke: Theme.panelStroke, lineWidth: 3, rimGlow: 0.18)

        dashedBorder = SKShapeNode(path: SeatBayNode.dashedPath())
        dashedBorder.strokeColor = Theme.inkFaint
        dashedBorder.lineWidth = 3
        dashedBorder.fillColor = .clear

        previewPaddle = SKSpriteNode(
            texture: TextureFactory.capsule(size: CGSize(width: 36, height: 160),
                                            color: Theme.color(for: slot)),
            size: CGSize(width: 16, height: 74))
        previewGlow = GlowSprite(color: Theme.color(for: slot), diameter: 220,
                                 intensity: 0.6, falloff: 2.6)
        previewGlow.xScale = 0.30
        previewGlow.yScale = 0.5

        header = NeonLabel(slot.longName, style: .heading, color: Theme.color(for: slot), glow: 0.7)

        super.init()

        addChild(panel)
        addChild(dashedBorder)
        header.position = CGPoint(x: 0, y: SeatBayNode.size.height / 2 - 52)
        addChild(header)
        addChild(body)
        addChild(footer)

        buildPreviewTrack()
        apply(.empty, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Preview track

    private func buildPreviewTrack() {
        let half = SeatBayNode.trackHalfHeight
        let rail = Arena.bar(from: CGPoint(x: 0, y: -half - 16),
                             to: CGPoint(x: 0, y: half + 16),
                             width: 3, color: Theme.arenaLineBright)
        rail.alpha = 0.6
        previewTrack.addChild(rail)
        for y in [-half - 16, half + 16] {
            let cap = Arena.bar(from: CGPoint(x: -14, y: y), to: CGPoint(x: 14, y: y),
                                width: 3, color: Theme.arenaLineBright)
            cap.alpha = 0.6
            previewTrack.addChild(cap)
        }
        previewTrack.addChild(previewGlow)
        previewTrack.addChild(previewPaddle)
        previewTrack.position = CGPoint(x: SeatBayNode.size.width / 2 - 96, y: -14)
        previewTrack.alpha = 0
        addChild(previewTrack)
    }

    /// Moves the preview paddle with live input from the seated controller.
    func updatePreview(axis: CGFloat, absolute: CGFloat?, dt: CGFloat) {
        guard case .controller = state else { return }
        let half = SeatBayNode.trackHalfHeight
        if let absolute {
            previewY = damp(previewY, lerp(-half, half, absolute), rate: 16, dt: dt)
        } else {
            previewY = clamp(previewY + axis * 340 * dt, -half, half)
        }
        previewPaddle.position.y = previewY
        previewGlow.position.y = previewY
    }

    // MARK: - State

    func apply(_ newState: State, animated: Bool = true) {
        state = newState
        body.removeAllChildren()
        footer.removeAllChildren()

        switch newState {
        case .empty:
            panel.setStrokeColor(tint.withAlphaComponent(0.42),
                                 fill: UIColor(hex: 0x0C162E, alpha: 0.92), corner: 30)
            dashedBorder.alpha = 0.55
            dashedBorder.strokeColor = tint.withAlphaComponent(0.55)
            header.color = tint.withAlphaComponent(0.75)
            previewTrack.run(.fadeOut(withDuration: 0.15))
            buildEmptyBody()

        case .controller(let device):
            panel.setStrokeColor(tint, fill: tint.withAlphaComponent(0.10), corner: 30)
            dashedBorder.alpha = 0
            header.color = tint
            previewTrack.run(.fadeIn(withDuration: 0.2))
            buildControllerBody(device)

        case .cpu(let difficulty):
            panel.setStrokeColor(Theme.gold, fill: Theme.gold.withAlphaComponent(0.08), corner: 30)
            dashedBorder.alpha = 0
            header.color = Theme.gold
            previewTrack.run(.fadeOut(withDuration: 0.15))
            buildCPUBody(difficulty)
        }

        if animated {
            removeAction(forKey: "stateChange")
            run(.sequence([
                .scale(to: 1.035, duration: 0.10).eased(.easeOut),
                .scale(to: 1.0, duration: 0.18).eased(.easeOut)
            ]), withKey: "stateChange")
        }
    }

    // MARK: - Body layouts

    private func buildEmptyBody() {
        if let icon = SymbolNode("gamecontroller", pointSize: 86,
                                 color: tint.withAlphaComponent(0.7)) {
            icon.position = CGPoint(x: 0, y: 78)
            body.addChild(icon)
        }

        // The prompt itself stays at full strength; only the glyph pulses, and
        // it is a plain sprite so nothing rasterised gets rescaled every frame.
        let prompt = promptRow(symbol: confirmSymbol, fallback: confirmFallback,
                               text: "PRESS TO JOIN", color: Theme.ink, size: .body,
                               pulseGlyph: true)
        prompt.position = CGPoint(x: 0, y: -6)
        body.addChild(prompt)

        // Only offer the CPU shortcut when something connected can actually
        // press it. A lone Siri Remote has no third button.
        if ControllerHub.shared.devices.contains(where: { $0.profile.hasTertiaryButton }) {
            let cpuHint = promptRow(symbol: tertiarySymbol, fallback: tertiaryFallback,
                                    text: "SEAT A CPU HERE", color: Theme.inkDim, size: .caption)
            cpuHint.position = CGPoint(x: 0, y: -72)
            body.addChild(cpuHint)
        }

        let waiting = NeonLabel("WAITING FOR A CONTROLLER", style: .caption,
                                color: Theme.inkFaint, glow: 0.2)
        waiting.position = CGPoint(x: 0, y: -SeatBayNode.size.height / 2 + 44)
        waiting.run(.breathe(from: 0.6, to: 1.0, duration: 1.8))
        footer.addChild(waiting)
    }

    private func buildControllerBody(_ device: ControllerDevice) {
        let leftX: CGFloat = -SeatBayNode.size.width / 2 + 62

        if let icon = SymbolNode(device.profile.deviceSymbol, pointSize: 70, color: tint) {
            icon.position = CGPoint(x: leftX + 24, y: 66)
            body.addChild(icon)
        }

        let name = NeonLabel(device.profile.displayName.uppercased(), style: .body,
                             color: Theme.ink, align: .left, glow: 0.45)
        name.position = CGPoint(x: leftX + 78, y: 78)
        // The track sits at width/2 - 96, so the name has to stop short of it.
        name.fitting(width: SeatBayNode.size.width / 2 - 96 - 70 - (leftX + 78))
        body.addChild(name)

        let connected = NeonLabel("CONNECTED", style: .caption, color: tint, align: .left, glow: 0.4)
        connected.position = CGPoint(x: leftX + 78, y: 36)
        body.addChild(connected)

        if let level = device.batteryLevel {
            let battery = BatteryPill(level: level, charging: device.isCharging)
            battery.position = CGPoint(x: leftX + 78 + battery.width / 2, y: -16)
            body.addChild(battery)
        } else if device.isCharging {
            let charging = NeonLabel("CHARGING", style: .caption, color: Theme.good,
                                     align: .left, glow: 0.3)
            charging.position = CGPoint(x: leftX + 78, y: -16)
            body.addChild(charging)
        }

        let hint = NeonLabel(device.profile.steeringHint.uppercased(), style: .caption,
                             color: Theme.inkDim, align: .left, glow: 0.2)
        hint.position = CGPoint(x: leftX, y: -74)
        body.addChild(hint)

        let moveMe = NeonLabel("MOVE TO TEST", style: .caption, color: tint.withAlphaComponent(0.8),
                               glow: 0.3)
        // Sits under the preview track, pulled in so it clears the bay edge.
        moveMe.position = CGPoint(x: SeatBayNode.size.width / 2 - 132,
                                  y: -SeatBayNode.size.height / 2 + 44)
        body.addChild(moveMe)

        let leave = promptRow(symbol: backSymbol, fallback: backFallback,
                              text: "LEAVE SEAT", color: Theme.inkDim, size: .caption)
        leave.position = CGPoint(x: -80, y: -SeatBayNode.size.height / 2 + 44)
        footer.addChild(leave)
    }

    private func buildCPUBody(_ difficulty: CPUDifficulty) {
        if let icon = SymbolNode("cpu.fill", pointSize: 74, color: Theme.gold) {
            icon.position = CGPoint(x: 0, y: 84)
            body.addChild(icon)
        }
        let title = NeonLabel("CPU OPPONENT", style: .body, color: Theme.ink, glow: 0.4)
        title.position = CGPoint(x: 0, y: 16)
        body.addChild(title)

        let level = NeonLabel(difficulty.title, style: .heading, color: Theme.gold, glow: 0.8)
        level.position = CGPoint(x: 0, y: -42)
        level.pop()
        body.addChild(level)

        for (name, x) in [("chevron.left", CGFloat(-190)), ("chevron.right", CGFloat(190))] {
            if let chevron = SymbolNode(name, pointSize: 34, color: Theme.gold) {
                chevron.position = CGPoint(x: x, y: -42)
                chevron.alpha = 0.7
                chevron.run(.breathe(from: 0.4, to: 0.9, duration: 1.4))
                body.addChild(chevron)
            }
        }

        let adjust = NeonLabel("LEFT / RIGHT TO CHANGE DIFFICULTY", style: .caption,
                               color: Theme.inkDim, glow: 0.2)
        adjust.position = CGPoint(x: 0, y: -96)
        body.addChild(adjust)

        let clear = promptRow(symbol: backSymbol, fallback: backFallback,
                              text: "CLEAR SEAT", color: Theme.inkDim, size: .caption)
        clear.position = CGPoint(x: 0, y: -SeatBayNode.size.height / 2 + 44)
        footer.addChild(clear)
    }

    // MARK: - Glyph helpers

    /// Buttons are labelled in the dialect of whatever is actually connected, so
    /// a PlayStation pad says Cross where an Xbox pad says A.
    private var referenceProfile: ControllerProfile? {
        if case .controller(let device) = state { return device.profile }
        let devices = ControllerHub.shared.devices
        // Prefer a full gamepad: its glyphs describe more of what is possible.
        return (devices.first { !$0.profile.isRemote } ?? devices.first)?.profile
    }
    private var confirmSymbol: String { referenceProfile?.confirmSymbol ?? "a.circle.fill" }
    private var confirmFallback: String { referenceProfile?.confirmFallback ?? "A" }
    private var backSymbol: String { referenceProfile?.backSymbol ?? "b.circle.fill" }
    private var backFallback: String { referenceProfile?.backFallback ?? "B" }
    private var tertiarySymbol: String { referenceProfile?.tertiarySymbol ?? "y.circle.fill" }
    private var tertiaryFallback: String { referenceProfile?.tertiaryFallback ?? "Y" }

    private func promptRow(symbol: String, fallback: String, text: String,
                           color: UIColor, size: Theme.TextStyle,
                           pulseGlyph: Bool = false) -> SKNode {
        let row = SKNode()
        let pointSize: CGFloat = size == .body ? 36 : 28
        var width: CGFloat = 0
        var glyphWidth: CGFloat = 0

        if let icon = SymbolNode(symbol, pointSize: pointSize, color: color) {
            row.addChild(icon)
            glyphWidth = icon.size.width
        } else {
            let badge = NeonLabel(fallback, style: size, color: color, glow: 0.3)
            row.addChild(badge)
            glyphWidth = badge.contentWidth + 10
        }
        let label = NeonLabel(text, style: size, color: color, align: .left, glow: 0.3)
        width = glyphWidth + 14 + label.contentWidth

        let glyph = row.children.first
        glyph?.position = CGPoint(x: -width / 2 + glyphWidth / 2, y: 0)
        if pulseGlyph {
            glyph?.run(.pulse(scale: 1.14, duration: 1.4))
        }
        label.position = CGPoint(x: -width / 2 + glyphWidth + 14, y: 0)
        row.addChild(label)
        return row
    }

    private static func dashedPath() -> CGPath {
        let rect = CGRect(x: -size.width / 2 + 16, y: -size.height / 2 + 16,
                          width: size.width - 32, height: size.height - 32)
        let base = UIBezierPath(roundedRect: rect, cornerRadius: 22).cgPath
        return base.copy(dashingWithPhase: 0, lengths: [16, 14])
    }
}

/// Small battery indicator with a proportional fill.
final class BatteryPill: SKNode {

    let width: CGFloat = 168

    init(level: Float, charging: Bool) {
        super.init()
        let height: CGFloat = 26
        let percent = Int((level * 100).rounded())
        let color: UIColor = level > 0.5 ? Theme.good : (level > 0.2 ? Theme.gold : Theme.danger)

        let shell = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2, width: 66, height: height),
                                cornerRadius: 7)
        shell.strokeColor = color
        shell.lineWidth = 2.5
        shell.fillColor = .clear
        addChild(shell)

        let nub = SKSpriteNode(texture: TextureFactory.pixel, color: color,
                               size: CGSize(width: 5, height: 11))
        nub.colorBlendFactor = 1
        nub.position = CGPoint(x: -width / 2 + 70, y: 0)
        addChild(nub)

        let fillWidth = max(3, (66 - 8) * CGFloat(level))
        let fill = SKSpriteNode(texture: TextureFactory.pixel, color: color,
                                size: CGSize(width: fillWidth, height: height - 9))
        fill.colorBlendFactor = 1
        fill.position = CGPoint(x: -width / 2 + 4 + fillWidth / 2, y: 0)
        addChild(fill)

        let text = charging ? "\(percent)%  CHARGING" : "\(percent)%"
        let label = NeonLabel(text, style: .caption, color: color, align: .left, glow: 0.25)
        label.position = CGPoint(x: -width / 2 + 84, y: 0)
        addChild(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
