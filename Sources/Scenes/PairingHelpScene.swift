import SpriteKit
import UIKit

/// Pairing cannot happen inside an app on tvOS, so this screen does the next
/// best thing: it spells out the exact system path and reports live whether a
/// new controller has shown up while the user is following along.
final class PairingHelpScene: BaseScene {

    private var liveCount: NeonLabel!
    private var radar: SKNode!

    private let steps: [(String, String, String)] = [
        ("1", "PUT THE CONTROLLER IN PAIRING MODE",
         "PlayStation: hold Create + PS.   Xbox: hold the pair button on the back."),
        ("2", "OPEN SETTINGS ON YOUR APPLE TV",
         "Leave this app with the Menu button, then open the Settings app."),
        ("3", "GO TO REMOTES AND DEVICES ▸ BLUETOOTH",
         "Your controller appears under Other Devices while it is blinking."),
        ("4", "SELECT IT TO PAIR",
         "Once it says Connected, come back here and press the confirm button to take a seat.")
    ]

    override func build() {
        let title = NeonLabel("PAIR A CONTROLLER", style: .title, color: Theme.ink, glow: 0.8)
        title.position = CGPoint(x: 960, y: 972)
        world.addChild(title)
        title.riseIn(distance: 22)

        let subtitle = NeonLabel("ANY BLUETOOTH GAME CONTROLLER WORKS", style: .caption,
                                 color: Theme.gold, glow: 0.4)
        subtitle.position = CGPoint(x: 960, y: 920)
        world.addChild(subtitle)

        for (index, step) in steps.enumerated() {
            let row = buildStep(number: step.0, title: step.1, detail: step.2)
            row.position = CGPoint(x: 960, y: 812 - CGFloat(index) * 140)
            world.addChild(row)
            row.riseIn(after: 0.06 * Double(index), distance: 26)
        }

        buildLiveStatus()

        let hints = hintRow([
            menuHint("BACK")
        ], color: Theme.inkFaint)
        hints.position = CGPoint(x: 960, y: Arena.hintRowY)
        world.addChild(hints)
    }

    private func buildStep(number: String, title: String, detail: String) -> SKNode {
        let width: CGFloat = 1480
        let height: CGFloat = 118
        let node = SKNode()
        node.addChild(PanelNode(size: CGSize(width: width, height: height), corner: 20,
                                fill: UIColor(hex: 0x070C1B, alpha: 0.88),
                                stroke: Theme.panelStroke, lineWidth: 2.5, rimGlow: 0.12))

        let badge = SKShapeNode(circleOfRadius: 34)
        badge.strokeColor = Theme.p1
        badge.lineWidth = 3
        badge.glowWidth = 3
        badge.fillColor = Theme.p1.withAlphaComponent(0.14)
        badge.position = CGPoint(x: -width / 2 + 72, y: 0)
        badge.zPosition = 2
        node.addChild(badge)

        let numberLabel = NeonLabel(number, style: .heading, color: Theme.p1, glow: 0.7)
        numberLabel.position = badge.position
        numberLabel.zPosition = 3
        node.addChild(numberLabel)

        let titleLabel = NeonLabel(title, style: .body, color: Theme.ink, align: .left, glow: 0.35)
        titleLabel.position = CGPoint(x: -width / 2 + 132, y: 20)
        titleLabel.zPosition = 2
        titleLabel.fitting(width: width - 172)
        node.addChild(titleLabel)

        let detailLabel = NeonLabel(detail, style: .caption, color: Theme.inkDim,
                                    align: .left, glow: 0.15)
        detailLabel.position = CGPoint(x: -width / 2 + 132, y: -24)
        detailLabel.zPosition = 2
        detailLabel.fitting(width: width - 172)
        node.addChild(detailLabel)

        return node
    }

    private func buildLiveStatus() {
        radar = SKNode()
        radar.position = CGPoint(x: 700, y: 232)
        world.addChild(radar)

        // Three expanding rings, offset in time, reading as an active search.
        for index in 0..<3 {
            let ring = SKShapeNode(circleOfRadius: 26)
            ring.strokeColor = Theme.p1
            ring.lineWidth = 3
            ring.fillColor = .clear
            ring.alpha = 0
            ring.run(.repeatForever(.sequence([
                .wait(forDuration: Double(index) * 0.6),
                .group([
                    .scale(to: 2.4, duration: 1.8),
                    .sequence([
                        .fadeAlpha(to: 0.7, duration: 0.2),
                        .fadeAlpha(to: 0, duration: 1.6)
                    ])
                ]),
                .scale(to: 1, duration: 0),
                .wait(forDuration: 1.8 - Double(index) * 0.6)
            ])))
            radar.addChild(ring)
        }
        if let icon = SymbolNode("antenna.radiowaves.left.and.right", pointSize: 34,
                                 color: Theme.p1) {
            radar.addChild(icon)
        }

        liveCount = NeonLabel("", style: .body, color: Theme.inkDim, align: .left, glow: 0.4)
        liveCount.position = CGPoint(x: 760, y: 232)
        world.addChild(liveCount)
        refreshCount()
        centreStatusRow()
    }

    override func hubDidUpdateDevices(_ hub: ControllerHub) {
        refreshCount()
    }

    /// The radar badge and the status line are laid out as one unit so the pair
    /// stays centred no matter how long the status text is.
    private func centreStatusRow() {
        guard liveCount != nil, radar != nil else { return }
        let gap: CGFloat = 34
        let total = 56 + gap + liveCount.contentWidth
        let left = 960 - total / 2
        radar.position = CGPoint(x: left + 28, y: 232)
        liveCount.position = CGPoint(x: left + 56 + gap, y: 232)
    }

    private func refreshCount() {
        // A controller can connect before the scene has finished building.
        guard liveCount != nil else { return }
        let count = hub.devices.count
        switch count {
        case 0:
            liveCount.color = Theme.danger
            liveCount.text = "SEARCHING — NO CONTROLLERS CONNECTED"
        case 1:
            liveCount.color = Theme.gold
            liveCount.text = "1 CONTROLLER CONNECTED — ONE MORE FOR COUCH CO-OP"
        default:
            liveCount.color = Theme.good
            liveCount.text = "\(count) CONTROLLERS CONNECTED — YOU ARE READY"
        }
        liveCount.pop(scale: 1.06, duration: 0.2)
        centreStatusRow()
    }

    override func handle(menu: MenuInput) {
        if menu.back || menu.confirm { goBack() }
    }

    override func handleMenuButton() -> Bool {
        goBack()
        return true
    }

    private func goBack() {
        SoundEngine.shared.play(.uiBack)
        Router.shared.go(.lobby(returnToMenu: true))
    }
}
