import Foundation
import Testing
@testable import chordid

/// A sample source with every note the real library has (frets 0–19 on each
/// string), returning short synthetic tones.
private final class FakeSource: SampleSource {
    let sampleRate = 44_100.0
    var missing: Set<SampleKey> = []
    func has(_ key: SampleKey) -> Bool { key.fret <= 19 && !missing.contains(key) }
    func tuningCents(_ key: SampleKey) -> Double { -20 }
    func sample(_ key: SampleKey) -> StereoSample? {
        let tone = (0..<4410).map { Float(sin(Double($0) * 0.05) * 0.2) }
        return StereoSample(left: tone, right: tone, sampleRate: sampleRate)
    }
}

struct StrumEngineTests {
    private func plan(_ shape: String, _ tuning: Tuning = .standard, style: StrumStyle = .natural, seed: UInt64 = 1,
                      source: FakeSource = FakeSource()) -> [StrumEvent] {
        var rng = SeededRandom(seed: seed)
        return StrumPlanner(source: source).plan(shape: ChordShape(shape)!, tuning: tuning, style: style, rng: &rng)
    }

    @Test func lowToHighAndMutedStringsSkipped() {
        let events = plan("x32010")
        #expect(events.map(\.string) == [1, 2, 3, 4, 5])
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.time < $1.time })
        #expect(events.first?.time == 0)
    }

    @Test(arguments: [StrumStyle.gentle, .natural, .bright])
    func gapsStayHuman(_ style: StrumStyle) {
        for seed in 0..<50 as Range<UInt64> {
            let events = plan("320003", style: style, seed: seed)
            for (a, b) in zip(events, events.dropFirst()) {
                let gap = (b.time - a.time) * 1000
                #expect(gap >= 11 && gap <= 38, "gap \(gap) ms")
            }
        }
    }

    @Test func naturalStrumAveragesTwelveToThirtyFiveMs() {
        var gaps: [Double] = []
        for seed in 0..<100 as Range<UInt64> {
            let e = plan("320003", seed: seed)
            gaps += zip(e, e.dropFirst()).map { ($1.time - $0.time) * 1000 }
        }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        #expect((12...35).contains(mean))
        // And it isn't robotic: the gaps actually vary.
        #expect((gaps.max()! - gaps.min()!) > 5)
    }

    @Test func everyStrumIsSlightlyDifferent() {
        let a = plan("320003", seed: 1), b = plan("320003", seed: 2)
        #expect(a.map(\.time) != b.map(\.time))
        #expect(a.map(\.gain) != b.map(\.gain))
    }

    @Test func strumEasesOff() {
        var first: Float = 0, last: Float = 0
        for seed in 0..<200 as Range<UInt64> {
            let e = plan("022100", seed: seed)
            first += e.first!.gain
            last += e.last!.gain
        }
        #expect(last < first * 0.9)
    }

    @Test func recordingTuningIsCorrected() {
        // The fake recordings are 20 cents flat, so every note is raised ~20 cents (± 3 human).
        for e in plan("x32010") {
            #expect(abs(e.pitchCents - 20) <= 3.01)
        }
    }

    @Test func samePitchOnDifferentStringsUsesDifferentRecordings() {
        // E4: open high E and 5th fret on the B string.
        let events = plan("xxxx50")
        #expect(events.count == 2)
        #expect(events[0].note == events[1].note)
        #expect(events[0].sample.string != events[1].sample.string)
    }

    @Test func shiftsStayWithinThreeSemitones() {
        // Drop D low string (D2) is below anything recorded: shift E2 down 2.
        let c = SampleChooser.choose(note: Note("D2")!, playedString: 0) { _, f in f <= 19 }
        #expect(c == SampleChoice(string: 0, fret: 0, shift: -2))
        // Fret 22 on the low E (D4) isn't recorded there; use the exact pitch on another string.
        let high = SampleChooser.choose(note: Note("D4")!, playedString: 0) { _, f in f <= 19 }
        #expect(high?.shift == 0)
        #expect(high?.string != 0)
        // Every note in every preset tuning up to fret 22 needs at most a 3-semitone shift.
        // Frets 23–24 on the high E sit above the highest recording (B5) and need up to 5.
        for tuning in Tuning.presets {
            for string in 0..<6 {
                for fret in 0...24 {
                    let note = Fretboard.note(string: string, fret: fret, tuning: tuning)
                    let choice = SampleChooser.choose(note: note, playedString: string) { _, f in f <= 19 }
                    let limit = note.midi > Note("B5")!.midi ? 5 : 3
                    #expect(choice != nil && abs(choice!.shift) <= limit, "\(tuning.name) string \(string) fret \(fret)")
                }
            }
        }
    }

    @Test func missingLoudnessFallsBackToAnother() {
        let source = FakeSource()
        for layer in [SampleLayer.pp, .ff] { source.missing.insert(SampleKey(string: 5, fret: 0, layer: layer)) }
        let events = plan("xxxxx0", source: source)
        #expect(events.first?.sample.layer == .mf)
    }

    @Test func renderHasNoClippingAndRingsOut() {
        let source = FakeSource()
        let events = plan("022100", style: .bright, source: source)
        let r = StrumRenderer.render(events, source: source)
        let peak = max(r.left.map(abs).max()!, r.right.map(abs).max()!)
        #expect(peak <= 0.971)
        #expect(r.left.last == 0)
        #expect(Double(r.left.count) / r.sampleRate > events.last!.time)
    }

    @Test func resamplingChangesLengthByTheRatio() {
        let s = StereoSample(left: [Float](repeating: 0.1, count: 10_000), right: [Float](repeating: 0.1, count: 10_000), sampleRate: 44_100)
        let (up, _) = StrumRenderer.resample(s, ratio: pow(2, 2.0 / 12))
        #expect(abs(Double(up.count) - 10_000 / pow(2, 2.0 / 12)) < 3)
    }
}
