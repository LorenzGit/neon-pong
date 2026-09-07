import AVFoundation

/// Every sound in the game is synthesised at launch, so the app ships with no
/// audio files and the bleeps stay true to the original hardware.
enum SFX: CaseIterable {
    case paddleHit
    case paddleHitHard
    case wallHit
    case score
    case explosion
    case powerUpSpawn
    case powerUpGood
    case powerUpBad
    case countdown
    case countdownGo
    case matchWin
    case achievement
    case uiMove
    case uiConfirm
    case uiBack
    case controllerJoin
    case controllerLeave
    case controllerLost
}

final class SoundEngine {

    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [SFX: AVAudioPCMBuffer] = [:]
    private var started = false

    private let sampleRate: Double = 44_100
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio is a nice-to-have; a failure here must not stop the game.
        }

        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        // A small pool lets overlapping hits ring out instead of cutting each other.
        for _ in 0..<10 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: format)
            players.append(player)
        }

        SFX.allCases.forEach { buffers[$0] = render($0) }

        do {
            try engine.start()
            players.forEach { $0.play() }
        } catch {
            started = false
        }
    }

    func play(_ sfx: SFX, volume: Float = 1.0) {
        guard SaveStore.shared.soundEnabled, started,
              let buffer = buffers[sfx], !players.isEmpty else { return }
        let player = players[nextPlayer % players.count]
        nextPlayer += 1
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Synthesis

    private func render(_ sfx: SFX) -> AVAudioPCMBuffer? {
        let samples: [Float]
        switch sfx {
        case .paddleHit:
            samples = Synth.blip(frequency: 520, duration: 0.055, wave: .square, decay: 26)
        case .paddleHitHard:
            samples = Synth.mix([
                Synth.sweep(from: 720, to: 380, duration: 0.09, wave: .square, decay: 20),
                Synth.noise(duration: 0.05, decay: 60, amplitude: 0.25)
            ])
        case .wallHit:
            samples = Synth.blip(frequency: 240, duration: 0.05, wave: .square, decay: 30)
        case .score:
            samples = Synth.sweep(from: 660, to: 120, duration: 0.42, wave: .square, decay: 6)
        case .explosion:
            samples = Synth.mix([
                Synth.noise(duration: 0.55, decay: 7.5, amplitude: 0.85),
                Synth.sweep(from: 180, to: 32, duration: 0.5, wave: .sine, decay: 6, amplitude: 0.7)
            ])
        case .powerUpSpawn:
            samples = Synth.arpeggio([440, 587, 784], noteDuration: 0.055, wave: .triangle, decay: 22)
        case .powerUpGood:
            samples = Synth.arpeggio([784, 988, 1319, 1568], noteDuration: 0.05, wave: .square, decay: 18)
        case .powerUpBad:
            samples = Synth.arpeggio([392, 330, 262], noteDuration: 0.07, wave: .square, decay: 16)
        case .countdown:
            samples = Synth.blip(frequency: 440, duration: 0.12, wave: .sine, decay: 12)
        case .countdownGo:
            samples = Synth.blip(frequency: 880, duration: 0.24, wave: .sine, decay: 7)
        case .matchWin:
            samples = Synth.arpeggio([523, 659, 784, 1047, 1319], noteDuration: 0.11,
                                     wave: .square, decay: 9)
        case .achievement:
            samples = Synth.arpeggio([659, 880, 1319], noteDuration: 0.09, wave: .triangle, decay: 11)
        case .uiMove:
            samples = Synth.blip(frequency: 900, duration: 0.028, wave: .square, decay: 90, amplitude: 0.45)
        case .uiConfirm:
            samples = Synth.arpeggio([660, 990], noteDuration: 0.05, wave: .square, decay: 22, amplitude: 0.6)
        case .uiBack:
            samples = Synth.arpeggio([440, 300], noteDuration: 0.05, wave: .square, decay: 22, amplitude: 0.5)
        case .controllerJoin:
            samples = Synth.arpeggio([523, 784, 1047], noteDuration: 0.07, wave: .triangle, decay: 13)
        case .controllerLeave:
            samples = Synth.arpeggio([784, 523], noteDuration: 0.07, wave: .triangle, decay: 13)
        case .controllerLost:
            samples = Synth.arpeggio([400, 300, 400, 300], noteDuration: 0.09, wave: .square, decay: 14)
        }
        return Synth.buffer(from: samples, format: format)
    }
}

