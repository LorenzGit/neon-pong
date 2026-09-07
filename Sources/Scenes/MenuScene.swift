import SpriteKit
import UIKit

/// Home screen. Also the app's root: pressing Menu here hands control back to
/// tvOS, which is what the platform expects from a top-level screen.
final class MenuScene: BaseScene {

    private var list: MenuList!
    private let seatBar = SKNode()

    override func build() {
        let wordmark = Wordmark.make(scale: 0.58, glow: 0.9)
        wordmark.position = CGPoint(x: 960, y: 912)
        world.addChild(wordmark)
        wordmark.riseIn(distance: 22)

        let rule = Arena.bar(from: CGPoint(x: -250, y: 0), to: CGPoint(x: 250, y: 0),
                             width: 3, color: Theme.gold)
        rule.position = CGPoint(x: 960, y: 846)
        rule.alpha = 0.7
        world.addChild(rule)

        let tagline = NeonLabel("COUCH CO-OP EDITION", style: .caption, color: Theme.gold, glow: 0.5)
        tagline.position = CGPoint(x: 960, y: 808)
        world.addChild(tagline)
        tagline.fadeIn(after: 0.1, duration: 0.3)

        list = MenuList(items: makeItems(), width: 780, rowHeight: 84, spacing: 14)
        list.position = CGPoint(x: 960, y: 452)
        list.onSelect = { [weak self] item, _ in self?.activate(item) }
        world.addChild(list)
        list.riseIn(after: 0.1, distance: 30)

        seatBar.position = CGPoint(x: 960, y: 754)
        world.addChild(seatBar)
        refreshSeatBar()

        let hints = hintRow([
            (symbol: "arrow.up.arrow.down", fallback: "^v", label: "NAVIGATE"),
            (symbol: hintProfile?.confirmSymbol ?? "a.circle.fill",
             fallback: hintProfile?.confirmFallback ?? "A", label: "SELECT")
        ], color: Theme.inkFaint)
        hints.position = CGPoint(x: 960, y: Arena.hintRowY)
        world.addChild(hints)
        hints.fadeIn(after: 0.24, duration: 0.3, to: 0.85)
    }

    private func makeItems() -> [MenuItem] {
        let unlocked = AchievementTracker.shared.unlockedCount
        let total = AchievementCatalog.all.count
        return [
            MenuItem(id: "play", title: "PLAY", symbol: "play.fill",
                     detail: "SEAT TWO CONTROLLERS AND START A MATCH", tint: Theme.p1),
            MenuItem(id: "controllers", title: "CONTROLLERS", symbol: "gamecontroller.fill",
                     detail: "ASSIGN SEATS, CHECK BATTERIES, ADD A CPU", tint: Theme.p2),
            MenuItem(id: "achievements", title: "ACHIEVEMENTS",
                     symbol: "trophy.fill",
                     detail: "\(unlocked) OF \(total) UNLOCKED", tint: Theme.gold),
            MenuItem(id: "settings", title: "SETTINGS", symbol: "slider.horizontal.3",
                     detail: "MATCH LENGTH, BALL SPEED, EFFECTS", tint: Theme.good),
            MenuItem(id: "pairing", title: "HOW TO PAIR A CONTROLLER",
                     symbol: "antenna.radiowaves.left.and.right",
                     detail: "STEP-BY-STEP BLUETOOTH WALKTHROUGH", tint: Theme.inkDim)
        ]
    }

    private func activate(_ item: MenuItem) {
        switch item.id {
        case "play", "controllers":
            Router.shared.go(.lobby(returnToMenu: true))
        case "achievements":
            Router.shared.go(.achievements)
        case "settings":
            Router.shared.go(.settings)
        case "pairing":
            Router.shared.go(.pairingHelp)
        default:
            break
        }
    }

    // MARK: - Seat bar

    override func hubDidUpdateDevices(_ hub: ControllerHub) {
        refreshSeatBar()
        list?.updateItem("achievements") { item in
            item.detail = "\(AchievementTracker.shared.unlockedCount) OF \(AchievementCatalog.all.count) UNLOCKED"
        }
    }

    /// Persistent readout of who is seated, so the state of the couch is visible
    /// without opening the lobby.
    private func refreshSeatBar() {
        seatBar.removeAllChildren()
        var chips: [SKNode] = []
        var widths: [CGFloat] = []

        for slot in PlayerSlot.allCases {
            let text: String
            let tint: UIColor
            let symbol: String
            switch hub.occupant(slot) {
            case .empty:
                text = "EMPTY"
                tint = Theme.inkFaint
                symbol = "person.crop.circle.badge.questionmark"
            case .controller:
                text = hub.device(for: slot)?.profile.shortName.uppercased() ?? "CONTROLLER"
                tint = Theme.color(for: slot)
                symbol = hub.device(for: slot)?.profile.deviceSymbol ?? "gamecontroller.fill"
            case .cpu(let difficulty):
                text = "CPU · \(difficulty.title)"
                tint = Theme.gold
                symbol = "cpu.fill"
            }
            let chip = SeatSummaryChip(slot: slot, text: text, tint: tint, symbol: symbol)
            chips.append(chip)
            widths.append(chip.width)
        }

        let spacing: CGFloat = 34
        let total = widths.reduce(0, +) + spacing
        var x = -total / 2
        for (chip, width) in zip(chips, widths) {
            chip.position = CGPoint(x: x + width / 2, y: 0)
            seatBar.addChild(chip)
            x += width + spacing
        }
    }

    override func handle(menu: MenuInput) {
        if menu.up { list.move(by: -1) }
        if menu.down { list.move(by: 1) }
        if menu.confirm { list.activate() }
    }

    /// Root screen: let the system take Menu so the user can leave the app.
    override func handleMenuButton() -> Bool { false }
}

/// "P1 — DualSense" pill used on the main menu.
final class SeatSummaryChip: SKNode {

    let width: CGFloat

    init(slot: PlayerSlot, text: String, tint: UIColor, symbol: String) {
        let label = NeonLabel(text, style: .caption, color: tint, align: .left, glow: 0.3)
        width = label.contentWidth + 190
        super.init()

        let height: CGFloat = 62
        addChild(PanelNode(size: CGSize(width: width, height: height), corner: height / 2,
                           fill: tint.withAlphaComponent(0.10), stroke: tint,
                           lineWidth: 2.5, rimGlow: 0.16))

        var x = -width / 2 + 30
        let slotLabel = NeonLabel(slot.shortName, style: .caption,
                                  color: Theme.color(for: slot), align: .left, glow: 0.5)
        slotLabel.position = CGPoint(x: x, y: 0)
        slotLabel.zPosition = 2
        addChild(slotLabel)
        x += slotLabel.contentWidth + 20

        if let icon = SymbolNode(symbol, pointSize: 26, color: tint) {
            icon.position = CGPoint(x: x + 12, y: 0)
            icon.zPosition = 2
            addChild(icon)
            x += 42
        }

        label.position = CGPoint(x: x, y: 0)
        label.zPosition = 2
        addChild(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
