import SpriteKit
import UIKit

/// The couch-coop setup screen. Every connected controller can claim a seat by
/// pressing its own confirm button; seats colour-code themselves, light the pad's
/// LEDs, rumble on join, and preview live stick movement so nobody has to guess
/// which controller they are holding.
final class LobbyScene: BaseScene {

    private let returnToMenu: Bool

    private var bays: [PlayerSlot: SeatBayNode] = [:]
    private let deviceStrip = SKNode()
    private var startButton: PanelNode!
    private var startLabel: NeonLabel!
    private var startGlyph: SKNode?
    private let statusLabel: NeonLabel

    private var lastReadyState = false

    init(size: CGSize, returnToMenu: Bool) {
        self.returnToMenu = returnToMenu
        statusLabel = NeonLabel("", style: .caption, color: Theme.inkDim, glow: 0.25)
        super.init(size: size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Build

    override func build() {
        let title = NeonLabel("CONTROLLER SETUP", style: .title, color: Theme.ink, glow: 0.8)
        title.position = CGPoint(x: 960, y: 982)
        world.addChild(title)
        title.riseIn(distance: 24)

        let subtitle = NeonLabel("TWO CONTROLLERS. ONE COUCH.", style: .caption,
                                 color: Theme.gold, glow: 0.4)
        subtitle.position = CGPoint(x: 960, y: 928)
        world.addChild(subtitle)
        subtitle.fadeIn(after: 0.08, duration: 0.3)

        for (index, slot) in PlayerSlot.allCases.enumerated() {
            let bay = SeatBayNode(slot: slot)
            bay.position = CGPoint(x: slot.isLeft ? 590 : 1330, y: 648)
            world.addChild(bay)
            bays[slot] = bay
            bay.riseIn(after: 0.08 + Double(index) * 0.07, distance: 34)
        }

        deviceStrip.position = CGPoint(x: 960, y: 338)
        world.addChild(deviceStrip)

        let stripTitle = NeonLabel("DETECTED CONTROLLERS", style: .caption,
                                   color: Theme.inkFaint, glow: 0.2)
        stripTitle.position = CGPoint(x: 960, y: 402)
        world.addChild(stripTitle)

        statusLabel.position = CGPoint(x: 960, y: 280)
        world.addChild(statusLabel)

        buildStartButton()
        buildHints()
        refresh()
    }

    private func buildStartButton() {
        startButton = PanelNode(size: CGSize(width: 640, height: 96), corner: 48,
                                fill: UIColor(hex: 0x0A1428, alpha: 0.95),
                                stroke: Theme.inkFaint, lineWidth: 3, rimGlow: 0.2)
        startButton.position = CGPoint(x: 960, y: 216)
        world.addChild(startButton)

        startLabel = NeonLabel("START MATCH", style: .button, color: Theme.inkFaint, glow: 0.4)
        startLabel.zPosition = 3
        startButton.addChild(startLabel)
        startGlyph = SKNode()
        startGlyph?.zPosition = 3
        startButton.addChild(startGlyph!)
        startButton.riseIn(after: 0.22, distance: 22)
    }

    private func buildHints() {
        let hints = hintRow([
            (symbol: "arrow.left.arrow.right", fallback: "<>", label: "CPU DIFFICULTY"),
            (symbol: hintProfile?.secondarySymbol ?? "x.circle.fill",
             fallback: hintProfile?.secondaryFallback ?? "X", label: "PAIRING HELP"),
            menuHint("MAIN MENU")
        ], color: Theme.inkFaint)
        hints.position = CGPoint(x: 960, y: Arena.hintRowY)
        world.addChild(hints)
        hints.fadeIn(after: 0.3, duration: 0.3, to: 0.85)
    }

    // MARK: - State sync

    override func hubDidUpdateDevices(_ hub: ControllerHub) {
        refresh()
    }

    private func refresh() {
        for slot in PlayerSlot.allCases {
            guard let bay = bays[slot] else { continue }
            let newState: SeatBayNode.State
            switch hub.occupant(slot) {
            case .empty:
                newState = .empty
            case .controller:
                if let device = hub.device(for: slot) {
                    newState = .controller(device)
                } else {
                    newState = .empty
                }
            case .cpu(let difficulty):
                newState = .cpu(difficulty)
            }
            // Only rebuild when the shape of the state actually changed.
            if !Self.sameShape(bay.state, newState) {
                bay.apply(newState)
            }
        }

        rebuildDeviceStrip()
        refreshStartButton()
        refreshStatus()

        if hub.device(for: .one) != nil && hub.device(for: .two) != nil {
            AchievementTracker.shared.record(.twoControllersSeated)
        }
    }

    private static func sameShape(_ a: SeatBayNode.State, _ b: SeatBayNode.State) -> Bool {
        switch (a, b) {
        case (.empty, .empty): return true
        case (.controller(let x), .controller(let y)): return x === y
        case (.cpu(let x), .cpu(let y)): return x == y
        default: return false
        }
    }

    private func rebuildDeviceStrip() {
        deviceStrip.removeAllChildren()
        let devices = hub.devices
        guard !devices.isEmpty else {
            let empty = NeonLabel("NO CONTROLLERS DETECTED", style: .body,
                                  color: Theme.danger, glow: 0.5)
            empty.run(.breathe(from: 0.55, to: 1.0, duration: 1.3))
            deviceStrip.addChild(empty)
            return
        }

        let chips = devices.map { DeviceChip(device: $0) }
        let spacing: CGFloat = 22
        let total = chips.reduce(0) { $0 + $1.width } + spacing * CGFloat(chips.count - 1)
        var x = -total / 2
        for chip in chips {
            chip.position = CGPoint(x: x + chip.width / 2, y: 0)
            deviceStrip.addChild(chip)
            x += chip.width + spacing
        }
        // Four controllers can be connected at once; shrink rather than overflow.
        let available = Arena.field.width
        deviceStrip.setScale(total > available ? available / total : 1)
    }

    private func refreshStartButton() {
        let ready = hub.bothSeatsReady
        guard ready != lastReadyState || startButton.action(forKey: "ready") == nil else { return }
        lastReadyState = ready

        startGlyph?.removeAllChildren()

        if ready {
            startButton.setStrokeColor(Theme.good, fill: Theme.good.withAlphaComponent(0.14),
                                       corner: 48)
            startLabel.color = Theme.ink
            startLabel.text = "START MATCH"
            startButton.removeAction(forKey: "ready")
            startButton.run(.pulse(scale: 1.035, duration: 1.1), withKey: "ready")

            // Glyph sits inside the button so the call to action is one object.
            let profile = hintProfile
            if let glyph = SymbolNode(profile?.confirmSymbol ?? "a.circle.fill",
                                      pointSize: 38, color: Theme.good) {
                let textWidth = startLabel.contentWidth
                glyph.position = CGPoint(x: -textWidth / 2 - 44, y: 0)
                startGlyph?.addChild(glyph)
                startLabel.position = CGPoint(x: 24, y: 0)
            }
            SoundEngine.shared.play(.powerUpGood, volume: 0.5)
        } else {
            startButton.removeAction(forKey: "ready")
            startButton.setScale(1)
            startButton.setStrokeColor(Theme.inkFaint,
                                       fill: UIColor(hex: 0x0A1428, alpha: 0.95), corner: 48)
            startLabel.color = Theme.inkFaint
            startLabel.position = .zero
            startLabel.text = "SEAT BOTH PLAYERS"
        }
    }

    private func refreshStatus() {
        if hub.devices.isEmpty {
            statusLabel.color = Theme.danger
            statusLabel.text = "OPEN SETTINGS ▸ REMOTES AND DEVICES ▸ BLUETOOTH TO PAIR A CONTROLLER"
        } else if !hub.bothSeatsReady {
            statusLabel.color = Theme.inkDim
            let waiting = PlayerSlot.allCases.filter { !hub.isSeatReady($0) }
                .map(\.shortName).joined(separator: " AND ")
            statusLabel.text = "WAITING ON \(waiting)"
        } else {
            statusLabel.color = Theme.good
            statusLabel.text = "BOTH SEATS READY"
        }
    }

    // MARK: - Input

    override func tick(dt: CGFloat) {
        // Live paddle preview for whoever is seated.
        for slot in PlayerSlot.allCases {
            guard let device = hub.device(for: slot), let bay = bays[slot] else { continue }
            let input = hub.previewAxis(for: device)
            bay.updatePreview(axis: input.axis, absolute: input.absolute, dt: dt)
        }

        // An unseated controller pressing confirm takes the first free seat.
        for device in hub.unassignedDevicesPressingConfirm() {
            guard let seat = hub.firstEmptySeat else {
                toasts.showNotice("BOTH SEATS TAKEN",
                                  subtitle: "Press \(device.profile.backName) on a seated controller to free one",
                                  tint: Theme.gold, symbol: "exclamationmark.circle.fill")
                continue
            }
            hub.assign(device, to: seat)
            SoundEngine.shared.play(.controllerJoin)
            toasts.showNotice("\(seat.longName) JOINED",
                              subtitle: device.profile.displayName,
                              tint: Theme.color(for: seat),
                              symbol: device.profile.deviceSymbol)
        }

        // An unseated pad's back button leaves the screen. A seated one gives up
        // its seat first, so there is always a controller-only route back.
        if !hub.unassignedDevicesPressingBack().isEmpty {
            goBackToMenu()
            return
        }

        // A seated controller pressing back gives its seat up.
        for device in hub.seatedDevicesPressingBack() {
            let slot = device.slot
            hub.release(device)
            SoundEngine.shared.play(.controllerLeave)
            if let slot {
                toasts.showNotice("\(slot.longName) SEAT OPEN", tint: Theme.inkDim,
                                  symbol: "person.crop.circle.badge.minus")
            }
        }

        // Y seats a CPU, so one player can start a solo match without menus.
        for _ in hub.devicesPressingTertiary() {
            guard let seat = hub.firstEmptySeat else { break }
            hub.seatCPU(.pro, in: seat)
            SoundEngine.shared.play(.powerUpSpawn)
            toasts.showNotice("CPU SEATED AS \(seat.shortName)",
                              subtitle: "Left and right change difficulty",
                              tint: Theme.gold, symbol: "cpu.fill")
            break
        }

        // X opens the pairing walkthrough.
        if !hub.devicesPressingSecondary().isEmpty {
            SoundEngine.shared.play(.uiConfirm)
            Router.shared.go(.pairingHelp)
            return
        }

        // A seated controller pressing confirm starts the match.
        if !hub.seatedDevicesPressingConfirm().isEmpty {
            startMatch()
        }
    }

    override func handle(menu: MenuInput) {
        if menu.left { adjustCPU(-1) }
        if menu.right { adjustCPU(1) }
    }

    private func adjustCPU(_ delta: Int) {
        var changed = false
        for slot in PlayerSlot.allCases {
            guard case .cpu(let current) = hub.occupant(slot) else { continue }
            let count = CPUDifficulty.allCases.count
            let next = CPUDifficulty(
                rawValue: (current.rawValue + delta + count) % count) ?? current
            hub.seatCPU(next, in: slot)
            changed = true
        }
        if changed { SoundEngine.shared.play(.uiMove, volume: 0.8) }
    }

    private func startMatch() {
        guard hub.bothSeatsReady else {
            SoundEngine.shared.play(.uiBack)
            toasts.showNotice("BOTH SEATS MUST BE FILLED", tint: Theme.danger,
                              symbol: "exclamationmark.triangle.fill")
            return
        }
        SoundEngine.shared.play(.uiConfirm)
        hub.rumbleAll(intensity: 0.6, sharpness: 0.5, duration: 0.12)
        let config = MatchConfig.current { self.hub.occupant($0) }
        Router.shared.go(.match(config),
                         transition: .doorway(withDuration: 0.5))
    }

    override func handleMenuButton() -> Bool {
        goBackToMenu()
        return true
    }

    private func goBackToMenu() {
        SoundEngine.shared.play(.uiBack)
        Router.shared.go(.menu)
    }
}

/// Compact pill summarising one connected controller and where it is seated.
final class DeviceChip: SKNode {

    let width: CGFloat

    init(device: ControllerDevice) {
        let name = device.profile.shortName.uppercased()
        let seatText: String
        let tint: UIColor
        switch device.slot {
        case .some(let slot):
            seatText = slot.shortName
            tint = Theme.color(for: slot)
        case nil:
            seatText = "FREE"
            tint = Theme.inkFaint
        }

        let nameProbe = NeonLabel(name, style: .caption, color: .white, glow: 0)
        width = nameProbe.contentWidth + 168
        super.init()

        let height: CGFloat = 56
        let panel = PanelNode(size: CGSize(width: width, height: height), corner: height / 2,
                              fill: tint.withAlphaComponent(0.12), stroke: tint,
                              lineWidth: 2.5, rimGlow: 0.18)
        addChild(panel)

        var x = -width / 2 + 30
        if let icon = SymbolNode(device.profile.deviceSymbol, pointSize: 26, color: tint) {
            icon.position = CGPoint(x: x, y: 0)
            icon.zPosition = 2
            addChild(icon)
            x += 30
        }

        let label = NeonLabel(name, style: .caption, color: Theme.ink, align: .left, glow: 0.25)
        label.position = CGPoint(x: x, y: 0)
        label.zPosition = 2
        addChild(label)

        let seat = NeonLabel(seatText, style: .caption, color: tint, align: .right, glow: 0.4)
        seat.position = CGPoint(x: width / 2 - 26, y: 0)
        seat.zPosition = 2
        addChild(seat)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
