import Foundation
import Testing
@testable import chordid

// MARK: - Synthetic signals

private let sampleRate = 48_000.0

private func sine(_ frequency: Double, count: Int = 4096, amplitude: Float = 0.3) -> [Float] {
    (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
}

/// A tone built from harmonics with the given relative amplitudes (index 0 = fundamental).
private func harmonics(_ frequency: Double, _ amplitudes: [Double], count: Int = 4096) -> [Float] {
    (0..<count).map { i in
        let t = Double(i) / sampleRate
        let value = amplitudes.enumerated().reduce(0.0) { sum, h in
            sum + h.element * sin(2 * .pi * frequency * Double(h.offset + 1) * t + Double(h.offset))
        }
        return Float(0.2 * value)
    }
}

/// Small deterministic random generator so tests are repeatable.
private struct LCG {
    var state: UInt64
    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(Double(state >> 11) / Double(1 << 53)) * 2 - 1
    }
}

/// Karplus–Strong plucked string: a burst of noise through a tuned, damped delay line.
/// Sounds (and analyses) much like a real plucked string: noisy attack, rich overtones, decay.
/// Returns the samples and the frequency the model actually produces.
private func pluck(_ frequency: Double, seconds: Double = 1.2, leadingSilence: Double = 0.2,
                   amplitude: Float = 0.3, seed: UInt64 = 1) -> (samples: [Float], frequency: Double) {
    // Averaging neighbouring samples shortens the loop by half a sample.
    let delay = max(2, Int((sampleRate / frequency + 0.5).rounded()))
    let actual = sampleRate / (Double(delay) - 0.5)
    var rng = LCG(state: seed)
    var line = (0..<delay).map { _ in rng.next() }
    var out = [Float](repeating: 0, count: Int(leadingSilence * sampleRate))
    var index = 0
    for _ in 0..<Int(seconds * sampleRate) {
        let current = line[index]
        let next = line[(index + 1) % delay]
        out.append(amplitude * current)
        line[index] = 0.998 * 0.5 * (current + next)
        index = (index + 1) % delay
    }
    return (out, actual)
}

private func cents(_ measured: Double, _ expected: Double) -> Double {
    1200 * log2(measured / expected)
}

/// Run a whole signal through detector + stabilizer the way the app does (4096 window, 1024 hop).
private func acceptedNotes(_ signal: [Float], stabilizer: inout NoteStabilizer) -> [Note] {
    let detector = PitchDetector(sampleRate: sampleRate)
    let window = 4096, hop = 1024
    var notes: [Note] = []
    var start = 0
    while start + window <= signal.count {
        let reading = detector.analyze(Array(signal[start..<start + window]))
        if let note = stabilizer.process(reading) { notes.append(note) }
        start += hop
    }
    return notes
}

// MARK: - Detector

struct PitchDetectorTests {
    /// Guitar range from drop-B low B1 up to fret 24 on the high E (E6).
    nonisolated static let frequencies: [Double] = [61.74, 73.42, 77.78, 82.41, 110, 146.83, 196, 246.94, 329.63, 659.26, 987.77, 1318.51]

    @Test(arguments: frequencies)
    func pureTone(_ f: Double) throws {
        let r = PitchDetector(sampleRate: sampleRate).analyze(sine(f))
        let measured = try #require(r.frequency)
        #expect(abs(cents(measured, f)) < 3)
        #expect(r.clarity > 0.95)
    }

    /// Second harmonic louder than the fundamental — typical of a guitar and the case
    /// where FFT peak-picking reports the wrong octave.
    @Test(arguments: frequencies)
    func strongSecondHarmonicDoesNotFoolIt(_ f: Double) throws {
        let r = PitchDetector(sampleRate: sampleRate).analyze(harmonics(f, [0.5, 1.0, 0.7, 0.4, 0.25]))
        let measured = try #require(r.frequency)
        #expect(abs(cents(measured, f)) < 5, "measured \(measured)")
    }

    @Test(arguments: [82.41, 110, 196])
    func weakFundamental(_ f: Double) throws {
        let r = PitchDetector(sampleRate: sampleRate).analyze(harmonics(f, [0.2, 1.0, 0.8, 0.5, 0.3]))
        let measured = try #require(r.frequency)
        #expect(abs(cents(measured, f)) < 5, "measured \(measured)")
    }

