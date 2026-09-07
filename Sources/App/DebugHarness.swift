import Foundation
import SpriteKit

#if DEBUG
/// Launch-argument driven overrides used to capture screenshots and to exercise
/// screens that would otherwise need two physical controllers. Debug builds
/// only, and inert unless an NP_* environment variable is set.
///
/// Examples:
///   NP_SCENE=lobby NP_CONTROLLERS=dualsense,xbox NP_SEAT=1
///   NP_SCENE=match NP_CPU=1 NP_SCORES=7,4 NP_EFFECTS=grow,freeze
enum DebugHarness {

    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static var isActive: Bool { env.keys.contains { $0.hasPrefix("NP_") } }

    /// Applies seat and progress overrides, then returns the route to open.
    static func startRoute() -> Route? {
        guard isActive else { return nil }

        seedControllers()
        seedSeats()
        seedAchievements()

        switch env["NP_SCENE"] ?? "menu" {
        case "boot":         return .boot
        case "lobby":        return .lobby(returnToMenu: true)
        case "achievements": return .achievements
        case "settings":     return .settings
        case "pairing":      return .pairingHelp
        case "match":        return .match(matchConfig())
        case "result":       return .result(sampleResult(), matchConfig())
        default:             return .menu
        }
    }

    // MARK: - Seats

    /// NP_CONTROLLERS=dualsense,xbox,siri creates that many hardware-free pads.
    private static func seedControllers() {
        guard let list = env["NP_CONTROLLERS"], !list.isEmpty else { return }
        let hub = ControllerHub.shared
        let batteries: [Float] = [0.82, 0.41, 0.96]
        for (index, name) in list.split(separator: ",").enumerated() {
            let profile = profile(named: String(name))
            let device = ControllerDevice(id: ControllerID(raw: "sim-\(index)-\(name)"),
                                          profile: profile)
            device.simulatedBatteryLevel = batteries[index % batteries.count]
            device.simulatedSnapshot = DeviceSnapshot()
            hub.addSimulatedDevice(device)
        }
    }

    private static func profile(named name: String) -> ControllerProfile {
        let brand: ControllerProfile.Brand
        switch name.lowercased() {
        case "dualsense": brand = .dualSense
        case "dualshock": brand = .dualShock
        case "xbox":      brand = .xbox
        case "switch":    brand = .switchPro
        default:          brand = .siriRemote
        }
        return ControllerProfile(brand: brand,
                                 displayName: ControllerProfile.defaultName(brand))
    }

    /// NP_SEAT=2 seats the first two simulated pads. NP_CPU=1 seats a CPU as P2.
    private static func seedSeats() {
        let hub = ControllerHub.shared
        if let count = env["NP_SEAT"].flatMap(Int.init) {
            for (index, device) in hub.devices.prefix(count).enumerated() {
                guard let slot = PlayerSlot(rawValue: index) else { break }
                hub.assign(device, to: slot, remember: false)
            }
        }
        if env["NP_CPU"] == "1" {
            hub.seatCPU(.pro, in: .two)
        }
        if env["NP_CPU"] == "both" {
            hub.seatCPU(.ruthless, in: .one)
            hub.seatCPU(.pro, in: .two)
        }
    }

    /// NP_ACHIEVEMENTS=seed unlocks a representative spread for screenshots.
    private static func seedAchievements() {
        guard env["NP_ACHIEVEMENTS"] == "seed" else { return }
        let store = SaveStore.shared
        let unlock = ["first.serve", "first.point", "rally.20", "win.shutout",
                      "power.multiball", "power.shield", "couch.ready", "win.comeback"]
        for id in unlock {
            guard let achievement = AchievementCatalog.achievement(id) else { continue }
            store.setProgress(achievement.target, for: id)
        }
        store.setProgress(63, for: "points.100")
        store.setProgress(214, for: "points.500")
        store.setProgress(7, for: "win.10")
        store.setProgress(34, for: "power.50")
        store.setProgress(9, for: "power.10")
        store.setProgress(5, for: "power.deck")
        store.setProgress(11, for: "matches.25")
        store.setProgress(1420, for: "time.60")
    }

    // MARK: - Match overrides

    static func matchConfig() -> MatchConfig {
        MatchConfig.current { ControllerHub.shared.occupant($0) }
    }

