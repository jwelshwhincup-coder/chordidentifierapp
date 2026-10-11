import Accelerate
import Foundation

/// One analysis frame from the microphone.
nonisolated struct PitchReading: Sendable, Equatable {
    /// Detected fundamental in Hz, or nil when there's no clear pitch.
    let frequency: Double?
    /// How periodic the signal is, 0…1. Clean plucked notes are above 0.9.
    let clarity: Double
    /// Root-mean-square level of the frame, 0…1.
    let rms: Double

    var decibels: Double { 20 * log10(max(rms, 1e-9)) }
}

/// Monophonic pitch detection using the McLeod Pitch Method (MPM).
///
/// MPM computes a normalised square difference function (NSDF) and takes
/// the first peak that comes close to the highest one. Choosing the *first*
/// strong peak, rather than the tallest, is what keeps it from locking onto
/// a harmonic an octave or a fifth away — the classic failure of picking
/// the biggest FFT bin on a guitar.
nonisolated struct PitchDetector: Sendable {
    let sampleRate: Double
    var minFrequency: Double = 60
    var maxFrequency: Double = 1400
    /// A peak must reach this fraction of the highest NSDF peak to be chosen.
    var peakThreshold: Double = 0.93

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// Samples needed per frame: enough to hold several periods of the lowest note.
    static func windowSize(for sampleRate: Double) -> Int {
        sampleRate > 30_000 ? 4096 : 2048
    }

    func analyze(_ input: [Float]) -> PitchReading {
        let n = input.count
        guard n > 64 else { return PitchReading(frequency: nil, clarity: 0, rms: 0) }

        // Remove any DC offset.
        let mean = vDSP.mean(input)
        let x = vDSP.add(-mean, input)
        let rms = Double(vDSP.rootMeanSquare(x))
        guard rms > 1e-5 else { return PitchReading(frequency: nil, clarity: 0, rms: rms) }

        let minLag = max(2, Int(sampleRate / maxFrequency))
        let maxLag = min(Int((sampleRate / minFrequency).rounded(.up)) + 2, n / 2)
        guard maxLag > minLag + 2 else { return PitchReading(frequency: nil, clarity: 0, rms: rms) }

        let nsdf = Self.nsdf(x, maxLag: maxLag)

        // Key maxima: the highest point between each upward and downward zero crossing,
        // skipping the lobe around lag 0.
        var keyMaxima: [Int] = []
        var lag = 1
        while lag < maxLag, nsdf[lag] > 0 { lag += 1 }
        var bestInLobe: Int?
        while lag < maxLag {
            if nsdf[lag] > 0 {
                if bestInLobe == nil || nsdf[lag] > nsdf[bestInLobe!] { bestInLobe = lag }
            } else if let b = bestInLobe {
                keyMaxima.append(b)
                bestInLobe = nil
            }
            lag += 1
        }
        if let b = bestInLobe { keyMaxima.append(b) }
        keyMaxima.removeAll { $0 < minLag || $0 >= maxLag - 1 }

        guard let highest = keyMaxima.map({ nsdf[$0] }).max(), highest > 0 else {
            return PitchReading(frequency: nil, clarity: 0, rms: rms)
        }
        let threshold = Float(peakThreshold) * highest
        guard let chosen = keyMaxima.first(where: { nsdf[$0] >= threshold }) else {
            return PitchReading(frequency: nil, clarity: 0, rms: rms)
        }

        // Parabolic interpolation for sub-sample accuracy.
        let a = Double(nsdf[chosen - 1]), b = Double(nsdf[chosen]), c = Double(nsdf[chosen + 1])
        let denominator = a - 2 * b + c
        let shift = denominator == 0 ? 0 : 0.5 * (a - c) / denominator
        let period = Double(chosen) + shift
        let peak = b - 0.25 * (a - c) * shift

        let frequency = sampleRate / period
        guard (minFrequency * 0.97...maxFrequency * 1.03).contains(frequency) else {
            return PitchReading(frequency: nil, clarity: min(peak, 1), rms: rms)
        }
        return PitchReading(frequency: frequency, clarity: min(peak, 1), rms: rms)
    }

    /// n'(τ) = 2·r(τ) / m(τ), where r is the autocorrelation over the overlapping part
    /// and m the sum of squares of both overlapping parts. Values lie in −1…1.
    private static func nsdf(_ x: [Float], maxLag: Int) -> [Float] {
        let n = x.count
        var result = [Float](repeating: 0, count: maxLag + 1)
        let squares = vDSP.multiply(x, x)
        var m = 2 * vDSP.sum(squares)
        x.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            for tau in 0...maxLag {
                if tau > 0 { m -= squares[tau - 1] + squares[n - tau] }
                var r: Float = 0
                vDSP_dotpr(base, 1, base + tau, 1, &r, vDSP_Length(n - tau))
                result[tau] = m > 0 ? 2 * r / m : 0
            }
        }
        return result
    }
}

