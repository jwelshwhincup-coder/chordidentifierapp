import Foundation

// A strum is built from single recorded notes started a few milliseconds apart,
// low string to high. Everything here is pure Swift so the same code renders the
// preview files on the Mac and the strum in the app.

// MARK: - Samples

/// Loudness the note was recorded at.
nonisolated enum SampleLayer: String, CaseIterable, Sendable {
    case pp, mf, ff
}

/// One recorded note: recorded string (0 = low E … 5 = high E), fret, loudness.
nonisolated struct SampleKey: Hashable, Sendable {
    let string: Int
    let fret: Int
    let layer: SampleLayer

    var name: String { String(format: "s%d_f%02d_%@", string, fret, layer.rawValue) }
}

nonisolated struct StereoSample: Sendable {
    var left: [Float]
    var right: [Float]
    var sampleRate: Double
    var count: Int { left.count }
}

/// Where recorded notes come from (bundle files in the app, a folder in the preview tool).
nonisolated protocol SampleSource: AnyObject {
    var sampleRate: Double { get }
    func has(_ key: SampleKey) -> Bool
    func sample(_ key: SampleKey) -> StereoSample?
    /// How far the recording is from concert pitch, in cents (+ = sharp).
    func tuningCents(_ key: SampleKey) -> Double
}

/// The open notes of the recorded guitar (standard tuning).
nonisolated let recordedOpenNotes: [Note] = ["E2", "A2", "D3", "G3", "B3", "E4"].map { Note($0)! }

/// Which recording to use for a note, and how far to pitch-shift it.
nonisolated struct SampleChoice: Equatable, Sendable {
    let string: Int
    let fret: Int
    /// Semitones to shift the recording (0 when the exact pitch was recorded).
    let shift: Int
}

nonisolated enum SampleChooser {
    /// Largest shift we'll use; beyond this a note starts to sound artificial.
    /// Only frets 23–24 on the high E (above the highest recorded note, B5) need more.
    static let maxPreferredShift = 3

    /// Picks the recording for `note` played on `playedString` (0 = lowest string).
    ///
    /// The same physical string is preferred, so a note keeps that string's
    /// tone. If the exact pitch wasn't recorded there (fret too high, or the
    /// string is tuned below E2) a neighbouring string with the exact pitch is
    /// used, then the smallest pitch shift.
    static func choose(note: Note, playedString: Int, available: (Int, Int) -> Bool) -> SampleChoice? {
        var best: (cost: Double, choice: SampleChoice)?
        for s in recordedOpenNotes.indices {
            let exactFret = note.midi - recordedOpenNotes[s].midi
            for shift in -12...12 {
                let fret = exactFret - shift
                guard fret >= 0, available(s, fret) else { continue }
                var cost = Double(abs(s - playedString)) * 1.0 + Double(abs(shift)) * 1.6
                if abs(shift) > maxPreferredShift { cost += 20 }
                if best == nil || cost < best!.cost {
                    best = (cost, SampleChoice(string: s, fret: fret, shift: shift))
                }
            }
        }
        return best?.choice
    }
}

// MARK: - Strum style

nonisolated struct StrumStyle: Hashable, Sendable {
    var name: String
    /// Average time between strings, in milliseconds.
    var gapMs: Double
    /// Random variation of each gap, ± milliseconds.
    var gapJitterMs: Double
    /// How hard the strings are hit, 0…1. Chooses the recorded loudness and the level.
    var velocity: Double
    /// How much quieter the last string is than the first, 0…1.
    var easeOff: Double
    /// Gaps get this much longer by the end of the strum (the stroke slows as it eases off).
    var slowDown: Double

    static let gentle = StrumStyle(name: "Gentle", gapMs: 28, gapJitterMs: 5, velocity: 0.4, easeOff: 0.45, slowDown: 0.3)
    static let natural = StrumStyle(name: "Natural", gapMs: 22, gapJitterMs: 5, velocity: 0.62, easeOff: 0.3, slowDown: 0.25)
    static let bright = StrumStyle(name: "Bright", gapMs: 15, gapJitterMs: 2.5, velocity: 0.85, easeOff: 0.15, slowDown: 0.15)
}

// MARK: - Planning

/// One string's part in a strum.
nonisolated struct StrumEvent: Equatable, Sendable {
    /// String on the fretboard (0 = lowest).
    let string: Int
    let note: Note
    /// Seconds after the strum starts.
    let time: Double
    let sample: SampleKey
    /// Total pitch change applied to the recording, in cents
    /// (shift + correction of the recording's tuning + a little human detune).
    let pitchCents: Double
    /// Linear gain.
    let gain: Float
    /// −1 (left) … +1 (right).
    let pan: Float
    /// One-pole low-pass cutoff in Hz, varied a little per note.
    let toneCutoff: Double
}