/// Tiny waveform synthesiser. Everything returns mono float samples at 44.1 kHz.
enum Synth {

    enum Wave {
        case sine, square, triangle, saw
    }

    static let sampleRate: Double = 44_100

    private static func sample(_ wave: Wave, phase: Double) -> Float {
        let t = phase.truncatingRemainder(dividingBy: 1.0)
        switch wave {
        case .sine:     return Float(sin(2 * .pi * t))
        case .square:   return t < 0.5 ? 1.0 : -1.0
        case .triangle: return Float(4 * abs(t - 0.5) - 1)
        case .saw:      return Float(2 * t - 1)
        }
    }

    /// A single decaying tone.
    static func blip(frequency: Double, duration: Double, wave: Wave,
                     decay: Double, amplitude: Float = 0.8) -> [Float] {
        sweep(from: frequency, to: frequency, duration: duration,
              wave: wave, decay: decay, amplitude: amplitude)
    }

    /// A tone that glides between two frequencies while decaying.
    static func sweep(from: Double, to: Double, duration: Double, wave: Wave,
                      decay: Double, amplitude: Float = 0.8) -> [Float] {
        let count = Int(duration * sampleRate)
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        for i in 0..<count {
            let progress = Double(i) / Double(count)
            let frequency = from + (to - from) * progress
            phase += frequency / sampleRate
            let envelope = Float(exp(-decay * progress * duration * 10)) * amplitude
            out[i] = sample(wave, phase: phase) * envelope
        }
        return applyEdgeFade(out)
    }

    /// White noise with an exponential decay, the base of every explosion.
    static func noise(duration: Double, decay: Double, amplitude: Float = 0.8) -> [Float] {
        let count = Int(duration * sampleRate)
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        // One-pole low pass gives the burst body instead of a hiss.
        var last: Float = 0
        var generator = SystemRandomNumberGenerator()
        for i in 0..<count {
            let progress = Double(i) / Double(count)
            let white = Float.random(in: -1...1, using: &generator)
            last += (white - last) * 0.34
            let envelope = Float(exp(-decay * progress * duration * 10)) * amplitude
            out[i] = last * envelope
        }
        return applyEdgeFade(out)
    }

    /// Notes played back to back, used for chimes and fanfares.
    static func arpeggio(_ frequencies: [Double], noteDuration: Double, wave: Wave,
                         decay: Double, amplitude: Float = 0.75) -> [Float] {
        frequencies.flatMap {
            blip(frequency: $0, duration: noteDuration, wave: wave,
                 decay: decay, amplitude: amplitude)
        }
    }

    /// Sums layers, keeping the result inside -1...1.
    static func mix(_ layers: [[Float]]) -> [Float] {
        let count = layers.map(\.count).max() ?? 0
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        for layer in layers {
            for i in 0..<layer.count { out[i] += layer[i] }
        }
        let peak = out.map(abs).max() ?? 1
        if peak > 1 {
            for i in 0..<count { out[i] /= peak }
        }
        return out
    }

    /// Removes the click a hard start or stop would otherwise produce.
    private static func applyEdgeFade(_ input: [Float], milliseconds: Double = 2) -> [Float] {
        var out = input
        let fade = min(Int(milliseconds / 1000 * sampleRate), out.count / 2)
        guard fade > 1 else { return out }
        for i in 0..<fade {
            let gain = Float(i) / Float(fade)
            out[i] *= gain
            out[out.count - 1 - i] *= gain
        }
        return out
    }

    static func buffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