/// Turns a stream of frames into confident note events.
///
/// A note is accepted only when it is loud enough, clearly pitched, and has
/// held the same pitch (within a few cents) for several frames in a row.
/// The first frames after a pluck are skipped because the attack is noisy.
///
/// Once a note is accepted, the same note isn't accepted again until a new
/// pluck is heard, so a string that's still ringing can't be counted twice.
/// A *different* note that holds steady is accepted straight away, so a soft
/// pluck of the next string still registers while the last one rings.
nonisolated struct NoteStabilizer: Sendable {
    struct Config: Sendable {
        /// About −48 dBFS.
        var gateRMS: Double = 0.004
        var minClarity: Double = 0.88
        /// Frames ignored after a pluck (~65 ms at 48 kHz with 1024-sample hops).
        var attackFrames = 3
        /// Consecutive steady frames needed (~105 ms).
        var stableFrames = 5
        var centsTolerance: Double = 35
        /// Level rise over the recent quietest frame that counts as a new pluck.
        var onsetRatio: Double = 1.8
        /// Frames of history for onset detection. Analysis windows overlap
        /// (4096 window, 1024 hop), so a pluck takes about 4 frames to fully arrive.
        var onsetLookback = 4
    }

    var config = Config()
    private var candidates: [Double] = []
    private var attackRemaining = 0
    private var recentRMS: [Double] = []
    private var framesSinceOnset = Int.max
    /// The last accepted note, until a new pluck is heard.
    private var lastAccepted: Note?

    init(config: Config = Config()) {
        self.config = config
    }

    /// Forget everything; the next steady note will be accepted.
    mutating func reset() {
        candidates.removeAll()
        attackRemaining = 0
        recentRMS.removeAll()
        framesSinceOnset = .max
        lastAccepted = nil
    }

    /// Feed one frame. Returns a note when one has just been confirmed.
    mutating func process(_ reading: PitchReading) -> Note? {
        defer {
            recentRMS.append(reading.rms)
            if recentRMS.count > config.onsetLookback { recentRMS.removeFirst() }
            if framesSinceOnset < .max { framesSinceOnset += 1 }
        }

        let loud = reading.rms >= config.gateRMS
        let floor = recentRMS.min() ?? 0
        let onset = loud && framesSinceOnset >= config.onsetLookback
            && (floor < config.gateRMS || reading.rms > floor * config.onsetRatio)
        if onset {
            framesSinceOnset = 0
            attackRemaining = config.attackFrames
            candidates.removeAll()
            lastAccepted = nil
        }
        if attackRemaining > 0 {
            attackRemaining -= 1
            return nil
        }
        guard loud, reading.clarity >= config.minClarity, let frequency = reading.frequency else {
            candidates.removeAll()
            return nil
        }

        let exact = 69 + 12 * log2(frequency / 440)
        if let centre = Self.median(candidates), abs(exact - centre) * 100 > config.centsTolerance {
            // Pitch moved (including an octave jump): start counting again.
            candidates = [exact]
        } else {
            candidates.append(exact)
        }

        guard candidates.count >= config.stableFrames, let centre = Self.median(candidates) else { return nil }
        candidates.removeAll()
        let note = Note(midi: Int(centre.rounded()))
        if note == lastAccepted { return nil } // same string still ringing
        lastAccepted = note
        return note
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