nonisolated struct StrumPlanner {
    let source: SampleSource

    func plan<R: RandomNumberGenerator>(shape: ChordShape, tuning: Tuning, style: StrumStyle, rng: inout R) -> [StrumEvent] {
        let notes = shape.notesByString(in: tuning)
        let sounding = notes.indices.filter { notes[$0] != nil } // muted strings are skipped
        guard !sounding.isEmpty else { return [] }

        var events: [StrumEvent] = []
        var time = 0.0
        for (position, string) in sounding.enumerated() {
            let note = notes[string]!
            let progress = sounding.count > 1 ? Double(position) / Double(sounding.count - 1) : 0

            if position > 0 {
                let gap = style.gapMs * (1 - style.slowDown / 2 + style.slowDown * progress)
                    + Double.random(in: -style.gapJitterMs...style.gapJitterMs, using: &rng)
                time += max(gap, 6) / 1000
            }

            // Strings further into the stroke are hit a little softer, with a random wobble.
            let velocity = min(max(style.velocity * (1 - style.easeOff * progress)
                                   + Double.random(in: -0.06...0.06, using: &rng), 0.05), 1)
            let layer = Self.layer(for: velocity, rng: &rng)

            guard let choice = SampleChooser.choose(note: note, playedString: string, available: { s, f in
                source.has(SampleKey(string: s, fret: f, layer: layer))
                    || SampleLayer.allCases.contains { source.has(SampleKey(string: s, fret: f, layer: $0)) }
            }) else { continue }

            // Use the chosen loudness, or the nearest one that was recorded.
            let fallbackOrder: [SampleLayer] = layer == .pp ? [.pp, .mf, .ff] : layer == .mf ? [.mf, .pp, .ff] : [.ff, .mf, .pp]
            guard let actualLayer = fallbackOrder.first(where: { source.has(SampleKey(string: choice.string, fret: choice.fret, layer: $0)) })
            else { continue }
            let key = SampleKey(string: choice.string, fret: choice.fret, layer: actualLayer)

            let humanDetune = Double.random(in: -3...3, using: &rng)
            let levelDB = (velocity - 0.62) * 9 + Double.random(in: -1.5...1.5, using: &rng)

            events.append(StrumEvent(
                string: string,
                note: note,
                time: time,
                sample: key,
                pitchCents: Double(choice.shift) * 100 - source.tuningCents(key) + humanDetune,
                gain: Float(pow(10, levelDB / 20)),
                pan: Float(-0.25 + 0.5 * Double(string) / Double(max(tuning.stringCount - 1, 1))),
                toneCutoff: Double.random(in: 5500...12000, using: &rng) * (0.75 + 0.35 * velocity)
            ))
        }
        return events
    }

    /// Soft strums mostly use the quiet recordings, hard ones the loud ones.
    private static func layer<R: RandomNumberGenerator>(for velocity: Double, rng: inout R) -> SampleLayer {
        let r = Double.random(in: -0.08...0.08, using: &rng) + velocity
        if r < 0.38 { return .pp }
        if r < 0.75 { return .mf }
        return .ff
    }
}

// MARK: - Rendering

nonisolated struct RenderedStrum: Sendable {
    var left: [Float]
    var right: [Float]
    let sampleRate: Double
    let events: [StrumEvent]
}

