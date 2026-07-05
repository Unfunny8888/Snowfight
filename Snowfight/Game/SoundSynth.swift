import AVFoundation
import Foundation

/// All sound effects are synthesized at launch into in-memory WAV data and
/// played through pooled AVAudioPlayers — no audio asset files required.
final class Sound {
    static let shared = Sound()

    var isMuted = false

    private var pools: [String: [AVAudioPlayer]] = [:]
    private var poolIndex: [String: Int] = [:]

    private init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)

        register("throw", data: Synth.swoosh(), voices: 4)
        register("splat", data: Synth.splat(), voices: 4)
        register("thud", data: Synth.thud(), voices: 3)
        register("ko", data: Synth.knockout(), voices: 2)
        register("pickup", data: Synth.pickup(), voices: 2)
        register("click", data: Synth.click(), voices: 2)
        register("levelup", data: Synth.jingle([523.25, 659.25, 783.99, 1046.5], noteLength: 0.13), voices: 1)
        register("gameover", data: Synth.jingle([392.0, 329.63, 261.63, 196.0], noteLength: 0.2), voices: 1)
    }

    /// Call early so the singleton (and audio session) initializes off the hot path.
    func prime() {}

    private func register(_ name: String, data: Data, voices: Int) {
        var players: [AVAudioPlayer] = []
        for _ in 0..<voices {
            if let player = try? AVAudioPlayer(data: data) {
                player.prepareToPlay()
                players.append(player)
            }
        }
        pools[name] = players
        poolIndex[name] = 0
    }

    func play(_ name: String, volume: Float = 0.8) {
        guard !isMuted, let pool = pools[name], !pool.isEmpty else { return }
        let index = (poolIndex[name] ?? 0) % pool.count
        poolIndex[name] = index + 1
        let player = pool[index]
        player.volume = volume
        player.currentTime = 0
        player.play()
    }
}

/// Minimal PCM synthesizer producing 16-bit mono WAV data.
enum Synth {
    static let sampleRate = 22050.0

    private static func wavData(_ samples: [Float]) -> Data {
        var data = Data()
        let byteCount = samples.count * 2

        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(16)                      // fmt chunk size
        append16(1)                     // PCM
        append16(1)                     // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))  // byte rate
        append16(2)                     // block align
        append16(16)                    // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(byteCount))

        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append16(UInt16(bitPattern: Int16(clamped * 32000)))
        }
        return data
    }

    private struct Rand {
        var state: UInt64
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 40) / Float(1 << 24) * 2 - 1
        }
    }

    /// Airy noise sweep for throwing.
    static func swoosh() -> Data {
        let n = Int(sampleRate * 0.18)
        var rng = Rand(state: 12345)
        var samples = [Float](repeating: 0, count: n)
        var smooth: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(n)
            let envelope = sinf(t * .pi)
            // narrowing smoothing window = rising "pitch"
            let alpha = 0.15 + 0.5 * t
            smooth += (rng.next() - smooth) * alpha
            samples[i] = smooth * envelope * 0.5
        }
        return wavData(samples)
    }

    /// Soft snow splat.
    static func splat() -> Data {
        let n = Int(sampleRate * 0.12)
        var rng = Rand(state: 777)
        var samples = [Float](repeating: 0, count: n)
        var smooth: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(n)
            let envelope = expf(-t * 7)
            smooth += (rng.next() - smooth) * 0.25
            samples[i] = smooth * envelope * 0.9
        }
        return wavData(samples)
    }

    /// Body hit thud: low sine with noisy attack.
    static func thud() -> Data {
        let n = Int(sampleRate * 0.15)
        var rng = Rand(state: 4242)
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i) / Float(n)
            let envelope = expf(-t * 9)
            let tone = sinf(2 * .pi * (120 - 50 * t) * Float(i) / Float(sampleRate))
            let noise = rng.next() * expf(-t * 30) * 0.5
            samples[i] = (tone * 0.8 + noise) * envelope
        }
        return wavData(samples)
    }

    /// Descending wobble for a knocked-out kid.
    static func knockout() -> Data {
        let n = Int(sampleRate * 0.4)
        var samples = [Float](repeating: 0, count: n)
        var phase: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(n)
            let freq = 440 - 300 * t + 30 * sinf(t * 40)
            phase += 2 * .pi * freq / Float(sampleRate)
            let envelope = (1 - t) * 0.5
            samples[i] = (sinf(phase) > 0 ? 0.6 : -0.6) * envelope // square-ish
        }
        return wavData(samples)
    }

    /// Bright pickup blip.
    static func pickup() -> Data {
        let n = Int(sampleRate * 0.2)
        var samples = [Float](repeating: 0, count: n)
        var phase: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(n)
            let freq: Float = t < 0.5 ? 660 : 990
            phase += 2 * .pi * freq / Float(sampleRate)
            let envelope = sinf(t * .pi) * 0.5
            samples[i] = sinf(phase) * envelope
        }
        return wavData(samples)
    }

    /// UI click.
    static func click() -> Data {
        let n = Int(sampleRate * 0.05)
        var samples = [Float](repeating: 0, count: n)
        var phase: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(n)
            phase += 2 * .pi * 800 / Float(sampleRate)
            samples[i] = sinf(phase) * (1 - t) * 0.4
        }
        return wavData(samples)
    }

    /// Simple note sequence with soft envelopes (level-up / game-over jingles).
    static func jingle(_ frequencies: [Double], noteLength: Double) -> Data {
        let noteSamples = Int(sampleRate * noteLength)
        var samples = [Float](repeating: 0, count: noteSamples * frequencies.count)
        for (noteIndex, freq) in frequencies.enumerated() {
            var phase: Float = 0
            for i in 0..<noteSamples {
                let t = Float(i) / Float(noteSamples)
                phase += 2 * .pi * Float(freq) / Float(sampleRate)
                let envelope = sinf(t * .pi) * 0.45
                let harmonic = sinf(phase * 2) * 0.2
                samples[noteIndex * noteSamples + i] = (sinf(phase) + harmonic) * envelope
            }
        }
        return wavData(samples)
    }
}
