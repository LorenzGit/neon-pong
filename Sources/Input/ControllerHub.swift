import GameController
import CoreHaptics
import QuartzCore
import UIKit

// MARK: - Per-frame input

/// One frame of raw intent read from a single physical device.
struct DeviceSnapshot {
    /// Velocity-style steering from sticks and D-pads, -1 (down) ... 1 (up).
    var axisY: CGFloat = 0
    /// Absolute target from a touch surface, 0 (bottom) ... 1 (top).
    /// Only trackpad devices report this, and only while a finger is down.
    var absoluteY: CGFloat?
    var touching = false

    var confirm = false
    var back = false
    /// X / Square.
    var secondary = false
    /// Y / Triangle.
    var tertiary = false
    var pause = false
    /// The controller's Menu button. tvOS also delivers this as a UIPress, but
    /// polling it too means "back" still works if that press never arrives.
    var menuButton = false
    var boost = false

    var navUp = false
    var navDown = false
    var navLeft = false
    var navRight = false
}

/// Edge-detected, repeat-aware menu intent aggregated across every device.
struct MenuInput {
    var up = false
    var down = false
    var left = false
    var right = false
    var confirm = false
    var back = false
    var pause = false
    var menuButton = false
    /// Which device produced the confirm, so a lobby can attribute the press.
    var confirmSource: ControllerID?

    var isEmpty: Bool {
        !(up || down || left || right || confirm || back || pause || menuButton)
    }
}

// MARK: - Device

/// A connected controller plus everything the app tracks about it.
final class ControllerDevice {

    let id: ControllerID
    /// nil for a device synthesised by the debug harness, which has no hardware
    /// behind it but otherwise behaves like any other seat occupant.
    let controller: GCController?
    let profile: ControllerProfile
    /// Colour-coded seat, or nil when the device is unassigned.
    var slot: PlayerSlot?

    var current = DeviceSnapshot()
    var previous = DeviceSnapshot()

    /// Hold timers driving menu auto-repeat, keyed by direction.
    fileprivate var holdTime: [Int: TimeInterval] = [:]
    fileprivate var repeatCount: [Int: Int] = [:]
    /// Last absolute touch target, held while the finger is lifted so a trackpad
    /// paddle does not snap back to centre on release.
    fileprivate var heldAbsoluteY: CGFloat = 0.5

    private var hapticEngine: CHHapticEngine?
    private var hapticsFailed = false

    init(id: ControllerID, controller: GCController) {
        self.id = id
        self.controller = controller
        self.profile = ControllerProfile.detect(controller)
    }

    /// Hardware-free device. Its snapshot is written directly by whoever created
    /// it; used by the debug harness to capture screenshots of seated states.
    init(id: ControllerID, profile: ControllerProfile) {
        self.id = id
        self.controller = nil
        self.profile = profile
    }

    /// When set, replaces hardware polling entirely.
    var simulatedSnapshot: DeviceSnapshot?

    /// Battery level 0...1, or nil when the device does not report one.
    var simulatedBatteryLevel: Float?

    var batteryLevel: Float? {
        if let simulatedBatteryLevel { return simulatedBatteryLevel }
        guard let battery = controller?.battery else { return nil }
        // Unknown state reports 0, which would read as an empty battery.
        guard battery.batteryState != .unknown else { return nil }
        return battery.batteryLevel
    }

    var isCharging: Bool {
        controller?.battery?.batteryState == .charging
    }

    // MARK: Feedback

    /// Sets the hardware player LEDs and, on DualSense/DualShock, the light bar.
    func applySeatFeedback() {
        guard let controller else { return }
        switch slot {
        case .one:
            controller.playerIndex = .index1
            setLight(Theme.p1)
        case .two:
            controller.playerIndex = .index2
            setLight(Theme.p2)
        case nil:
            controller.playerIndex = .indexUnset
            setLight(UIColor(hex: 0x14203A))
        }
    }

    private func setLight(_ color: UIColor) {
        guard let light = controller?.light else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        light.color = GCColor(red: Float(r), green: Float(g), blue: Float(b))
    }