    @Test(arguments: [73.42, 82.41, 110, 146.83, 196, 246.94, 329.63, 659.26, 1318.51])
    func pluckedString(_ f: Double) throws {
        let (signal, actual) = pluck(f, leadingSilence: 0)
        // Skip the first 100 ms of attack, analyse the ringing part.
        let frame = Array(signal[4800..<4800 + 4096])
        let r = PitchDetector(sampleRate: sampleRate).analyze(frame)
        let measured = try #require(r.frequency)
        #expect(abs(cents(measured, actual)) < 8, "measured \(measured), expected \(actual)")
        #expect(r.clarity > 0.9)
    }

    @Test func noiseHasNoConfidentPitch() {
        var rng = LCG(state: 42)
        let noise = (0..<4096).map { _ in 0.3 * rng.next() }
        let r = PitchDetector(sampleRate: sampleRate).analyze(noise)
        #expect(r.frequency == nil || r.clarity < 0.88)
    }

    @Test func silenceIsRejected() {
        let r = PitchDetector(sampleRate: sampleRate).analyze([Float](repeating: 0, count: 4096))
        #expect(r.frequency == nil)
        #expect(r.rms == 0)
    }

    @Test func noisyPluckStillDetected() throws {
        let (clean, actual) = pluck(110, leadingSilence: 0)
        var rng = LCG(state: 7)
        let noisy = clean.map { $0 + 0.02 * rng.next() } // roughly 20 dB SNR
        let r = PitchDetector(sampleRate: sampleRate).analyze(Array(noisy[4800..<4800 + 4096]))
        let measured = try #require(r.frequency)
        #expect(abs(cents(measured, actual)) < 10)
    }

    @Test func works44_1kHz() throws {
        let sr = 44_100.0
        let window = PitchDetector.windowSize(for: sr)
        let samples = (0..<window).map { Float(0.3 * sin(2 * .pi * 82.41 * Double($0) / sr)) }
        let measured = try #require(PitchDetector(sampleRate: sr).analyze(samples).frequency)
        #expect(abs(cents(measured, 82.41)) < 3)
    }
}

// MARK: - Stabilizer

struct NoteStabilizerTests {
    private func reading(_ hz: Double?, clarity: Double = 0.97, rms: Double = 0.05) -> PitchReading {
        PitchReading(frequency: hz, clarity: clarity, rms: rms)
    }
    private let silence = PitchReading(frequency: nil, clarity: 0, rms: 0.0001)

    @Test func acceptsAfterAttackAndStableFrames() {
        var s = NoteStabilizer()
        _ = s.process(silence)
        var results: [Note?] = []
        for _ in 0..<10 { results.append(s.process(reading(110))) }
        // 3 attack frames skipped, then 5 steady frames → note on the 8th loud frame.
        #expect(results.prefix(7).allSatisfy { $0 == nil })
        #expect(results[7] == Note("A2"))
        #expect(results.dropFirst(8).allSatisfy { $0 == nil })
    }

