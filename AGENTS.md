# Neon Pong — working notes

tvOS app, Swift + SpriteKit, no third-party dependencies. `README.md` covers
what it is and how to install it; this file is about how to work on it.

## Visual QA before finalising

**Every change to something a person looks at must be rendered and inspected
before it is called done.** A clean `./check.sh` and a green build say nothing
about whether text fits inside its panel.

Everything visual in this app is drawn in code — no bitmap assets — so layout
bugs cannot be caught by reading a diff. They have to be looked at. The defects
that reached the living-room TV in this project were all of that kind: SF
Symbols rendering as black silhouettes, labels silently losing their bloom to
draw-order, device names running off the edge of a seat bay, and glow copies
doubling into a legible second string outside a modal. Each was invisible to
the compiler and obvious in a screenshot.

The pass:

1. Render it. `./Tools/rebuild.sh`, then `./Tools/capture.sh <name> <delay>
   NP_*=...`. **Confirm the build succeeded** — a stale binary will re-render
   the bug you just fixed.
2. Read the capture back and look at it. Crop to the region you changed and
   inspect at full resolution; a downscaled contact sheet hides overflow by a
   few pixels and doubled glyphs.
3. Cover the extremes, not the happy path: the longest device name, an empty
   seat, a locked achievement, a mid-explosion frame, each controller brand.
   Overflow shows up at the extremes.
4. Check text against its container's edge and against the tvOS overscan-safe
   area (`Theme.safeInset`), not just against the screen. Anything that can hold
   variable-length text needs `NeonLabel.fitting(width:)`.
5. When a component renders twice on one screen — the two seat bays, both score
   labels — compare them. If they differ, that is a bug, not a coincidence.
6. For gameplay, a still is not enough. Record with `simctl io recordVideo`,
   pull frames with ffmpeg, and check motion, particles and transitions.

Say which states you inspected and what you saw. "It builds" is not evidence.

## Skills distilled from this project

`.agents/skills/` holds what this project taught, written to apply beyond it:

| | |
|---|---|
| `visual-qa-pass` | render it and look at it before calling it done |
| `game-controller-ux` | GameController glyphs, LEDs, the tvOS Menu button |
| `couch-coop-seating` | press-to-join, disconnects, who is player 1 |
| `spritekit-ui-craft` | draw order, glow, symbols, TV-safe layout |
| `tvos-app-setup` | project, icon, signing, install on a real Apple TV |
| `arcade-game-feel` | sub-stepped physics, juice, power-ups, synth audio |
| `fixture-fidelity` | keep harnesses from drifting off the shipping code |

`.claude` and `.codex` are symlinks to `.agents`, so both agents load the same
files and there is one copy to maintain. Fix a lesson there as well as in the
code when one of them turns out to be wrong.

## Duplicated descriptions drift

`DebugHarness` fabricates controllers so the simulator can show states that need
real hardware. Twice now it has carried its own copy of something the shipping
code also defines, and the two fell out of step — so the simulator showed a
button prompt the device never rendered. Fixtures must derive from the same
source as the real path, never restate it.

## The tools

- `./check.sh` — type-checks every file against the tvOS SDK in seconds. Use it
  while iterating; it is much faster than a build.
- `./Tools/rebuild.sh` — builds and installs on the booted simulator. Needs the
  simulator UDID in `/tmp/np_device`.
- `./Tools/capture.sh <name> <delay> [NP_KEY=VALUE ...]` — launches with debug
  overrides and screenshots. The `NP_*` table is in `README.md`.
- `xcrun swift Tools/IconForge.swift artifacts/art && python3 Tools/build_assets.py`
  — regenerates the icon, top shelf images and launch image.

`NP_*` overrides and `DebugHarness` are `#if DEBUG` only and are not compiled
into a Release build. Verify that with `strings` if you touch them.

## Deploying to the Apple TV

The team ID lives in `Configs/Signing.xcconfig` (gitignored; copy the
`.example`). Find the device with `xcrun devicectl list devices`, then:

```bash
ATV=<identifier from devicectl>
xcodebuild -project NeonPong.xcodeproj -scheme NeonPong -configuration Debug \
  -destination "platform=tvOS,id=$ATV" -derivedDataPath build/DDdev \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device "$ATV" \
  build/DDdev/Build/Products/Debug-appletvos/NeonPong.app
xcrun devicectl device process launch --device "$ATV" com.lorenzonuvoletta.neonpong
```

Pairing is done in Xcode ▸ Window ▸ Devices and Simulators; it cannot be
scripted. Registration on the developer account can — that is what
`-allowProvisioningDeviceRegistration` does.

## Things that will bite

- **Draw order.** The view runs with `ignoresSiblingOrder`, so anything layered
  needs an explicit `zPosition`. Without one, a label can be drawn over its own
  glow and lose it at random.
- **Glow.** Only display type (`.hero`, `.title`, `.score`) uses a real
  `CIGaussianBlur`; a screen's worth of blur passes is more than SpriteKit will
  reliably render. Body copy stacks unscaled additive copies plus a haze behind.
  Do not scale glow copies — that displaces every glyph and doubles the string.
- **Button letters.** `GCExtendedGamepad` is position-based. `buttonX` is the
  *west* face button: Square on PlayStation, Y on a Switch Pro. Never hard-code
  a glyph; take it from `ControllerProfile`.
- **The Siri Remote** has two action buttons, not four: `buttonA` clicks the
  touch surface, `buttonX` is Play/Pause. There is no Y.
- **Physics.** The ball is integrated by hand and sub-stepped so it cannot tunnel
  through a paddle at speed. Do not replace it with `SKPhysicsBody`.
