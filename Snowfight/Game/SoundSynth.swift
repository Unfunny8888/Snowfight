import AVFoundation
import Foundation

/// All audio is synthesized at launch into in-memory WAV data — no asset
/// files. The character of the original game came from its childlike voices
/// (the "ow!", the wailing cry of a downed kid, the giggles) over soft snow
/// foley and a jaunty toy tune; every one of those is recreated here with a
/// tiny formant-ish voice synth and a chiptune music loop.
final class Sound {
    static let shared = Sound()

    var sfxEnabled: Bool {
        didSet { UserDefaults.standard.set(sfxEnabled, forKey: GameConfig.sfxEnabledKey) }
    }
    var musicEnabled: Bool {
        didSet {
            UserDefaults.standard.set(musicEnabled, forKey: GameConfig.musicEnabledKey)
            if musicEnabled { startMusic() } else { musicPlayer?.pause() }
        }
    }

    private var pools: [String: [AVAudioPlayer]] = [:]
    private var poolIndex: [String: Int] = [:]
    private var musicPlayer: AVAudioPlayer?

    private init() {
        let defaults = UserDefaults.standard
        sfxEnabled = defaults.object(forKey: GameConfig.sfxEnabledKey) as? Bool ?? true
        musicEnabled = defaults.object(forKey: GameConfig.musicEnabledKey) as? Bool ?? true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)

        register("throw", data: Synth.throwSound(), voices: 4)
        register("splat", data: Synth.splat(), voices: 4)
        register("hit", data: Synth.hitSound(), voices: 3)      // thud + "ow!"
        register("ko", data: Synth.cry(), voices: 2)            // the famous wail
        register("pickup", data: Synth.giggle(), voices: 2)
        register("click", data: Synth.click(), voices: 2)
        register("cheer", data: Synth.cheer(), voices: 1)       // round / level won
        register("gameover", data: Synth.sadWail(), voices: 1)

