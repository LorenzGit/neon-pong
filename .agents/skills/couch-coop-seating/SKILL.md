---
name: couch-coop-seating
description: Design local multiplayer seat assignment — press-to-join, which pad is which player, colour coding, mid-session disconnects, CPU takeover, and remembering seats between launches. Use when building same-screen co-op or versus for console/TV/desktop, adding a player-select or lobby screen, or when someone asks "how do I know which controller is player 1".
---

# Couch co-op seating

The hard part of local multiplayer is not input. It is answering, from six feet
away, "which one of these is me" — and staying answered when a battery dies.

## Press-to-join beats a menu

Do not make players pick "2 players" and then guess who is who. Let each pad
claim a seat by pressing its own confirm button.

```
unseated pad presses confirm  -> takes the first free seat
seated pad presses back       -> gives the seat up
unseated pad presses back     -> leaves the screen
seated pad presses confirm    -> starts the match
```

That last pair is the trick: confirm means join *or* start depending on whether
you already hold a seat, so starting needs no separate focus target and no
navigation. Nobody has to hand the controller round.

## Make the pairing physically obvious

A seat colour on screen is not enough when two identical pads are on the sofa.
Bind the seat to the hardware:

- **Player LEDs and light bar** set to the seat colour (`playerIndex`,
  `light?.color`).
- **A short rumble on join**, so the person holding it feels the claim.
- **A live input preview in the seat** — a small paddle, cursor or bar that moves
  with the stick. This is the single most useful element on the screen: you wiggle
  and see which panel responds. Label it ("move to test").
- **The pad's real product name**, not "Controller 2".
- **Battery level**, so a dying pad is caught before the match, not during it.

## Say it in the pad's own language

Prompts must name the button on the controller that player is actually holding —
Cross on PlayStation, A on Xbox. See the `game-controller-ux` skill; getting this
wrong actively misdirects people.

With mixed pads on one couch you cannot label everything for everyone. Prefer a
full gamepad's vocabulary over a remote's for shared prompts, and use the seated
pad's own vocabulary inside its seat.

## Disconnects are a first-class state, not an error

A battery dies mid-rally. Do not fail out to a menu and do not keep simulating.

- **Pause immediately** and hold. Keep the score on screen.
- **Say which seat** lost its pad and which pad it was.
- **Resume automatically** when it reconnects, ideally with a short countdown so
  nobody is caught cold.
- **Offer a way forward** that is not "quit": let any other unseated pad drop
  into the empty seat, or hand it to the CPU.
- Keep the seat **reserved** rather than reshuffling everyone.

```swift
func hub(_ hub: Hub, seatDidLoseDevice slot: Slot, name: String) {
    guard config.isHuman(slot), phase != .finished else { return }
    showHoldOverlay(slot: slot, name: name)   // pauses; watches for a pad
}
```

While holding, poll for three exits every frame: the original pad returning, any
unseated pad pressing confirm, or the CPU-takeover button.

## Remember seats between launches

`GCController` has no stable hardware id. `vendorName + productCategory` is the
best available key — identical for two identical pads, which is fine for "this
model sat in seat 1 last time" as long as you refuse to hand the same seat to
two devices. Restore on connect, announce it briefly, and let it be overridden.

## Seats hold more than controllers

Model the seat as an enum, not an optional device. It lets a CPU sit down
without a parallel code path:

```swift
enum SeatOccupant { case empty, controller(ControllerID), cpu(Difficulty) }
```

Give the CPU a one-button shortcut from the seat itself (north face button)
rather than burying it in settings, and let left/right change difficulty in
place. Someone alone on the sofa should reach a match in two presses.

## Let any pad drive menus

Outside the match, aggregate navigation across every connected device. The
second player should never have to pass the controller back to change a setting.
Aggregate with edge detection plus hold-to-repeat:

```swift
// delay ~0.42s before the first repeat, ~0.14s between
```

## Pairing itself usually lives outside your app

On tvOS you cannot pair a Bluetooth pad from inside an app. Do not pretend
otherwise: show the exact system path, per-brand instructions for entering
pairing mode, and a live count of connected controllers that updates while the
player follows along. Watching the number go up is the confirmation they need.

## What to test

Drive these with a fake-device harness rather than by hand:

- zero controllers connected
- one connected, one seated
- both seated, then one leaves
- a pad disconnecting mid-match, then returning
- a pad disconnecting mid-match, replaced by a different pad
- CPU in one seat, human in the other
- two identical pads (does seat memory hand both the same seat?)
- the longest product name you can find
