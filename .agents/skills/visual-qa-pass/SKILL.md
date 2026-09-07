---
name: visual-qa-pass
description: Render, look at, and prove any change a person will see — UI, layout, copy, icons, generated art, charts, game screens. Use before calling visual work done, when asked "does this look right", "check the UI", "screenshot it", "verify the layout", or whenever a diff changes something that gets drawn. Covers driving unreachable states, what to inspect, and the failure modes that type-check cleanly.
---

# Visual QA pass

A green build says nothing about whether text fits inside its panel. Anything
drawn has to be rendered and looked at before it is called done.

This matters most where the UI is built in code rather than from static assets:
there is no design file to compare against, and layout bugs are invisible in a
diff.

## The loop

1. **Build, and confirm it succeeded.** A stale binary re-renders the bug you
   just fixed and sends you chasing it twice. Check the build result explicitly;
   do not pipe it to `/dev/null` and assume.
2. **Drive the app into the state you changed.** See "Reaching hard states".
3. **Capture.** Screenshot for layout, video for motion.
4. **Read the image back and actually look at it.** Not the filename, not the
   exit code — the pixels.
5. **Crop to the region you changed and inspect at full resolution.** A
   downscaled contact sheet is for surveying many screens at once; it hides
   overflow by a few pixels, doubled glyphs and off-by-one spacing.

Contact sheets are still worth building once you have more than three states:
composite them into a grid, look for the one that differs from its neighbours,
then open that one at full size.

## What to look at

- **Container edges.** Every string that can vary in length: longest product
  name, longest translation, biggest number. Text that fits the placeholder is
  not evidence.
- **The platform's safe area**, not just the screen. TVs overscan; phones have
  notches and home indicators.
- **The extremes of every list**: first row, last row, empty state, single item,
  one more than fits.
- **Components that render twice on one screen.** Two player panels, two score
  labels, a repeated card. If instances that should match do not, that is a bug,
  not a coincidence — chase it rather than assuming animation phase.
- **Overlays against what they cover.** Toasts, banners and modals need their
  own vertical lane or they land on top of a hint row.
- **Both light and dark**, both orientations, both scale factors, if supported.

## Reaching hard states

Most bugs live in states that need hardware, a network failure, or twenty
minutes of play. Build a launch-time override harness so any of them is one
command away:

```swift
#if DEBUG
enum DebugHarness {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var isActive: Bool { env.keys.contains { $0.hasPrefix("NP_") } }
    static func startRoute() -> Route? { /* env["NP_SCENE"] -> a screen */ }
}
#endif
```

Then `SIMCTL_CHILD_NP_SCENE=result xcrun simctl launch <dev> <bundle>`.

Rules that make this pay off:

- **Wrap it in `#if DEBUG`** and verify it is absent from Release with
  `strings <binary> | grep NP_`.
- **Fixtures must derive from the shipping source, never restate it.** A harness
  that hard-codes its own copy of a name, a glyph or a colour will drift, and
  then the simulator shows something the device never renders. This bites
  repeatedly. Give the fixture the same factory the real path uses.
- **Script real input** rather than jumping straight to a seeded screen, when
  the interaction itself is what you are proving. Injecting a button press for
  one frame and releasing it exercises the actual edge-detection path.

## Motion needs video

Stills cannot show a transition that flickers, a particle burst that never
fires, or a paddle that jitters.

```bash
xcrun simctl io <dev> recordVideo --codec h264 out.mp4 &   # kill -INT to stop
ffmpeg -i out.mp4 -vf "fps=1/2,scale=1280:-1" frames/f%02d.png
```

Then composite the frames into a sheet and read the sequence.

## Failure modes that type-check cleanly

Each of these built and ran without warning, and was only visible in a capture:

- **Icons rendering as black silhouettes.** A tinted image whose tint is
  resolved lazily by the UI framework never resolves when handed straight to a
  texture. Flatten it through a real drawing context first.
- **Elements silently losing a layer.** With sibling-order-independent
  rendering, anything layered needs an explicit z; without one, a label can be
  drawn over its own glow at random and look dim on one instance and not the
  other.
- **A glow that doubles the text.** Faking bloom by stacking *scaled* copies
  displaces every glyph in proportion to its distance from the anchor. On a
  short label that passes for a halo; on a long one it is a legible second
  string sitting outside the first. Stack unscaled copies for brightness and put
  a soft blurred shape behind for the halo.
- **Labels overflowing after a data change.** The placeholder fit; the real
  value did not.
- **Two panels that drifted apart** because one code path updated and the other
  did not.

## Reporting

Say which states you inspected and what you saw. Keep the captures. "It builds"
and "should be fine now" are not visual evidence — if you did not look, say so.