    /// NP_SCORES=7,4 opens the match already in progress.
    static var seededScores: [PlayerSlot: Int]? {
        guard let raw = env["NP_SCORES"] else { return nil }
        let parts = raw.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return [.one: parts[0], .two: parts[1]]
    }

    /// NP_EFFECTS=grow,freeze applies those power-ups the moment play starts.
    static var seededEffects: [PowerUpKind] {
        guard let raw = env["NP_EFFECTS"] else { return [] }
        return raw.split(separator: ",").compactMap { name in
            PowerUpKind.allCases.first { "\($0)".lowercased() == name.lowercased() }
        }
    }

    /// NP_POWERUP=fireball drops one pickup into the arena immediately.
    static var seededPickup: PowerUpKind? {
        guard let raw = env["NP_POWERUP"] else { return nil }
        return PowerUpKind.allCases.first { "\($0)".lowercased() == raw.lowercased() }
    }

    /// NP_PAUSED=1 opens the match with the pause overlay up.
    static var startPaused: Bool { env["NP_PAUSED"] == "1" }
    /// NP_DISCONNECT=1 opens the match in the controller-lost state.
    static var startDisconnected: Bool { env["NP_DISCONNECT"] == "1" }
    /// NP_NOCOUNTDOWN=1 skips the 3-2-1 so captures land on live play.
    static var skipCountdown: Bool { env["NP_NOCOUNTDOWN"] == "1" }

    // MARK: - Scripted input

    /// NP_SCRIPT=join drives the simulated pads through the real join flow, so a
    /// recording can show press-to-join and start working rather than jumping
    /// straight to a seeded scene.
    static func startScriptIfRequested() {
        guard let script = env["NP_SCRIPT"] else { return }
        let hub = ControllerHub.shared
        let devices = hub.devices.filter { $0.controller == nil }
        guard !devices.isEmpty else { return }

        if script == "back" {
            // Exercises the controller-only route out of a screen.
            tap(devices[0], \.back, at: 3.5)
            return
        }
        if script == "menubutton" {
            tap(devices[0], \.menuButton, at: 3.5)
            return
        }
        guard script == "join", devices.count >= 2 else { return }

        // (delay from launch, device index, button)
        let beats: [(TimeInterval, Int, WritableKeyPath<DeviceSnapshot, Bool>)] = [
            (4.6, 0, \.confirm),   // P1 takes a seat
            (6.4, 1, \.confirm),   // P2 takes a seat
            (9.0, 0, \.confirm)    // a seated pad starts the match
        ]

        for (delay, index, button) in beats {
            tap(devices[index], button, at: delay)
        }

        // Once play starts, sweep both paddles so the rally is watchable.
        Timer.scheduledTimer(withTimeInterval: 11.0, repeats: false) { _ in
            var phase = 0.0
            Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                phase += 1.0 / 30.0
                for (index, device) in devices.enumerated() {
                    var snapshot = device.simulatedSnapshot ?? DeviceSnapshot()
                    let offset = Double(index) * 1.7
                    snapshot.axisY = CGFloat(sin(phase * 1.6 + offset))
                    device.simulatedSnapshot = snapshot
                }
            }
        }
    }

    /// Presses and releases one button, so the hub sees a single clean edge.
    private static func tap(_ device: ControllerDevice,
                            _ button: WritableKeyPath<DeviceSnapshot, Bool>,
                            at delay: TimeInterval) {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            var snapshot = device.simulatedSnapshot ?? DeviceSnapshot()
            snapshot[keyPath: button] = true
            device.simulatedSnapshot = snapshot
        }
        Timer.scheduledTimer(withTimeInterval: delay + 0.12, repeats: false) { _ in
            var snapshot = device.simulatedSnapshot ?? DeviceSnapshot()
            snapshot[keyPath: button] = false
            device.simulatedSnapshot = snapshot
        }
    }

    private static func sampleResult() -> MatchResult {
        MatchResult(winner: .one,
                    scores: [.one: 11, .two: 8],
                    longestRally: 27,
                    totalRallies: 19,
                    powerUpsCollected: [.one: 6, .two: 4],
                    topBallSpeed: 2140,
                    duration: 254,
                    wasComeback: true,
                    largestDeficitOvercome: 5,
                    multiballPoints: 2,
                    fireballPoints: 1)
    }
}
#endif
