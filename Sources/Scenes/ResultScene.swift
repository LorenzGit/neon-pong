import SpriteKit
import UIKit

/// Post-match summary: who won, the final line, four headline stats, and the
/// three things anyone wants next.
final class ResultScene: BaseScene {

    private let result: MatchResult
    private let config: MatchConfig
    private var list: MenuList!

    init(size: CGSize, result: MatchResult, config: MatchConfig) {
        self.result = result
        self.config = config
        super.init(size: size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func build() {
        let winnerColor = Theme.color(for: result.winner)

        let confetti = Effects.confetti(width: Theme.sceneSize.width,
                                        colors: [winnerColor, Theme.gold, .white])
        confetti.position = CGPoint(x: 960, y: Theme.sceneSize.height + 30)
        confetti.zPosition = 40
        world.addChild(confetti)

        buildHeadline(color: winnerColor)
        buildScoreline()
        buildStats()
        buildMenu()

        SoundEngine.shared.play(.matchWin)
        hub.rumbleSeat(result.winner, intensity: 0.8, sharpness: 0.5, duration: 0.3)
    }

    // MARK: - Sections

    private func buildHeadline(color: UIColor) {
        if let trophy = SymbolNode("trophy.fill", pointSize: 86, color: Theme.gold) {
            trophy.position = CGPoint(x: 960, y: 962)
            world.addChild(trophy)
            trophy.riseIn(distance: 20)
            trophy.run(.repeatForever(.sequence([
                .rotate(byAngle: 0.06, duration: 1.1).eased(.easeInEaseOut),
                .rotate(byAngle: -0.12, duration: 2.2).eased(.easeInEaseOut),
                .rotate(byAngle: 0.06, duration: 1.1).eased(.easeInEaseOut)
            ])))
        }

        let winnerName = winnerTitle()
        let headline = NeonLabel(winnerName, style: .title, color: color, glow: 1.0)
        headline.position = CGPoint(x: 960, y: 872)
        world.addChild(headline)
        headline.riseIn(after: 0.06, distance: 26)

        let flavour: String
        if result.isShutout {
            flavour = "A PERFECT SHUTOUT"
        } else if result.wasComeback && result.largestDeficitOvercome >= 3 {
            flavour = "CAME BACK FROM \(result.largestDeficitOvercome) DOWN"
        } else if result.margin == 1 {
            flavour = "DECIDED BY A SINGLE POINT"
        } else {
            flavour = "WINS BY \(result.margin)"
        }
        let sub = NeonLabel(flavour, style: .caption, color: Theme.gold, glow: 0.4)
        sub.position = CGPoint(x: 960, y: 820)
        world.addChild(sub)
        sub.fadeIn(after: 0.16, duration: 0.3)
    }

    private func winnerTitle() -> String {
        if config.cpu[result.winner] != nil {
            return "CPU WINS"
        }
        return "\(result.winner.longName) WINS"
    }

    private func buildScoreline() {
        for slot in PlayerSlot.allCases {
            let color = Theme.color(for: slot)
            let isWinner = slot == result.winner
            let label = NeonLabel("\(result.score(slot))", style: .hero,
                                  color: isWinner ? color : color.withAlphaComponent(0.55),
                                  glow: isWinner ? 1.0 : 0.4)
            label.setScale(0.62)
            label.position = CGPoint(x: slot.isLeft ? 776 : 1144, y: 690)
            world.addChild(label)
            label.riseIn(after: 0.2 + (slot.isLeft ? 0 : 0.07), distance: 28)
            if isWinner { label.run(.pulse(scale: 1.05, duration: 1.6)) }

            let name = NeonLabel(seatLabel(slot), style: .caption,
                                 color: isWinner ? color : Theme.inkDim, glow: 0.3)
            name.position = CGPoint(x: slot.isLeft ? 776 : 1144, y: 596)
            world.addChild(name)
            name.fadeIn(after: 0.28, duration: 0.3)
        }

        let dash = Arena.bar(from: CGPoint(x: -24, y: 0), to: CGPoint(x: 24, y: 0),
                             width: 6, color: Theme.inkFaint)
        dash.position = CGPoint(x: 960, y: 690)
        world.addChild(dash)
    }

    private func seatLabel(_ slot: PlayerSlot) -> String {
        if let difficulty = config.cpu[slot] { return "CPU · \(difficulty.title)" }
        return slot.longName
    }

    private func buildStats() {
        let minutes = Int(result.duration) / 60
        let seconds = Int(result.duration) % 60
        let tiles: [(String, String, String, UIColor)] = [
            ("LONGEST RALLY", "\(result.longestRally)", "arrow.left.arrow.right", Theme.good),
            ("POWER-UPS", "\(result.powerUpsCollected.values.reduce(0, +))",
             "bolt.fill", Theme.p2),
            ("TOP BALL SPEED", "\(Int(result.topBallSpeed))", "speedometer", Theme.danger),
            ("MATCH TIME", String(format: "%d:%02d", minutes, seconds), "clock.fill", Theme.gold)
        ]

        let tileWidth: CGFloat = 330
        let spacing: CGFloat = 28
        let total = CGFloat(tiles.count) * tileWidth + CGFloat(tiles.count - 1) * spacing
        var x = 960 - total / 2 + tileWidth / 2

        for (index, tile) in tiles.enumerated() {
            let node = StatTile(title: tile.0, value: tile.1, symbol: tile.2, tint: tile.3,
                                size: CGSize(width: tileWidth, height: 150))
            node.position = CGPoint(x: x, y: 480)
            world.addChild(node)
            node.riseIn(after: 0.32 + Double(index) * 0.05, distance: 24)
            x += tileWidth + spacing
        }
    }

    private func buildMenu() {
        list = MenuList(items: [
            MenuItem(id: "rematch", title: "REMATCH", symbol: "arrow.clockwise", tint: Theme.p1),
            MenuItem(id: "setup", title: "CHANGE PLAYERS",
                     symbol: "gamecontroller.fill", tint: Theme.p2),
            MenuItem(id: "menu", title: "MAIN MENU", symbol: "house.fill", tint: Theme.inkDim)
        ], width: 700)
        list.position = CGPoint(x: 960, y: 232)
        list.onSelect = { [weak self] item, _ in self?.activate(item) }
        world.addChild(list)
        list.riseIn(after: 0.44, distance: 26)
    }

    private func activate(_ item: MenuItem) {
        switch item.id {
        case "rematch":
            Router.shared.go(.match(MatchConfig.current { self.hub.occupant($0) }),
                             transition: .doorway(withDuration: 0.45))
        case "setup":
            Router.shared.go(.lobby(returnToMenu: true))
        default:
            Router.shared.go(.menu)
        }
    }

    override func handle(menu: MenuInput) {
        if menu.up { list.move(by: -1) }
        if menu.down { list.move(by: 1) }
        if menu.confirm { list.activate() }
        if menu.back { Router.shared.go(.menu) }
    }

    override func handleMenuButton() -> Bool {
        SoundEngine.shared.play(.uiBack)
        Router.shared.go(.menu)
        return true
    }
}

/// Labelled number card used on the result screen.
final class StatTile: SKNode {

    init(title: String, value: String, symbol: String, tint: UIColor, size: CGSize) {
        super.init()
        addChild(PanelNode(size: size, corner: 20,
                           fill: UIColor(hex: 0x070C1B, alpha: 0.9),
                           stroke: tint.withAlphaComponent(0.7), lineWidth: 2.5, rimGlow: 0.14))

        if let icon = SymbolNode(symbol, pointSize: 30, color: tint) {
            icon.position = CGPoint(x: 0, y: 44)
            icon.zPosition = 2
            addChild(icon)
        }

        let valueLabel = NeonLabel(value, style: .heading, color: Theme.ink, glow: 0.5)
        valueLabel.position = CGPoint(x: 0, y: -2)
        valueLabel.zPosition = 2
        addChild(valueLabel)

        let titleLabel = NeonLabel(title, style: .caption, color: tint, glow: 0.3)
        titleLabel.position = CGPoint(x: 0, y: -48)
        titleLabel.zPosition = 2
        addChild(titleLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
