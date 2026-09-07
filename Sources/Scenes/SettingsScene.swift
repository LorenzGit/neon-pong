import SpriteKit

/// Match rules and presentation toggles. Every row is a cycling option so the
/// whole screen is drivable with left/right and one button.
final class SettingsScene: BaseScene {

    private var list: MenuList!
    private static let targetScores = [5, 7, 11, 21]

    override func build() {
        let title = NeonLabel("SETTINGS", style: .title, color: Theme.ink, glow: 0.8)
        title.position = CGPoint(x: 960, y: 962)
        world.addChild(title)
        title.riseIn(distance: 24)

        list = MenuList(items: makeItems(), width: 900, rowHeight: 74, spacing: 10)
        list.position = CGPoint(x: 960, y: 572)
        list.onAdjust = { [weak self] item, _, delta in self?.adjust(item, delta) }
        list.onSelect = { [weak self] item, _ in self?.select(item) }
        world.addChild(list)
        list.riseIn(after: 0.08, distance: 28)

        let hints = hintRow([
            (symbol: "arrow.left.arrow.right", fallback: "<>", label: "CHANGE"),
            menuHint("BACK")
        ], color: Theme.inkFaint)
        hints.position = CGPoint(x: 960, y: Arena.hintRowY)
        world.addChild(hints)
        hints.fadeIn(after: 0.2, duration: 0.3, to: 0.85)
    }

    private func makeItems() -> [MenuItem] {
        let store = SaveStore.shared
        let speed = BallSpeedPreset(rawValue: store.ballSpeedIndex) ?? .classic
        return [
            MenuItem(id: "target", title: "POINTS TO WIN",
                     value: "\(store.targetScore)", symbol: "flag.checkered",
                     detail: "FIRST TO THIS MANY POINTS TAKES THE MATCH", tint: Theme.gold),
            MenuItem(id: "speed", title: "BALL SPEED",
                     value: speed.title, symbol: "speedometer",
                     detail: "HOW FAST THE SERVE STARTS AND HOW HARD IT RAMPS", tint: Theme.danger),
            MenuItem(id: "powerups", title: "POWER-UPS",
                     value: store.powerUpsEnabled ? "ON" : "OFF", symbol: "bolt.fill",
                     detail: "SPAWN PICKUPS MID-RALLY", tint: Theme.p2),
            MenuItem(id: "rumble", title: "CONTROLLER RUMBLE",
                     value: store.rumbleEnabled ? "ON" : "OFF", symbol: "waveform",
                     detail: "HAPTICS ON PADDLE HITS, GOALS AND UNLOCKS", tint: Theme.p1),
            MenuItem(id: "sound", title: "SOUND",
                     value: store.soundEnabled ? "ON" : "OFF", symbol: "speaker.wave.2.fill",
                     detail: "SYNTHESISED ARCADE BLEEPS AND EXPLOSIONS", tint: Theme.p1),
            MenuItem(id: "shake", title: "SCREEN SHAKE",
                     value: store.screenShakeEnabled ? "ON" : "OFF", symbol: "waveform.path",
                     detail: "CAMERA KICK ON BIG HITS", tint: Theme.good),
            MenuItem(id: "crt", title: "CRT SCANLINES",
                     value: store.crtEnabled ? "ON" : "OFF", symbol: "tv.fill",
                     detail: "RETRO OVERLAY. TAKES EFFECT ON THE NEXT SCREEN", tint: Theme.good),
            MenuItem(id: "reset", title: "RESET ACHIEVEMENTS AND STATS",
                     symbol: "trash.fill",
                     detail: "PRESS TWICE TO CONFIRM", tint: Theme.danger)
        ]
    }

    private func adjust(_ item: MenuItem, _ delta: Int) {
        let store = SaveStore.shared
        switch item.id {
        case "target":
            let scores = Self.targetScores
            let index = scores.firstIndex(of: store.targetScore) ?? 2
            store.targetScore = scores[(index + delta + scores.count) % scores.count]
            list.updateValue("\(store.targetScore)", forID: "target")
        case "speed":
            let count = BallSpeedPreset.allCases.count
            store.ballSpeedIndex = (store.ballSpeedIndex + delta + count) % count
            let speed = BallSpeedPreset(rawValue: store.ballSpeedIndex) ?? .classic
            list.updateValue(speed.title, forID: "speed")
        case "powerups":
            store.powerUpsEnabled.toggle()
            list.updateValue(store.powerUpsEnabled ? "ON" : "OFF", forID: "powerups")
        case "rumble":
            store.rumbleEnabled.toggle()
            list.updateValue(store.rumbleEnabled ? "ON" : "OFF", forID: "rumble")
            if store.rumbleEnabled { hub.rumbleAll(intensity: 0.6, sharpness: 0.5) }
        case "sound":
            store.soundEnabled.toggle()
            list.updateValue(store.soundEnabled ? "ON" : "OFF", forID: "sound")
            if store.soundEnabled { SoundEngine.shared.play(.powerUpGood) }
        case "shake":
            store.screenShakeEnabled.toggle()
            list.updateValue(store.screenShakeEnabled ? "ON" : "OFF", forID: "shake")
        case "crt":
            store.crtEnabled.toggle()
            list.updateValue(store.crtEnabled ? "ON" : "OFF", forID: "crt")
        default:
            break
        }
    }

    private var resetArmed = false

    private func select(_ item: MenuItem) {
        guard item.id == "reset" else { return }
        if resetArmed {
            SaveStore.shared.resetEverything()
            resetArmed = false
            list.updateItem("reset") { $0.title = "RESET ACHIEVEMENTS AND STATS" }
            toasts.showNotice("PROGRESS CLEARED", tint: Theme.danger, symbol: "trash.fill")
            SoundEngine.shared.play(.powerUpBad)
        } else {
            resetArmed = true
            list.updateItem("reset") { $0.title = "PRESS AGAIN TO CONFIRM" }
            toasts.showNotice("THIS WIPES EVERY ACHIEVEMENT",
                              subtitle: "Select the row again to confirm",
                              tint: Theme.danger, symbol: "exclamationmark.triangle.fill")
        }
    }

    override func handle(menu: MenuInput) {
        if menu.up { list.move(by: -1); resetArmed = false }
        if menu.down { list.move(by: 1); resetArmed = false }
        if menu.left { list.adjust(-1) }
        if menu.right { list.adjust(1) }
        if menu.confirm { list.activate() }
        if menu.back { goBack() }
    }

    override func handleMenuButton() -> Bool {
        goBack()
        return true
    }

    private func goBack() {
        SoundEngine.shared.play(.uiBack)
        Router.shared.go(.menu)
    }
}
