---
name: arcade-game-feel
description: Make a small action game feel good — hand-rolled deterministic physics that never tunnels, bounce rules players can read, screen shake, particles, power-ups, achievements and procedurally synthesised sound. Use when building or tuning an arcade game loop, when a fast object passes through a wall or paddle, when hits feel weak, or when adding pickups, juice or an achievement system.
---

# Arcade game feel

## Roll your own physics for a ball-and-paddle game

A 2D physics engine is the wrong tool when there is one moving body and the
bounce rule is a design decision. Hand integration is deterministic, tunable,
and about thirty lines.

**Sub-step or you will tunnel.** At 2000 units/second and 60fps a ball moves 33
units per frame and passes straight through a 24-unit paddle. Size the step from
the geometry, not from a guess:

```swift
let steps = max(1, Int(ceil(ball.speed * dt / (ball.radius * 0.7))))
let sub = dt / CGFloat(steps)
for _ in 0..<steps {
    ball.position += ball.velocity * sub
    resolveWalls(ball); resolvePaddles(ball); resolvePickups(ball)
    if scored { break }
}
```

**The bounce rule is the game.** In Pong the angle comes from *where on the bat*
you hit, not from the incoming angle. That is what makes it a game of placement
rather than reflexes:

```swift
let offset = clamp((ball.y - paddle.centerY) / (paddle.halfHeight + ball.radius), -1, 1)
let angle  = offset * maxBounceAngle          // ~58°
var speed  = min(ball.speed + rallyAccel, maxSpeed)
let dir: CGFloat = paddle.isLeft ? 1 : -1
var (vx, vy) = (cos(angle) * speed * dir, sin(angle) * speed)
vy += paddle.velocityY * 0.20                 // a little english from the bat
```

Then renormalise to `speed`, and **floor the horizontal component**
(`abs(vx) >= speed * 0.36`) or a near-vertical rally stalls forever.

Reposition the ball onto the contact face before applying the new velocity, and
reject contacts where it is already well behind the bat, or a fast ball gets
grabbed backwards.

## Juice, in rough order of value per line

1. **Screen shake.** Shake a container node, not the camera, and keep chrome
   outside it. Square the trauma so small hits stay subtle and big ones do not:
   `offset = trauma² * maxOffset * random(-1...1)`, decaying ~2/second.
2. **Squash and stretch** on the thing that got hit — 0.05s out, 0.16s back.
3. **A comet trail** on the moving object, tinted to whoever last touched it.
   Ownership becomes readable at a glance during a scramble.
4. **Sparks on contact**, emitted along the surface normal, count and speed
   scaled by impact force.
5. **An expanding ring** on the big moments. Use a ring *texture* — scaling an
   `SKShapeNode` circle 50× makes its path flattening show as radial spokes.
6. **Rumble the pad that earned it**, not both.
7. **Slow motion on the winning point.** A `timeScale` multiplier on delta time
   for a second before the result screen.

Scale all of it by impact force so a soft return and a hard one do not feel the
same:

```swift
let power = clamp(speed / maxSpeed, 0.25, 1.0)
shake.add(0.08 + 0.14 * power)
sound.play(power > 0.7 ? .hitHard : .hit, volume: 0.6 + 0.35 * power)
```

Put shake behind a setting. Some people cannot play with it on.

## Power-ups

Keep the claim rule stateable in one sentence — "whoever last touched the ball
that hits it" — and never make the player infer it. Show who got what.

Split them into **timed** and **instant** and let the type drive the UI: timed
effects get a HUD chip with a countdown bar, instant ones just fire. Balance
self-buffs against opponent-debuffs so both are worth chasing.

Weight the spawn table rather than picking uniformly; the loud ones (multiball,
fireball) should be rarer than the steady modifiers.

Two things that bite:

- **Clear ball-bound effects when the point ends**, and rebuild the HUD when you
  do, or a chip sits there with a frozen timer.
- **Refresh, do not stack.** Collecting the same power-up twice should reset the
  timer, not queue a second one.

Announce a pickup **once**. A centre banner and a bottom toast for the same
event is noise; pick the one that can say both what happened and to whom.

## Achievements

Model them as `id, title, one-line requirement, target, tint`. `target == 1` is
a one-shot, above that is a counter with a progress bar — the bar is what makes
a locked achievement feel reachable instead of decorative.

Feed a tracker with events rather than sprinkling `unlock()` through gameplay:

```swift
enum Event { case pointScored(by: Slot), rallyEnded(hits: Int),
             case powerUpCollected(Kind), case matchFinished(Result, Config) }
```

Persist progress as `[id: Int]`. Guard announcements with an in-memory `Set` so
a toast fires once per session even if the event repeats, and do not touch
storage every frame — only record a "peak value" event when the peak actually
moves.

Keep a handful reachable in the first session; a wall of locked rows on first
launch reads as a chore list.

## Synthesise the sound

For arcade bleeps you do not need audio files. Render float buffers at launch
and play them through a pool of `AVAudioPlayerNode`s:

```swift
func sweep(from: Double, to: Double, duration: Double, wave: Wave,
           decay: Double, amplitude: Float) -> [Float]
```

A square-wave blip is a paddle hit; a downward sweep is a goal; low-passed white
noise with an exponential decay is an explosion; three rising notes is an
unlock. Fade 2ms at each end or every sound clicks.

Use a pool of ~10 players round-robin so overlapping hits ring out instead of
cutting each other. Set the session to `.ambient` with `.mixWithOthers` so you do
not stop someone's music. Treat the whole engine as best-effort — wrap start in
`do/catch` and let the game run silent if it fails.

`AVAudioPlayerNode.rate` is 3D-mixing Doppler, not playback pitch. It will not
pitch-shift your blip.

## Making the CPU beatable

Predict where the ball crosses the paddle's plane, folding the prediction back
inside the walls for bounces. Then make it worse on purpose:

- blend the prediction with the ball's *current* position — a weak CPU mostly
  chases, which is exactly how a weak human plays
- add a per-rally aim error, re-rolled when the ball changes direction
- cap paddle speed per difficulty

Three difficulties differing in prediction, error and speed cover everyone.