    @Test func quietOrUnclearFramesNeverAccepted() {
        var s = NoteStabilizer()
        for _ in 0..<30 { #expect(s.process(reading(110, rms: 0.001)) == nil) }
        var t = NoteStabilizer()
        for _ in 0..<30 { #expect(t.process(reading(110, clarity: 0.6)) == nil) }
    }

    @Test func octaveJumpRestartsTheCount() {
        var s = NoteStabilizer()
        _ = s.process(silence)
        for _ in 0..<3 { _ = s.process(reading(110)) }        // attack
        for _ in 0..<4 { #expect(s.process(reading(110)) == nil) }
        #expect(s.process(reading(220)) == nil)                // octave flip resets: this is frame 1
        for _ in 0..<3 { #expect(s.process(reading(220)) == nil) }
        #expect(s.process(reading(220)) == Note("A3"))
    }

    @Test func ringingNoteIsNotCountedTwiceButANewPluckIs() {
        var s = NoteStabilizer()
        _ = s.process(silence)
        var notes = (0..<40).compactMap { _ in s.process(reading(110)) }
        #expect(notes == [Note("A2")])
        // Still ringing, slowly quieter: nothing new.
        notes = (0..<40).compactMap { i in s.process(reading(110, rms: 0.05 - Double(i) * 0.0005)) }
        #expect(notes.isEmpty)
        // New pluck: level jumps.
        notes = (0..<12).compactMap { _ in s.process(reading(146.83, rms: 0.2)) }
        #expect(notes == [Note("D3")])
    }

    @Test func softPluckOfADifferentNoteIsAccepted() {
        var s = NoteStabilizer()
        _ = s.process(silence)
        #expect((0..<12).compactMap { _ in s.process(reading(82.41)) } == [Note("E2")])
        // Next string plucked softly: no level jump, but a new steady pitch.
        #expect((0..<12).compactMap { _ in s.process(reading(110, rms: 0.045)) } == [Note("A2")])
    }

    @Test func sameNoteNeedsARealNewPluck() {
        var s = NoteStabilizer()
        _ = s.process(silence)
        #expect((0..<12).compactMap { _ in s.process(reading(110)) } == [Note("A2")])
        #expect((0..<20).compactMap { _ in s.process(reading(110, rms: 0.045)) }.isEmpty)
        // Re-plucked: level jumps.
        #expect((0..<12).compactMap { _ in s.process(reading(110, rms: 0.2)) } == [Note("A2")])
    }

    @Test func smallTuningWobbleIsTolerated() {
        var s = NoteStabilizer()
        _ = s.process(silence)
        let wobble = [110.0, 110.6, 109.5, 110.3, 109.8, 110.4, 110.1, 109.9]
        let notes = wobble.compactMap { s.process(reading($0)) }
        #expect(notes == [Note("A2")])
    }

    @Test(arguments: [61.74, 73.42, 82.41, 110, 196, 329.63, 659.26, 1318.51])
    func pluckedStringEndToEnd(_ f: Double) {
        let (signal, actual) = pluck(f)
        var s = NoteStabilizer()
        let notes = acceptedNotes(signal, stabilizer: &s)
        let expected = Note(midi: Int((69 + 12 * log2(actual / 440)).rounded()))
        #expect(notes == [expected], "got \(notes.map(\.nameWithOctave))")
    }

    @Test func twoPlucksInARowGiveTwoNotes() {
        let first = pluck(82.41, seconds: 0.8, seed: 3).samples
        let second = pluck(110, seconds: 0.8, leadingSilence: 0, amplitude: 0.4, seed: 4).samples
        var s = NoteStabilizer()
        let notes = acceptedNotes(first + second, stabilizer: &s)
        #expect(notes.map(\.nameWithOctave) == ["E2", "A2"])
    }
}

// MARK: - Listening flow

struct ListeningSessionTests {
    @Test func placesNotesLowToHigh() {
        var s = ListeningSession(tuning: .standard)
        #expect(s.hear(Note("E2")!) == .placed(string: 0, fret: 0))   // open
        #expect(s.hear(Note("C3")!) == .placed(string: 1, fret: 3))
        #expect(s.currentString == 2)
        #expect(s.shape.frets == [0, 3, nil, nil, nil, nil])
    }

    @Test func impossibleNotesDoNotAdvance() {
        var s = ListeningSession(tuning: .standard)
        #expect(s.hear(Note("D2")!) == .tooLow(string: 0, note: Note("D2")!))
        #expect(s.hear(Note("F4")!) == .tooHigh(string: 0, note: Note("F4")!)) // fret 25
        #expect(s.currentString == 0)
        #expect(s.hear(Note("E4")!) == .placed(string: 0, fret: 24))
    }

    @Test func skipMarksMuted() {
        var s = ListeningSession(tuning: .standard)
        s.skip()
        #expect(s.shape.frets[0] == nil)
        #expect(s.currentString == 1)
    }

    @Test func fullChordFinishesAndNames() {
        var s = ListeningSession(tuning: .standard)
        s.skip()
        for name in ["C3", "E3", "G3", "C4", "E4"] { _ = s.hear(Note(name)!) }
        #expect(s.isFinished)
        #expect(s.shape == ChordShape("x32010"))
        #expect(s.hear(Note("E2")!) == .notListening)
        #expect(ChordEngine.identify(shape: s.shape, tuning: .standard).best?.symbol == "C")
    }

    @Test func respectsTuning() {
        var s = ListeningSession(tuning: .dropD)
        #expect(s.hear(Note("D2")!) == .placed(string: 0, fret: 0))
    }

    @Test func respectsCapo() {
        var s = ListeningSession(tuning: .standard, capo: 2)
        #expect(s.hear(Note("E2")!) == .tooLow(string: 0, note: Note("E2")!))
        #expect(s.hear(Note("F#2")!) == .placed(string: 0, fret: 0))
        #expect(s.maxShapeFret == 22)
    }

    @Test func startOverResets() {
        var s = ListeningSession(tuning: .standard)
        _ = s.hear(Note("G2")!)
        s.startOver()
        #expect(s.currentString == 0)
        #expect(s.shape.isEmpty)
    }
}
