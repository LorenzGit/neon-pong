---
name: fixture-fidelity
description: Keep test fixtures, mocks, seed data, debug harnesses and preview providers from drifting away from the code they stand in for, so what you verify is what ships. Use when writing or changing a fixture, mock, stub, seeded state, SwiftUI preview or debug override, and when a bug reproduces in the real app but not in the harness (or the reverse).
---

# Fixture fidelity

A fixture that restates what the shipping code defines will diverge from it. The
divergence compiles, the tests stay green, and you end up verifying a thing that
does not exist.

This is not hypothetical: in one session a debug harness fabricated controller
profiles by writing out every button glyph as a literal. The real detection code
was fixed; the harness was not. The simulator kept rendering the old, wrong
prompt, so the fix looked like it had failed. It happened a second time in the
same file within the hour with a hard-coded product name.

## The rule

**Fixtures may choose inputs. They may not restate outputs.**

Pick which case you want — this brand, that error, an empty list — and then let
the production code derive everything downstream of that choice.

```swift
// Drifts. Every glyph is a second, unmaintained definition.
ControllerProfile(brand: .siriRemote, confirmSymbol: "circle.circle.fill",
                  backSymbol: "chevron.left.circle.fill", backName: "Back", …)

// Cannot drift. The fixture picks a brand; the type derives the rest.
ControllerProfile(brand: .siriRemote,
                  displayName: ControllerProfile.defaultName(.siriRemote))
```

The refactor that gets you there is usually the same shape: move the derived
values from stored properties set at every construction site to computed
properties on the type, then delete the literals.

## Where this hides

- **Debug and preview harnesses** that build a "realistic looking" object by
  hand.
- **Seed scripts** that write records the app would write differently.
- **Golden files and snapshots** regenerated from a mock rather than the real
  renderer.
- **Docs and README snippets** quoting output that has since changed.
- **Two enums** — one in the model, one in the fixture — that must be kept in
  step by hand.
- **A hard-coded string in a test** asserting a message the code now words
  differently.

## Symptoms

- A fix works in production but the harness still shows the old behaviour, or
  the reverse.
- A test asserts a literal that no longer appears anywhere else in the codebase.
- Grep for a string finds it exactly twice, in two files that never change
  together.
- Someone says "it works on the device but not in the simulator" about something
  with no device-specific code.

## When you find one

Delete the duplicate rather than syncing it. Syncing buys one release. If the
values genuinely cannot be shared — different module, different language, a wire
format — then make the mismatch loud: a test that compares the two, or a
generator that emits one from the other.

## Related

Fixture drift is invisible to the compiler and, for anything drawn, invisible in
a diff. Pair this with `visual-qa-pass`: after fixing the real path, re-render
through the harness and confirm it now shows what the real path produces.