    /// Short rumble. `intensity` and `sharpness` are 0...1.
    func rumble(intensity: Float, sharpness: Float, duration: TimeInterval = 0.08) {
        guard !hapticsFailed, let haptics = controller?.haptics else { return }
        if hapticEngine == nil {
            hapticEngine = haptics.createEngine(withLocality: .default)
            hapticEngine?.isAutoShutdownEnabled = true
            do {
                try hapticEngine?.start()
            } catch {
                hapticsFailed = true
                hapticEngine = nil
                return
            }
        }
        guard let engine = hapticEngine else { return }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0,
            duration: duration)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            hapticsFailed = true
        }
    }

    func stopHaptics() {
        hapticEngine?.stop()
        hapticEngine = nil
    }

    // MARK: Polling

    func poll() {
        previous = current
        if let simulatedSnapshot {
            current = simulatedSnapshot
            return
        }
        var snapshot = DeviceSnapshot()

        if let pad = controller?.extendedGamepad {
            let stick = deadzone(pad.leftThumbstick.yAxis.value)
                + deadzone(pad.rightThumbstick.yAxis.value)
            let dpad = CGFloat(pad.dpad.yAxis.value)
            snapshot.axisY = clamp(stick + dpad, -1, 1)

            snapshot.confirm = pad.buttonA.isPressed
            snapshot.back = pad.buttonB.isPressed
            snapshot.secondary = pad.buttonX.isPressed
            snapshot.tertiary = pad.buttonY.isPressed
            snapshot.pause = pad.buttonOptions?.isPressed ?? false
            snapshot.menuButton = pad.buttonMenu.isPressed
            snapshot.boost = pad.leftShoulder.isPressed || pad.rightShoulder.isPressed
                || pad.leftTrigger.isPressed || pad.rightTrigger.isPressed

            snapshot.navUp = pad.dpad.up.isPressed || deadzone(pad.leftThumbstick.yAxis.value, 0.55) > 0
            snapshot.navDown = pad.dpad.down.isPressed || deadzone(pad.leftThumbstick.yAxis.value, 0.55) < 0
            snapshot.navLeft = pad.dpad.left.isPressed || deadzone(pad.leftThumbstick.xAxis.value, 0.55) < 0
            snapshot.navRight = pad.dpad.right.isPressed || deadzone(pad.leftThumbstick.xAxis.value, 0.55) > 0

        } else if let micro = controller?.microGamepad {
            // Absolute mode maps the touch surface 1:1 onto the arena, which is the
            // most direct way to steer a paddle with a remote.
            micro.reportsAbsoluteDpadValues = true
            micro.allowsRotation = false

            let x = CGFloat(micro.dpad.xAxis.value)
            let y = CGFloat(micro.dpad.yAxis.value)
            let touching = abs(x) > 0.001 || abs(y) > 0.001
            snapshot.touching = touching
            if touching {
                heldAbsoluteY = clamp((y + 1) / 2, 0, 1)
            }
            snapshot.absoluteY = heldAbsoluteY
            snapshot.axisY = touching ? clamp(y, -1, 1) : 0

            snapshot.confirm = micro.buttonA.isPressed
            snapshot.back = micro.buttonX.isPressed

            // The remote has no discrete D-pad, so treat a firm swipe as a nudge.
            snapshot.navUp = y > 0.55
            snapshot.navDown = y < -0.55
            snapshot.navLeft = x < -0.55
            snapshot.navRight = x > 0.55
        }

        current = snapshot
    }

    fileprivate func pressed(_ key: KeyPath<DeviceSnapshot, Bool>) -> Bool {
        current[keyPath: key] && !previous[keyPath: key]
    }
}

// MARK: - Hub

protocol ControllerHubDelegate: AnyObject {
    /// A device connected, disconnected, or changed seat.
    func hubDidUpdateDevices(_ hub: ControllerHub)
    /// A device that was driving a seat went away mid-session.
    func hub(_ hub: ControllerHub, seatDidLoseDevice slot: PlayerSlot, name: String)
    /// A device reclaimed a seat it previously held.
    func hub(_ hub: ControllerHub, seatDidRegainDevice slot: PlayerSlot, name: String)
}

/// Owns controller discovery, seat assignment and per-frame polling for the
/// whole app. Scenes read from it; they never touch GameController directly.
final class ControllerHub {

    static let shared = ControllerHub()

    private(set) var devices: [ControllerDevice] = []
    /// Seat occupancy. A seat may be empty, driven by a device, or by the CPU.
    private(set) var seats: [PlayerSlot: SeatOccupant] = [.one: .empty, .two: .empty]

    weak var delegate: ControllerHubDelegate?

    /// Set by the match scene so a mid-game disconnect can pause play.
    var isMatchActive = false

    private var ordinalCounter = 0
    private var lastMenuHandledAt: CFTimeInterval = -10
    private var lastMenuResult = false
    private var menu = MenuInput()
    private let store = SaveStore.shared

    private init() {}

    // MARK: Lifecycle