        if let music = try? AVAudioPlayer(data: Synth.music()) {
            music.numberOfLoops = -1
            music.volume = 0.30
            music.prepareToPlay()
            musicPlayer = music
        }
    }

    /// Warms the singleton (synthesis + audio session + player pools) on a
    /// background queue so scene presentation never blocks on it, then starts
    /// the tune if enabled.
    static func warmUp() {
        DispatchQueue.global(qos: .utility).async {
            let sound = Sound.shared
            DispatchQueue.main.async {
                if sound.musicEnabled { sound.startMusic() }
            }
        }
    }

    func startMusic() {
        guard musicEnabled, let musicPlayer, !musicPlayer.isPlaying else { return }
        musicPlayer.play()
    }

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
        guard sfxEnabled, let pool = pools[name], !pool.isEmpty else { return }
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

    // MARK: - WAV container

    private static func wavData(_ samples: [Float]) -> Data {
        let byteCount = samples.count * 2
        var data = Data()
        data.reserveCapacity(44 + byteCount)

        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(16)
        append16(1)                     // PCM
        append16(1)                     // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
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

    /// Mixes `overlay` into `base` starting at `offset` samples, growing base if needed.
    private static func mix(_ base: [Float], _ overlay: [Float], offset: Int = 0, gain: Float = 1) -> [Float] {
        var out = base
        if offset + overlay.count > out.count {
            out.append(contentsOf: [Float](repeating: 0, count: offset + overlay.count - out.count))
        }
        for (i, sample) in overlay.enumerated() {
            out[offset + i] += sample * gain
        }
        return out
    }

    // MARK: - Kid voice synth

    /// A pitch-glide segment of "voice"; frequency 0 means silence (a breath gap).
    struct VoiceSeg {
        var from: Float
        var to: Float
        var duration: Float
    }

    /// Little formant-ish voice: a gliding fundamental with weighted harmonics,
    /// optional tremolo wobble (for wailing), and breath noise. This is what
    /// makes the kids sound like kids.
    private static func voice(_ segments: [VoiceSeg],
                              harmonics: [Float],
                              tremoloRate: Float = 0,
                              tremoloDepth: Float = 0,
                              breath: Float = 0.1,
                              amp: Float = 0.5) -> [Float] {
        var samples: [Float] = []
        var rng = Rand(state: 24601)
        var phase: Float = 0
        let dt = Float(1.0 / sampleRate)
        var globalT: Float = 0

        for seg in segments {
            let count = Int(Float(sampleRate) * seg.duration)
            samples.reserveCapacity(samples.count + count)
            for i in 0..<count {
                let t = Float(i) / Float(max(count, 1))
                guard seg.from > 0 else {
                    samples.append(0)
                    globalT += dt
                    continue
                }
                let f0 = seg.from + (seg.to - seg.from) * t
                phase += 2 * .pi * f0 * dt
                var tone: Float = 0
                for (k, weight) in harmonics.enumerated() {
                    tone += weight * sinf(phase * Float(k + 1))
                }
                // soft envelope per segment, so each syllable swells and fades
                let envelope = powf(sinf(t * .pi), 0.6)
                var tremolo: Float = 1
                if tremoloRate > 0 {
                    tremolo = 1 - tremoloDepth * (0.5 + 0.5 * sinf(2 * .pi * tremoloRate * globalT))
                }
                let noise = rng.next() * breath
                samples.append((tone + noise) * envelope * tremolo * amp)
                globalT += dt
            }
        }
        return samples
    }

    private static let kidHarmonics: [Float] = [1.0, 0.55, 0.30, 0.16, 0.08]

    /// Sharp little "ow!" for a body hit.
    static func owVoice() -> [Float] {
        voice([VoiceSeg(from: 340, to: 195, duration: 0.17)],
              harmonics: kidHarmonics, breath: 0.14, amp: 0.5)
    }

    /// The wailing "waa-aah" of a knocked-out kid — the signature sound.
    static func cry() -> Data {
        let wail = voice([
            VoiceSeg(from: 430, to: 385, duration: 0.28),
            VoiceSeg(from: 0, to: 0, duration: 0.06),
            VoiceSeg(from: 405, to: 235, duration: 0.42),
        ], harmonics: [1.0, 0.6, 0.36, 0.2, 0.1],
           tremoloRate: 5.5, tremoloDepth: 0.42, breath: 0.10, amp: 0.42)
        return wavData(wail)
    }

    /// Losing wail for the game-over screen: longer, droopier.
    static func sadWail() -> Data {
        let wail = voice([
            VoiceSeg(from: 330, to: 300, duration: 0.3),
            VoiceSeg(from: 0, to: 0, duration: 0.05),
            VoiceSeg(from: 310, to: 170, duration: 0.55),
        ], harmonics: [1.0, 0.55, 0.3, 0.15],
           tremoloRate: 4.5, tremoloDepth: 0.5, breath: 0.12, amp: 0.4)
        return wavData(wail)
    }

    /// Bright "yaay!" — two little voices gliding up together.
    static func cheer() -> Data {
        let low = voice([VoiceSeg(from: 320, to: 520, duration: 0.38)],
                        harmonics: kidHarmonics, tremoloRate: 6, tremoloDepth: 0.18, breath: 0.08, amp: 0.3)
        let high = voice([VoiceSeg(from: 405, to: 650, duration: 0.38)],
                         harmonics: kidHarmonics, tremoloRate: 6.5, tremoloDepth: 0.18, breath: 0.08, amp: 0.24)
        return wavData(mix(low, high))
    }

    /// Staccato giggle for grabbing a power-up.
    static func giggle() -> Data {
        let g = voice([
            VoiceSeg(from: 480, to: 530, duration: 0.06),
            VoiceSeg(from: 0, to: 0, duration: 0.045),
            VoiceSeg(from: 520, to: 570, duration: 0.06),
            VoiceSeg(from: 0, to: 0, duration: 0.045),
            VoiceSeg(from: 560, to: 610, duration: 0.06),
            VoiceSeg(from: 0, to: 0, duration: 0.045),
            VoiceSeg(from: 505, to: 545, duration: 0.09),
        ], harmonics: [1.0, 0.5, 0.25], breath: 0.12, amp: 0.34)
        return wavData(g)
    }

    // MARK: - Foley

    /// Airy noise sweep plus a tiny effort grunt: the throw.
    static func throwSound() -> Data {
        let n = Int(sampleRate * 0.18)
        var rng = Rand(state: 12345)
        var swoosh = [Float](repeating: 0, count: n)
        var smooth: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(n)
            let envelope = sinf(t * .pi)
            let alpha = 0.15 + 0.5 * t
            smooth += (rng.next() - smooth) * alpha
            swoosh[i] = smooth * envelope * 0.45
        }
        let hup = voice([VoiceSeg(from: 235, to: 155, duration: 0.09)],
                        harmonics: [1.0, 0.4, 0.2], breath: 0.3, amp: 0.22)
        return wavData(mix(swoosh, hup))
    }

    /// Soft fluffy snow splat.
    static func splat() -> Data {
        let n = Int(sampleRate * 0.13)
        var rng = Rand(state: 777)
        var samples = [Float](repeating: 0, count: n)
        var smooth: Float = 0
        for i in 0..<n {
            let t = Float(i) / Float(n)
            let envelope = expf(-t * 6.5)
            smooth += (rng.next() - smooth) * 0.18
            samples[i] = smooth * envelope * 0.9
        }
        return wavData(samples)
    }

    /// Body hit: low thud with an "ow!" right on top.
    static func hitSound() -> Data {
        let n = Int(sampleRate * 0.15)
        var rng = Rand(state: 4242)
        var thud = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i) / Float(n)
            let envelope = expf(-t * 9)
            let tone = sinf(2 * .pi * (120 - 50 * t) * Float(i) / Float(sampleRate))
            let noise = rng.next() * expf(-t * 30) * 0.5
            thud[i] = (tone * 0.7 + noise) * envelope
        }
        return wavData(mix(thud, owVoice(), offset: Int(sampleRate * 0.02), gain: 0.9))
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

    // MARK: - Music

    /// Jaunty original toy-box loop: staccato triangle-ish melody, bouncing
    /// bass, brushed off-beat hats. Eight bars, loops seamlessly.
    static func music() -> Data {
        let bpm: Float = 132
        let eighth = 60.0 / bpm / 2
        let barEighths = 8
        // (bar, eighth-in-bar, midi, length-in-eighths)
        let melody: [(Int, Int, Int, Int)] = [
            (0,0,72,1),(0,1,76,1),(0,2,79,1),(0,3,76,1),(0,4,81,2),(0,6,79,2),
            (1,0,76,1),(1,1,72,1),(1,2,74,1),(1,3,76,1),(1,4,72,2),(1,6,67,2),
            (2,0,74,1),(2,1,77,1),(2,2,81,1),(2,3,77,1),(2,4,79,2),(2,6,77,2),
            (3,0,76,1),(3,1,74,1),(3,2,71,1),(3,3,74,1),(3,4,72,4),
            (4,0,72,1),(4,1,76,1),(4,2,79,1),(4,3,76,1),(4,4,81,2),(4,6,79,2),
            (5,0,76,1),(5,1,72,1),(5,2,74,1),(5,3,76,1),(5,4,72,2),(5,6,67,2),
            (6,0,77,1),(6,1,81,1),(6,2,84,1),(6,3,81,1),(6,4,79,2),(6,6,76,2),
            (7,0,74,1),(7,1,76,1),(7,2,74,1),(7,3,71,1),(7,4,72,4),
        ]
        // root/fifth bounce per bar: C Am Dm G C Am F C
        let bassBars: [[Int]] = [
            [48,55,48,55],[45,52,45,52],[50,57,50,57],[43,50,43,50],
            [48,55,48,55],[45,52,45,52],[41,48,41,48],[48,55,48,50],
        ]

        let totalBars = 8
        let totalSamples = Int(Float(sampleRate) * eighth * Float(barEighths * totalBars))
        var samples = [Float](repeating: 0, count: totalSamples)

        func hz(_ midi: Int) -> Float {
            440 * powf(2, (Float(midi) - 69) / 12)
        }

        func addNote(midi: Int, startEighths: Float, lenEighths: Float,
                     amp: Float, second: Float, third: Float, staccato: Float) {
            let start = Int(Float(sampleRate) * eighth * startEighths)
            let length = Int(Float(sampleRate) * eighth * lenEighths * staccato)
            let f = hz(midi)
            var phase: Float = 0
            for i in 0..<length where start + i < totalSamples {
                let t = Float(i) / Float(max(length, 1))
                phase += 2 * .pi * f / Float(sampleRate)
                let envelope = min(t * 30, 1) * (1 - t * t)  // pluck
                let tone = sinf(phase) + second * sinf(phase * 2) + third * sinf(phase * 3)
                samples[start + i] += tone * envelope * amp
            }
        }

        for (bar, pos, midi, len) in melody {
            addNote(midi: midi, startEighths: Float(bar * barEighths + pos), lenEighths: Float(len),
                    amp: 0.20, second: 0.35, third: 0.14, staccato: 0.82)
        }
        for (bar, quarters) in bassBars.enumerated() {
            for (q, midi) in quarters.enumerated() {
                addNote(midi: midi, startEighths: Float(bar * barEighths + q * 2), lenEighths: 2,
                        amp: 0.16, second: 0.20, third: 0.0, staccato: 0.6)
            }
        }
        // off-beat hat ticks
        var rng = Rand(state: 99)
        for e in stride(from: 1, to: barEighths * totalBars, by: 2) {
            let start = Int(Float(sampleRate) * eighth * Float(e))
            let length = Int(Float(sampleRate) * 0.02)
            for i in 0..<length where start + i < totalSamples {
                let t = Float(i) / Float(length)
                samples[start + i] += rng.next() * (1 - t) * 0.05
            }
        }
        return wavData(samples)
    }
}
