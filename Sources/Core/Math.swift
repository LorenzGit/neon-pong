import CoreGraphics
import Foundation

@inline(__always)
func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

@inline(__always)
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * clamp(t, 0, 1)
}

/// Frame-rate independent exponential smoothing.
/// `rate` is roughly "fraction closed per second".
@inline(__always)
func damp(_ current: CGFloat, _ target: CGFloat, rate: CGFloat, dt: CGFloat) -> CGFloat {
    let t = 1 - exp(-rate * dt)
    return current + (target - current) * t
}

/// Removes stick drift and rescales the live range so the full 0...1 is usable.
@inline(__always)
func deadzone(_ value: Float, _ threshold: Float = 0.14) -> CGFloat {
    let magnitude = abs(value)
    guard magnitude > threshold else { return 0 }
    let scaled = (magnitude - threshold) / (1 - threshold)
    return CGFloat(scaled * (value < 0 ? -1 : 1))
}

extension CGFloat {
    var sign01: CGFloat { self < 0 ? -1 : 1 }
}