    func start() {
        GCController.shouldMonitorBackgroundEvents = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(didConnect(_:)),
            name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(didDisconnect(_:)),
            name: .GCControllerDidDisconnect, object: nil)
        GCController.controllers().forEach { register($0) }
    }

    @objc private func didConnect(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        register(controller)
    }

    @objc private func didDisconnect(_ note: Notification) {
        guard let controller = note.object as? GCController,
              let index = devices.firstIndex(where: { $0.controller === controller })
        else { return }
        let device = devices[index]
        device.stopHaptics()
        let lostSeat = device.slot
        devices.remove(at: index)
        if let slot = lostSeat {
            // Keep the seat reserved so the same pad can walk straight back in.
            seats[slot] = .empty
            delegate?.hub(self, seatDidLoseDevice: slot, name: device.profile.shortName)
        }
        delegate?.hubDidUpdateDevices(self)
    }

    private func register(_ controller: GCController) {
        guard !devices.contains(where: { $0.controller === controller }) else { return }
        ordinalCounter += 1
        let vendor = controller.vendorName ?? "Controller"
        let id = ControllerID(raw: "\(vendor)|\(controller.productCategory)|#\(ordinalCounter)")
        let device = ControllerDevice(id: id, controller: controller)
        devices.append(device)

        // Auto-restore the seat this exact model held last time, if it is free.
        if let remembered = store.rememberedSeat(forSignature: signature(of: device)),
           case .empty = seats[remembered] ?? .empty,
           !devices.contains(where: { $0.slot == remembered }) {
            assign(device, to: remembered, remember: false)
            delegate?.hub(self, seatDidRegainDevice: remembered, name: device.profile.shortName)
        } else {
            device.applySeatFeedback()
        }
        delegate?.hubDidUpdateDevices(self)
    }

    /// Model-level signature used to remember seats between launches. Two
    /// identical pads share a signature, which is the best identity the
    /// GameController framework exposes.
    private func signature(of device: ControllerDevice) -> String {
        guard let controller = device.controller else { return "simulated|\(device.id.raw)" }
        return "\(controller.vendorName ?? "?")|\(controller.productCategory)"
    }

    // MARK: Seats

    func device(for slot: PlayerSlot) -> ControllerDevice? {
        devices.first { $0.slot == slot }
    }

    var unassignedDevices: [ControllerDevice] {
        devices.filter { $0.slot == nil }
    }

    func occupant(_ slot: PlayerSlot) -> SeatOccupant {
        seats[slot] ?? .empty
    }

    func isSeatReady(_ slot: PlayerSlot) -> Bool {
        switch occupant(slot) {
        case .empty: return false
        case .controller, .cpu: return true
        }
    }

    var bothSeatsReady: Bool {
        isSeatReady(.one) && isSeatReady(.two)
    }

    @discardableResult
    func assign(_ device: ControllerDevice, to slot: PlayerSlot, remember: Bool = true) -> Bool {
        guard device.slot != slot else { return false }
        // Evict whoever holds the seat, human or CPU.
        if let sitting = self.device(for: slot) {
            sitting.slot = nil
            sitting.applySeatFeedback()
        }
        if let old = device.slot {
            seats[old] = .empty
        }
        device.slot = slot
        seats[slot] = .controller(device.id)
        device.applySeatFeedback()
        device.rumble(intensity: 0.75, sharpness: 0.6, duration: 0.10)
        if remember { store.rememberSeat(slot, signature: signature(of: device)) }
        delegate?.hubDidUpdateDevices(self)
        return true
    }

    func release(_ device: ControllerDevice) {
        guard let slot = device.slot else { return }
        device.slot = nil
        seats[slot] = .empty
        device.applySeatFeedback()
        device.rumble(intensity: 0.35, sharpness: 0.2, duration: 0.06)
        store.forgetSeat(slot)
        delegate?.hubDidUpdateDevices(self)
    }

    func seatCPU(_ difficulty: CPUDifficulty, in slot: PlayerSlot) {
        if let sitting = device(for: slot) {
            sitting.slot = nil
            sitting.applySeatFeedback()
        }
        seats[slot] = .cpu(difficulty)
        delegate?.hubDidUpdateDevices(self)
    }

    func clearSeat(_ slot: PlayerSlot) {
        if let sitting = device(for: slot) {
            sitting.slot = nil
            sitting.applySeatFeedback()
        }
        seats[slot] = .empty
        delegate?.hubDidUpdateDevices(self)
    }

    /// First empty seat, preferring player one.
    var firstEmptySeat: PlayerSlot? {
        PlayerSlot.allCases.first { !isSeatReady($0) }
    }

    // MARK: Menu button

    /// One physical Menu press reaches the app twice: as a `UIPress` and as a
    /// polled `buttonMenu` edge. This collapses them into a single decision.
    ///
    /// The gate lives on the hub rather than on a scene because the first path
    /// through can change scenes; a per-scene gate would let the second path
    /// reach a freshly presented root screen, hand it an unhandled press, and
    /// drop the player out to the tvOS Home screen.
    func gateMenuButton(_ handler: () -> Bool) -> Bool {
        let now = CACurrentMediaTime()
        if now - lastMenuHandledAt <= 0.35 { return lastMenuResult }
        lastMenuHandledAt = now
        lastMenuResult = handler()
        return lastMenuResult
    }

    // MARK: Polling

    /// Call once per frame before reading input.
    func poll(dt: TimeInterval) {
        devices.forEach { $0.poll() }
        menu = aggregateMenuInput(dt: dt)
    }

    /// Menu intent for this frame. Any connected device can drive menus so a
    /// second player is never locked out of navigation.
    var menuInput: MenuInput { menu }

    /// Steering for a seat this frame, as a velocity in -1...1 and an optional
    /// absolute target in 0...1 for trackpad devices.
    func steering(for slot: PlayerSlot) -> (axis: CGFloat, absolute: CGFloat?, boost: Bool) {
        guard let device = device(for: slot) else { return (0, nil, false) }
        return (device.current.axisY, device.current.absoluteY, device.current.boost)
    }

    func rumbleSeat(_ slot: PlayerSlot, intensity: Float, sharpness: Float, duration: TimeInterval = 0.08) {
        guard store.rumbleEnabled else { return }
        device(for: slot)?.rumble(intensity: intensity, sharpness: sharpness, duration: duration)
    }

    func rumbleAll(intensity: Float, sharpness: Float, duration: TimeInterval = 0.12) {
        guard store.rumbleEnabled else { return }
        devices.forEach { $0.rumble(intensity: intensity, sharpness: sharpness, duration: duration) }
    }

    private func aggregateMenuInput(dt: TimeInterval) -> MenuInput {
        var result = MenuInput()
        for device in devices {
            if repeats(device, direction: 0, held: device.current.navUp, dt: dt) { result.up = true }
            if repeats(device, direction: 1, held: device.current.navDown, dt: dt) { result.down = true }
            if repeats(device, direction: 2, held: device.current.navLeft, dt: dt) { result.left = true }
            if repeats(device, direction: 3, held: device.current.navRight, dt: dt) { result.right = true }
            if device.pressed(\.confirm) {
                result.confirm = true
                result.confirmSource = device.id
            }
            if device.pressed(\.back) { result.back = true }
            if device.pressed(\.pause) { result.pause = true }
            if device.pressed(\.menuButton) { result.menuButton = true }
        }
        return result
    }

    /// Edge on press, then auto-repeat after a hold. Standard menu feel.
    private func repeats(_ device: ControllerDevice, direction: Int,
                         held: Bool, dt: TimeInterval) -> Bool {
        guard held else {
            device.holdTime[direction] = 0
            device.repeatCount[direction] = 0
            return false
        }
        let elapsed = (device.holdTime[direction] ?? 0) + dt
        device.holdTime[direction] = elapsed
        let fired = device.repeatCount[direction] ?? 0
        if fired == 0 {
            device.repeatCount[direction] = 1
            return true
        }
        let due = Theme.menuRepeatDelay + Theme.menuRepeatInterval * Double(fired - 1)
        if elapsed >= due {
            device.repeatCount[direction] = fired + 1
            return true
        }
        return false
    }

    /// Devices that hold no seat and pressed confirm this frame.
    func unassignedDevicesPressingConfirm() -> [ControllerDevice] {
        devices.filter { $0.slot == nil && $0.pressed(\.confirm) }
    }

    /// Unseated devices that pressed back this frame, i.e. asked to leave the
    /// screen rather than a seat.
    func unassignedDevicesPressingBack() -> [ControllerDevice] {
        devices.filter { $0.slot == nil && $0.pressed(\.back) }
    }

    /// Seated devices that pressed back this frame, i.e. asked to leave.
    func seatedDevicesPressingBack() -> [ControllerDevice] {
        devices.filter { $0.slot != nil && $0.pressed(\.back) }
    }

    /// Seated devices that pressed confirm this frame, i.e. asked to start.
    func seatedDevicesPressingConfirm() -> [ControllerDevice] {
        devices.filter { $0.slot != nil && $0.pressed(\.confirm) }
    }

    /// Any device that pressed the Y / Triangle button this frame.
    func devicesPressingTertiary() -> [ControllerDevice] {
        devices.filter { $0.pressed(\.tertiary) }
    }

    /// Adds a hardware-free device. Debug harness only.
    func addSimulatedDevice(_ device: ControllerDevice) {
        devices.append(device)
        device.applySeatFeedback()
        delegate?.hubDidUpdateDevices(self)
    }

    /// Any device that pressed the X / Square button this frame.
    func devicesPressingSecondary() -> [ControllerDevice] {
        devices.filter { $0.pressed(\.secondary) }
    }

    /// Live steering for a device, used by the lobby's paddle preview.
    func previewAxis(for device: ControllerDevice) -> (axis: CGFloat, absolute: CGFloat?) {
        (device.current.axisY, device.current.absoluteY)
    }
}
