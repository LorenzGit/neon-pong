---
name: spritekit-ui-craft
description: Build screen UI in SpriteKit — text with glow, panels, SF Symbols, procedurally generated textures, menus and TV-safe layout — and avoid the rendering traps that build cleanly but look wrong. Use when laying out SpriteKit scenes, drawing HUDs or menus in a game, generating art in code instead of shipping assets, or debugging "the icon is black", "the label lost its glow", "the text is doubled".
---

# SpriteKit UI craft

SpriteKit gives you a renderer, not a UI toolkit. These are the parts that cost
time.

## Draw order is not what you wrote

`SKView.ignoresSiblingOrder = true` (worth having, it batches) means siblings at
the same `zPosition` draw in **undefined order**. Anything layered — a glow
under a glyph, a fill under a stroke — needs an explicit `zPosition`.

Without one, a crisp label can be drawn *over* its own additive glow, which
looks like the element randomly losing its bloom. Two identical components on
one screen will disagree, and it will look like an animation phase problem. It
is not; give them z values.

## SF Symbols come out black

`UIImage(systemName:)` is a template. `withTintColor(_:renderingMode:)` defers
the tint until the image is drawn in a UIKit context — and `SKTexture(image:)`
never provides one, so you get the raw black glyph.

Flatten it first:

```swift
let cfg = UIImage.SymbolConfiguration(pointSize: size, weight: weight)
guard let symbol = UIImage(systemName: name, withConfiguration: cfg) else { return nil }
let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 2; fmt.opaque = false
let flat = UIGraphicsImageRenderer(size: symbol.size, format: fmt).image { _ in
    symbol.withTintColor(color, renderingMode: .alwaysOriginal)
          .draw(in: CGRect(origin: .zero, size: symbol.size))
}
SKTexture(image: flat)
```

Return `nil` and fall back to text when the symbol name does not exist on the
running OS. Names come and go between releases.

## Glowing text

Two approaches, and the choice is about count.

**Display type** (a handful per screen) can use a real blur:

```swift
let host = SKEffectNode()
host.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": size * 0.16])
host.shouldEnableEffects = true
host.blendMode = .add
host.zPosition = -1          // behind the crisp copy
```

**Body copy** cannot. A screen can hold forty-odd labels, and forty simultaneous
`CIGaussianBlur` passes is more than SpriteKit will reliably render — some effect
nodes silently drop out, so random labels lose their glow.

Fake it, but **do not scale the copies**. Scaling displaces every glyph in
proportion to its distance from the anchor: on a short label it passes for a
halo, on a long one it is a legible second string sitting outside the first, and
on a modal it spills past the panel edge. Instead:

- stack two **unscaled** additive copies for brightness
- put a **stretched radial glow sprite behind**, sized to the rendered text, for
  the outward haze — it has no geometry to double

```swift
haze.size = CGSize(width: crisp.frame.width * 1.35 + h, height: h * 2.6)
```

## Text that fits

`SKLabelNode` does not wrap or truncate usefully. Anything holding variable text
needs an explicit fit:

```swift
@discardableResult
func fitting(width: CGFloat) -> Self {
    let measured = contentWidth
    if measured > width, measured > 0 { setScale(width / measured) }
    return self
}
```

Apply it to every label that shows a device name, a player name, a localised
string or a number that can grow. Measure the container's *inner* width — a neon
border and its glow need air, so subtract more than you think.

Use `attributedText` rather than `fontName` + `fontSize`: it gives you real
system fonts including weights SpriteKit will not resolve by name, plus `.kern`
for the letter-spacing that sells arcade and editorial type.

```swift
NSAttributedString(string: s, attributes: [
    .font: UIFont.systemFont(ofSize: size, weight: .black),
    .foregroundColor: color,
    .kern: tracking
])
```

## Generate textures instead of shipping assets

Core Graphics into `SKTexture` covers most game UI, stays crisp at any
resolution, and keeps the whole look tweakable from one palette file. Cache by a
key built from the parameters.

```swift
private static var cache: [String: SKTexture] = [:]
static func cached(_ key: String, _ build: () -> UIImage) -> SKTexture { ... }
```

Worth having: radial glow (gradient with `pow(1 - t, falloff)` alpha), capsule,
disc, ring, rounded panel with stroke, vignette, scanlines, a 4×4 white pixel
for tinted rectangles.

Two specifics:

- **Scale a ring sprite, never an `SKShapeNode` circle.** Scaling a shape node
  50× makes its path flattening visible as radial spokes. A ring *texture* stays
  smooth at any size.
- **Bake repeating overlays into one texture.** Full-screen scanlines as one
  sprite, not 270 line nodes. Draw in points and remember the renderer scale:
  a 2pt line becomes 4 device pixels at 2x and reads as banding rather than a
  CRT.

## TV-safe layout

TVs overscan. Keep everything meaningful inside roughly 90×60pt of the edges of
a 1920×1080 space, and lay the screen out in **lanes** so nothing collides:

```
1020  ── safe top ──
 950     score / title
 870     status chips
 130-838 play field or content
 132     button hint row
  58     toast lane
  60  ── safe bottom ──
```

Give transient overlays their own lane. A toast that appears over the hint row
looks like a bug even though both are correct in isolation.

## Small things that add up

- `scaleMode = .aspectFit` with a fixed design size (1920×1080) gives one
  coordinate space for every device.
- Clamp delta time in `update`: `min(now - last, 1.0/20.0)`. A hitch or a resume
  from background will otherwise teleport everything.
- Shake a container node, not the camera, and keep chrome (vignette, toasts)
  outside it. Square the trauma so small hits stay subtle.
- Ease your actions. SpriteKit defaults to linear and it always reads as cheap.
- `SKCropNode` with a sprite mask for scrolling lists, plus a gradient fade at
  the clipped edge so a half-visible row reads as intentional.
