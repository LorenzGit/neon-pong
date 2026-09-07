---
name: game-controller-ux
description: Build controller support with Apple's GameController framework that speaks each pad's own language — correct button glyphs per brand, player LEDs and light bars, rumble, battery, the Siri Remote's limits, and routing the tvOS Menu button without dropping the player to the Home screen. Use when adding gamepad input, showing button prompts, supporting DualSense/DualShock/Xbox/Switch pads, or debugging "the wrong button is shown" and "I can't get back".
---

# Game controller UX

## Buttons are positions, not letters

`GCExtendedGamepad` is **position-based**. `buttonA` is always the south face
button, `buttonB` east, `buttonX` **west**, `buttonY` north — regardless of what
is printed on the pad.

So the logical mapping is already right (`buttonA` is confirm on every brand),
but **the glyph you draw is not**. Print a letter X for `buttonX` and a
PlayStation player reads it as Cross, which is their confirm button.

| Logical | Xbox | PlayStation | Switch |
|---|---|---|---|
| `buttonA` south | A | Cross | B |
| `buttonB` east | B | Circle | A |
| `buttonX` west | X | **Square** | **Y** |
| `buttonY` north | Y | **Triangle** | **X** |
| `buttonMenu` | Menu | **Options** | Plus |
| `buttonOptions` | View | Share / Create | Minus |

Never hard-code a glyph at the call site. Detect the brand once and derive
everything from it:

```swift
struct ControllerProfile {
    enum Brand { case dualSense, dualShock, xbox, switchPro, joyCon, siriRemote, mfi }
    let brand: Brand
    var confirmSymbol: String { /* per brand */ }
    var backSymbol: String { /* per brand */ }
}

static func detect(_ c: GCController) -> ControllerProfile {
    let haystack = (c.productCategory + " " + (c.vendorName ?? "")).lowercased()
    // match "dualsense", "dualshock", "xbox", "switch pro", "joy-con", "remote"
}
```

Match on lowercased `productCategory` + `vendorName` substrings rather than the
`GCProductCategory` constants alone; third-party pads report inconsistently.

SF Symbols has the glyphs: `a.circle.fill`, `b.circle.fill`,
`xmark.circle.fill` (Cross), `circle.circle.fill`, `square.circle.fill`,
`triangle.circle.fill`, `line.3.horizontal.circle.fill` (Menu/Options),
`playpause.circle.fill`. Always keep a text fallback — a symbol name that does
not exist on the running OS returns nil.

## The Siri Remote has two action buttons

It is a `GCMicroGamepad`, not extended. It gives you:

- `buttonA` — click the touch surface
- `buttonX` — **Play/Pause**
- `dpad` — the touch surface
- no `buttonY`, no shoulders, no second stick

So any prompt that needs a third button is unreachable on a remote. Hide it
rather than showing an instruction nobody can follow, and label `buttonX` as
Play/Pause — not with a back-chevron, which implies the Menu button and is a
different button entirely.

For analogue steering, absolute mode maps the touch surface 1:1 onto the screen,
which is the nicest way to drive a paddle or slider:

```swift
micro.reportsAbsoluteDpadValues = true
micro.allowsRotation = false
// Values go to zero on release, so hold the last position rather than snapping.
let touching = abs(micro.dpad.xAxis.value) > 0.001 || abs(micro.dpad.yAxis.value) > 0.001
if touching { held = clamp((CGFloat(micro.dpad.yAxis.value) + 1) / 2, 0, 1) }
```

## The tvOS Menu button

Menu is how the player leaves your app, and how they go back inside it. Get this
wrong and they either get trapped or get thrown to the Home screen mid-match.

Handle it as a `UIPress` in the view controller. Consuming it keeps the player
in the app; passing it up the chain at your **root** screen is what lets tvOS
take them home, which the platform expects.

```swift
override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    guard presses.contains(where: { $0.type == .menu }) else {
        super.pressesBegan(presses, with: event); return
    }
    if currentScreen.handleMenuButton() { consumed = true; return }  // sub-screen
    consumed = false
    super.pressesBegan(presses, with: event)                          // root: exit
}
```

Do **not** install a `pressedChangedHandler` on `buttonMenu`; that suppresses
the UIPress path entirely.

**Poll `buttonMenu` as well**, so going back does not depend on a single
delivery route — but then one physical press arrives twice. Gate the two:

```swift
// On a long-lived object, NOT on a screen.
func gateMenuButton(_ handler: () -> Bool) -> Bool {
    let now = CACurrentMediaTime()
    if now - lastHandledAt <= 0.35 { return lastResult }
    lastHandledAt = now; lastResult = handler(); return lastResult
}
```

The gate must outlive a screen transition. A per-screen gate lets the second
path reach a freshly presented root screen, hand it an unhandled press, and drop
the player out to the Home screen. Returning the *cached result* rather than a
blanket `true` is what preserves the intended exit at the root.

## Always give a second way back

Menu is undiscoverable if nothing on screen names it. Wire the east button
(B / Circle) to back as well, and label prompts with the real button name.

## Feedback the pad can give

```swift
controller.playerIndex = .index1                 // lights the pad's player LEDs
controller.light?.color = GCColor(red:green:blue:)  // DualSense/DualShock bar
```

Setting `playerIndex` and the light bar to a seat colour is the clearest way to
show which physical pad is which player. Pair it with a short rumble on join:

```swift
guard let haptics = controller.haptics else { return }
let engine = haptics.createEngine(withLocality: .default)
try engine?.start()
// CHHapticEvent(.hapticContinuous, intensity/sharpness, duration: 0.1)
```

Treat haptics as best-effort: wrap in `do/catch`, set a "failed" flag on the
first error and stop retrying, and gate it behind a user setting.

`controller.battery?.batteryLevel` is 0...1 but reads 0 when
`batteryState == .unknown` — check the state or you will show every pad as
empty.

## Identity across launches

`GCController` exposes no stable hardware UDID. The best you can do is
`vendorName + productCategory`, which is the same for two identical pads. Good
enough to restore "this model sat in seat 1 last time"; guard against handing the
same seat to both.

## Polling beats handlers for games

Read state once per frame in your update loop and diff against the previous
frame for edges. It keeps input aligned with simulation and makes auto-repeat,
dead zones and edge detection trivial:

```swift
func pressed(_ key: KeyPath<Snapshot, Bool>) -> Bool {
    current[keyPath: key] && !previous[keyPath: key]
}
```

Apply a dead zone that rescales the live range, or the stick feels sticky:

```swift
func deadzone(_ v: Float, _ t: Float = 0.14) -> CGFloat {
    let m = abs(v); guard m > t else { return 0 }
    return CGFloat((m - t) / (1 - t) * (v < 0 ? -1 : 1))
}
```

Set `GCController.shouldMonitorBackgroundEvents = true` and declare
`GCSupportsControllerUserInteraction` plus `GCSupportedGameControllers` in
Info.plist.
