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
    /// The unconstrained best guess was an octave or fifth away from anything
    /// the expected string can play, and was moved onto the in-range match.
    var octaveCorrected = false

    var decibels: Double { PitchReading.decibels(rms) }

    static func decibels(_ rms: Double) -> Double { 20 * log10(max(rms, 1e-9)) }
}

/// Monophonic pitch detection using the McLeod Pitch Method (MPM).
///
/// MPM computes a normalised square difference function (NSDF) and takes
/// the *first* peak that comes close to the highest one, rather than the
/// highest itself. That keeps it from locking onto a sub-harmonic.
///
/// When the caller knows which string is being played, it passes the range
/// that string can produce (open note … fret 24). Anything outside that range
/// is impossible, not just unlikely: if the unconstrained pick lands an octave
/// or a fifth away from a candidate that *is* in range, the in-range one wins.
nonisolated struct PitchDetector: Sendable {
    let sampleRate: Double
    var minFrequency: Double = 60
    var maxFrequency: Double = 1400
    /// A peak must reach this fraction of the highest NSDF peak to be chosen.
    var peakThreshold: Double = 0.93
    /// An in-range peak related to the unconstrained pick must reach this fraction of the highest.
    var relatedThreshold: Double = 0.6
    /// An unrelated in-range peak must reach this fraction of the highest.
    var inRangeThreshold: Double = 0.85

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// Samples per frame: about five periods of the lowest note we might hear,
    /// rounded up to a power of two. Long enough for the low E string, short
    /// enough on higher strings that sub-octave periods don't dominate.
    static func windowSize(for sampleRate: Double, lowestFrequency: Double = 60) -> Int {
        let needed = sampleRate / max(lowestFrequency, 20) * 5
        var n = 1024
        while Double(n) < needed && n < 8192 { n *= 2 }
        return n
    }

    /// Frequency ratios that count as "the same note, wrong octave/fifth".
    private static let relatedRatios: [Double] = [2, 3, 4, 1.5, 0.5, 1.0 / 3, 2.0 / 3, 0.25]

    func analyze(_ input: [Float], expected: ClosedRange<Double>? = nil) -> PitchReading {
        let n = input.count
        guard n > 64 else { return PitchReading(frequency: nil, clarity: 0, rms: 0) }

        // Remove any DC offset.
        let mean = vDSP.mean(input)
        let x = vDSP.add(-mean, input)
        let rms = Double(vDSP.rootMeanSquare(x))
        guard rms > 1e-6 else { return PitchReading(frequency: nil, clarity: 0, rms: rms) }

        // Lags (periods in samples) we're allowed to answer with.
        let low = expected?.lowerBound ?? minFrequency
        let high = expected?.upperBound ?? maxFrequency
        let answerLags = (sampleRate / (high * 1.01))...(sampleRate / (low * 0.99))
        // Search a little wider than the answer range so a sub-harmonic is seen for what it is.
        let maxLag = min(n / 2 - 1, Int(sampleRate / low * (expected == nil ? 1.03 : 3.2)) + 2)
        let minLag = max(2, Int(sampleRate / (maxFrequency * 1.03)))
        guard maxLag > minLag + 2 else { return PitchReading(frequency: nil, clarity: 0, rms: rms) }

        let nsdf = Self.nsdf(x, maxLag: maxLag)
        let keyMaxima = Self.keyMaxima(nsdf, maxLag: maxLag).filter { $0 >= minLag && $0 < maxLag - 1 }

        guard let highest = keyMaxima.map({ nsdf[$0] }).max(), highest > 0 else {
            return PitchReading(frequency: nil, clarity: 0, rms: rms)
        }
        // The classic MPM choice: the first peak close to the highest.
        guard let firstStrong = keyMaxima.first(where: { Double(nsdf[$0]) >= peakThreshold * Double(highest) }) else {
            return PitchReading(frequency: nil, clarity: 0, rms: rms)
        }

        var chosen = firstStrong
        var clarity = Double(nsdf[firstStrong])
        var corrected = false

        if !answerLags.contains(Double(firstStrong)) {
            guard expected != nil else { return PitchReading(frequency: nil, clarity: clarity, rms: rms) }
            let inRange = keyMaxima.filter { answerLags.contains(Double($0)) }
            if let related = inRange.first(where: { lag in
                Double(nsdf[lag]) >= relatedThreshold * Double(highest)
                    && Self.relatedRatios.contains { abs(Double(firstStrong) / Double(lag) / $0 - 1) < 0.03 }
            }) {
                // An octave/fifth error: the signal is periodic at this lag too, and it's the only one the string can make.
                chosen = related
                clarity = Double(highest)
                corrected = true
            } else if let plain = inRange.first(where: { Double(nsdf[$0]) >= inRangeThreshold * Double(highest) }) {
                chosen = plain
                clarity = Double(nsdf[plain])
            } else {
                return PitchReading(frequency: nil, clarity: clarity, rms: rms)
            }
        }

        // Parabolic interpolation for sub-sample accuracy.
        let a = Double(nsdf[chosen - 1]), b = Double(nsdf[chosen]), c = Double(nsdf[chosen + 1])
        let denominator = a - 2 * b + c
        let shift = denominator == 0 ? 0 : 0.5 * (a - c) / denominator
        let period = Double(chosen) + shift
        if !corrected { clarity = min(b - 0.25 * (a - c) * shift, 1) }

        let frequency = sampleRate / period
        guard (low * 0.97...high * 1.03).contains(frequency) else {
            return PitchReading(frequency: nil, clarity: min(clarity, 1), rms: rms)
        }
        return PitchReading(frequency: frequency, clarity: min(clarity, 1), rms: rms, octaveCorrected: corrected)
    }

    /// The highest point between each upward and downward zero crossing, skipping the lobe around lag 0.
    private static func keyMaxima(_ nsdf: [Float], maxLag: Int) -> [Int] {
        var result: [Int] = []
        var lag = 1
        while lag < maxLag, nsdf[lag] > 0 { lag += 1 }
        var bestInLobe: Int?
        while lag < maxLag {
            if nsdf[lag] > 0 {
                if bestInLobe == nil || nsdf[lag] > nsdf[bestInLobe!] { bestInLobe = lag }
            } else if let b = bestInLobe {
                result.append(b)
                bestInLobe = nil
            }
            lag += 1
        }
        if let b = bestInLobe { result.append(b) }
        return result
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
/// Loudness is judged against the room, not a fixed number: the first
/// ~0.4 s after listening starts measure the background level, which then
/// keeps adapting slowly while nothing is playing. A pluck is a sudden rise
/// well above that; the first frames after it (the noisy attack) are skipped
/// and the ringing part is analysed for as long as it stays clearly above
/// the room. A note is accepted once its pitch has held steady for a few frames.
///
/// Once a note is accepted, the same note isn't accepted again until a new
/// pluck is heard, so a string that's still ringing can't be counted twice.
/// A *different* note that holds steady is accepted straight away, so a soft
/// pluck of the next string still registers while the last one rings.
nonisolated struct NoteStabilizer: Sendable {
    struct Config: Sendable {
        /// Frames used to measure the room when listening starts (~0.4 s at 1024-sample hops).
        var calibrationFrames = 18
        /// The room is never assumed quieter than this (−74 dBFS).
        var minimumFloorRMS: Double = 0.0002
        /// A pluck must rise this far above the room (×4 = +12 dB)…
        var onsetAboveFloor: Double = 4
        /// …and above the quietest of the last few frames (×1.6 = +4 dB).
        var onsetRise: Double = 1.6
        /// The ringing note is analysed while it stays this far above the room (×2 = +6 dB).
        var sustainAboveFloor: Double = 2
        /// Absolute minimum for a note, whatever the room (−66 dBFS).
        var minimumNoteRMS: Double = 0.0005
        var minClarity: Double = 0.85
        /// Frames ignored after a pluck (~64 ms at 48 kHz with 1024-sample hops).
        var attackFrames = 3
        /// Consecutive steady frames needed (~85 ms).
        var stableFrames = 4
        var centsTolerance: Double = 35
        /// Frames of history for onset detection. Analysis windows overlap, so a
        /// pluck takes a few frames to fully arrive.
        var onsetLookback = 4
    }

    var config = Config()
    /// Current estimate of the room's background level (RMS).
    private(set) var noiseFloor: Double
    private var calibration: [Double] = []
    private var candidates: [Double] = []
    private var attackRemaining = 0
    private var recentRMS: [Double] = []
    private var framesSinceOnset = Int.max
    /// The last accepted note, until a new pluck is heard.
    private var lastAccepted: Note?

    init(config: Config = Config()) {
        self.config = config
        self.noiseFloor = config.minimumFloorRMS
    }

    var isCalibrated: Bool { calibration.count >= config.calibrationFrames }
    /// Level a ringing note must stay above.
    var gateRMS: Double { max(noiseFloor * config.sustainAboveFloor, config.minimumNoteRMS) }
    /// Level a pluck must reach.
    var onsetRMS: Double { max(noiseFloor * config.onsetAboveFloor, config.minimumNoteRMS * 2) }

    /// Forget everything, including the room level; the next frames recalibrate.
    mutating func reset() {
        self = NoteStabilizer(config: config)
    }

    /// Feed one frame. Returns a note when one has just been confirmed.
    mutating func process(_ reading: PitchReading) -> Note? {
        defer {
            recentRMS.append(reading.rms)
            if recentRMS.count > config.onsetLookback { recentRMS.removeFirst() }
            if framesSinceOnset < .max { framesSinceOnset += 1 }
        }
        updateFloor(reading.rms)

        let loud = reading.rms >= gateRMS
        let recentQuietest = recentRMS.min() ?? 0
        let onset = reading.rms >= onsetRMS && framesSinceOnset >= config.onsetLookback
            && (recentQuietest < gateRMS || reading.rms > recentQuietest * config.onsetRise)
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

    private mutating func updateFloor(_ rms: Double) {
        if !isCalibrated {
            calibration.append(rms)
            // A low percentile, so a pluck during calibration doesn't count as "the room".
            let sorted = calibration.sorted()
            noiseFloor = max(sorted[sorted.count / 4], config.minimumFloorRMS)
            return
        }
        // Afterwards, follow the room while nothing is ringing: down quickly, up slowly.
        if rms < noiseFloor {
            noiseFloor = max(0.5 * noiseFloor + 0.5 * rms, config.minimumFloorRMS)
        } else if rms < noiseFloor * 1.5 && framesSinceOnset > 10 {
            noiseFloor = 0.97 * noiseFloor + 0.03 * rms
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