nonisolated enum StrumRenderer {
    /// Fixed output level, set so a hard six-string strum peaks a little below full scale.
    static let masterGain: Float = 0.9

    static func render(_ events: [StrumEvent], source: SampleSource, reverbMix: Float = 0.14) -> RenderedStrum {
        let rate = source.sampleRate
        let tail = 0.4
        let noteSeconds = 4.0
        let total = Int(((events.map(\.time).max() ?? 0) + noteSeconds + tail) * rate)
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)

        for event in events {
            guard let sample = source.sample(event.sample) else { continue }
            let ratio = pow(2, event.pitchCents / 1200)
            let offset = Int(event.time * rate)
            let (l, r) = resample(sample, ratio: ratio)
            let lp = lowPass(coefficient: event.toneCutoff, rate: rate)
            // Equal-power pan applied on top of the stereo recording.
            let angle = (Double(event.pan) + 1) * .pi / 4
            let gl = Float(cos(angle) * sqrt(2)) * event.gain * masterGain
            let gr = Float(sin(angle) * sqrt(2)) * event.gain * masterGain
            var zl: Float = 0, zr: Float = 0
            let n = min(l.count, total - offset)
            guard n > 0 else { continue }
            for i in 0..<n {
                zl += lp * (l[i] - zl)
                zr += lp * (r[i] - zr)
                left[offset + i] += zl * gl
                right[offset + i] += zr * gr
            }
        }

        if reverbMix > 0 {
            var reverb = Reverb(sampleRate: rate)
            reverb.process(left: &left, right: &right, mix: reverbMix)
        }

        // Safety: never clip, even with an unusually loud chord.
        let peak = max(left.map(abs).max() ?? 0, right.map(abs).max() ?? 0)
        if peak > 0.97 {
            let g = 0.97 / peak
            for i in left.indices { left[i] *= g; right[i] *= g }
        }
        // Gentle fade on the very end so the file never stops abruptly.
        let fade = min(Int(tail * rate), total)
        for i in 0..<fade {
            let g = Float(1 - Double(i) / Double(max(fade - 1, 1)))
            left[total - fade + i] *= g
            right[total - fade + i] *= g
        }
        return RenderedStrum(left: left, right: right, sampleRate: rate, events: events)
    }

    /// Cubic (Hermite) interpolation. `ratio` > 1 raises the pitch.
    static func resample(_ s: StereoSample, ratio: Double) -> ([Float], [Float]) {
        if abs(ratio - 1) < 1e-6 { return (s.left, s.right) }
        let outCount = Int(Double(s.count - 3) / ratio)
        var l = [Float](repeating: 0, count: max(outCount, 0))
        var r = l
        func hermite(_ x: [Float], _ i: Int, _ t: Float) -> Float {
            let xm1 = x[max(i - 1, 0)], x0 = x[i], x1 = x[i + 1], x2 = x[i + 2]
            let c1 = 0.5 * (x1 - xm1)
            let c2 = xm1 - 2.5 * x0 + 2 * x1 - 0.5 * x2
            let c3 = 0.5 * (x2 - xm1) + 1.5 * (x0 - x1)
            return ((c3 * t + c2) * t + c1) * t + x0
        }
        for j in 0..<l.count {
            let pos = Double(j) * ratio
            let i = Int(pos)
            let t = Float(pos - Double(i))
            l[j] = hermite(s.left, i, t)
            r[j] = hermite(s.right, i, t)
        }
        return (l, r)
    }

    private static func lowPass(coefficient cutoff: Double, rate: Double) -> Float {
        Float(1 - exp(-2 * Double.pi * cutoff / rate))
    }
}

/// A small, soft room (Freeverb-style). The recordings were made in an
/// anechoic chamber and sound unnaturally dry without a little space.
nonisolated struct Reverb {
    private var combsL: [Comb], combsR: [Comb]
    private var allpassL: [Allpass], allpassR: [Allpass]

    init(sampleRate: Double, roomSize: Float = 0.62, damping: Float = 0.45) {
        let scale = sampleRate / 44_100
        let combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        let allpassTunings = [556, 441, 341, 225]
        let spread = 23
        let feedback = roomSize * 0.28 + 0.7
        combsL = combTunings.map { Comb(size: Int(Double($0) * scale), feedback: feedback, damp: damping) }
        combsR = combTunings.map { Comb(size: Int(Double($0 + spread) * scale), feedback: feedback, damp: damping) }
        allpassL = allpassTunings.map { Allpass(size: Int(Double($0) * scale)) }
        allpassR = allpassTunings.map { Allpass(size: Int(Double($0 + spread) * scale)) }
    }

    mutating func process(left: inout [Float], right: inout [Float], mix: Float) {
        let inputGain: Float = 0.015
        for i in left.indices {
            let input = (left[i] + right[i]) * inputGain
            var outL: Float = 0, outR: Float = 0
            for c in combsL.indices {
                outL += combsL[c].process(input)
                outR += combsR[c].process(input)
            }
            for a in allpassL.indices {
                outL = allpassL[a].process(outL)
                outR = allpassR[a].process(outR)
            }
            left[i] = left[i] * (1 - mix * 0.5) + outL * mix
            right[i] = right[i] * (1 - mix * 0.5) + outR * mix
        }
    }

    private struct Comb {
        var buffer: [Float]
        var index = 0
        var store: Float = 0
        let feedback: Float
        let damp: Float

        init(size: Int, feedback: Float, damp: Float) {
            buffer = [Float](repeating: 0, count: max(size, 1))
            self.feedback = feedback
            self.damp = damp
        }

        mutating func process(_ input: Float) -> Float {
            let output = buffer[index]
            store = output * (1 - damp) + store * damp
            buffer[index] = input + store * feedback
            index = (index + 1) % buffer.count
            return output
        }
    }

    private struct Allpass {
        var buffer: [Float]
        var index = 0

        init(size: Int) { buffer = [Float](repeating: 0, count: max(size, 1)) }

        mutating func process(_ input: Float) -> Float {
            let buffered = buffer[index]
            buffer[index] = input + buffered * 0.5
            index = (index + 1) % buffer.count
            return buffered - input
        }
    }
}

/// Seedable random numbers, so previews and tests are repeatable.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
