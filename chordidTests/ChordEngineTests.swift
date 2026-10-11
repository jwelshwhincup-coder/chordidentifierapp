import Foundation
import Testing
@testable import chordid

/// A shape, the tuning it's played in, and the chord symbol we expect.
/// Expected symbols are written with ASCII b/# and converted to ♭/♯.
struct ShapeCase: CustomTestStringConvertible, Sendable {
    let shape: String
    let tuning: String
    let expected: String
    let note: String

    init(_ shape: String, _ expected: String, _ tuning: String = "standard", _ note: String = "") {
        self.shape = shape
        self.expected = expected
        self.tuning = tuning
        self.note = note
    }

    var testDescription: String { "\(tuning) \(shape) → \(expected)" }
}

private func display(_ ascii: String) -> String {
    ascii.replacingOccurrences(of: "b", with: "♭").replacingOccurrences(of: "#", with: "♯")
}

private func tuning(_ id: String) -> Tuning {
    Tuning.presets.first { $0.id == id }!
}

private func identify(_ shape: String, _ tuningID: String = "standard") -> ChordAnalysis {
    ChordEngine.identify(shape: ChordShape(shape)!, tuning: tuning(tuningID))
}

struct ChordEngineShapeTests {
    static let openChords: [ShapeCase] = [
        .init("x32010", "C"),
        .init("320003", "G"),
        .init("320033", "G"),
        .init("xx0232", "D"),
        .init("x02220", "A"),
        .init("022100", "E"),
        .init("x02210", "Am"),
        .init("022000", "Em"),
        .init("xx0231", "Dm"),
        .init("022200", "Esus4"),
        .init("xx0233", "Dsus4"),
        .init("xx0230", "Dsus2"),
        .init("x02230", "Asus4"),
        .init("x02200", "Asus2"),
        .init("x32030", "Cadd9"),
        .init("024000", "Emadd9"),
        .init("x3211x", "Caug"),
        .init("x2343x", "Bdim"),
    ]

    static let barreChords: [ShapeCase] = [
        .init("133211", "F"),
        .init("133111", "Fm"),
        .init("x13331", "Bb"),
        .init("x24442", "B"),
        .init("x24432", "Bm"),
        .init("244222", "F#m"),
        .init("x35553", "C"),
        .init("355433", "G"),
        .init("x46654", "C#m"),
        .init("466544", "Ab"),
        .init("x35343", "Cm7"),
        .init("x24232", "Bm7"),
    ]

    static let sevenths: [ShapeCase] = [
        .init("x32310", "C7"),
        .init("320001", "G7"),
        .init("xx0212", "D7"),
        .init("x02020", "A7"),
        .init("020100", "E7"),
        .init("x21202", "B7"),
        .init("x02010", "Am7"),
        .init("022030", "Em7"),
        .init("xx0211", "Dm7"),
        .init("x32000", "Cmaj7"),
        .init("xx3210", "Fmaj7"),
        .init("x02120", "Amaj7"),
        .init("x02030", "A7sus4"),
        .init("x02110", "AmMaj7"),
        .init("xx1212", "D#dim7"),
        .init("x3434x", "Cm7b5"),
    ]

    static let sixths: [ShapeCase] = [
        .init("320000", "G6", "standard", "not Em7/G"),
        .init("x02222", "A6"),
        .init("xx0201", "Dm6", "standard", "not Bm7b5/D"),
        .init("x32210", "Am/C", "standard", "6th chords need their 5th, so C–E–A is Am/C"),
    ]

    static let slashChords: [ShapeCase] = [
        .init("032010", "C/E"),
        .init("2x0232", "D/F#"),
        .init("x20003", "G/B"),
        .init("3x2010", "C/G"),
        .init("x4222x", "A/C#"),
        .init("3x2210", "Am7/G"),
        .init("x3x232", "D7/C"),
    ]

    static let powerChords: [ShapeCase] = [
        .init("355xxx", "G5"),
        .init("x355xx", "C5"),
        .init("133xxx", "F5"),
        .init("x022xx", "A5"),
    ]

    static let jazz: [ShapeCase] = [
        .init("x32333", "C9"),
        .init("020102", "E9"),
        .init("022032", "Em9"),
        .init("x3243x", "Cmaj9", "standard", "no 5th"),
        .init("8x998x", "Cmaj7", "standard", "no 5th, shell voicing"),
        .init("x7678x", "E7#9", "standard", "Hendrix chord"),
        .init("x3232x", "C7b9"),
        .init("3x345x", "G13", "standard", "13 shell: root, 7, 3, 13"),
        .init("x32233", "C6/9"),
    ]

    static let altTunings: [ShapeCase] = [
        .init("000000", "Dsus4", "dadgad"),
        .init("004200", "D", "dadgad"),
        .init("002200", "Dsus2", "dadgad"),
        .init("000200", "D5", "dadgad"),
        .init("x00000", "Dsus4/A", "dadgad"),
        .init("220022", "Em7", "dadgad"),
        .init("0x0020", "G/D", "dadgad"),
        .init("000000", "G/D", "openG", "open strum has D in the bass"),
        .init("x00000", "G", "openG"),
        .init("x55555", "C", "openG"),
        .init("x77777", "D", "openG"),
        .init("x00010", "Gsus4", "openG"),
        .init("x00003", "G7", "openG"),
        .init("x33333", "Bb", "openG"),
        .init("000232", "D", "dropD"),
        .init("022100", "Eb", "halfStepDown"),
        .init("x02210", "G#m", "halfStepDown"),
        .init("000000", "D", "openD"),
        .init("000000", "E", "openE"),
    ]

    @Test(arguments: openChords) func openChord(_ c: ShapeCase) { check(c) }
    @Test(arguments: barreChords) func barreChord(_ c: ShapeCase) { check(c) }
    @Test(arguments: sevenths) func seventhChord(_ c: ShapeCase) { check(c) }
    @Test(arguments: sixths) func sixthChord(_ c: ShapeCase) { check(c) }
    @Test(arguments: slashChords) func slashChord(_ c: ShapeCase) { check(c) }
    @Test(arguments: powerChords) func powerChord(_ c: ShapeCase) { check(c) }
    @Test(arguments: jazz) func jazzVoicing(_ c: ShapeCase) { check(c) }
    @Test(arguments: altTunings) func alternateTuning(_ c: ShapeCase) { check(c) }

    private func check(_ c: ShapeCase) {
        let result = identify(c.shape, c.tuning)
        let alts = result.alternatives.map(\.symbol).joined(separator: ", ")
        #expect(result.best?.symbol == display(c.expected), "alternatives: [\(alts)] \(c.note)")
    }
}

struct ChordEngineBehaviourTests {
    @Test func nothingSounding() {
        #expect(identify("xxxxxx").best == nil)
    }

    @Test func singleNote() {
        let r = identify("x3xxxx")
        #expect(r.best?.kind == .note)
        #expect(r.best?.symbol == "C")
    }

    @Test func octavesAreOneNote() {
        let r = identify("x3x5xx")
        #expect(r.best?.kind == .note)
        #expect(r.best?.symbol == "C")
    }

    @Test func majorThirdInterval() {
        let r = identify("x32xxx")
        #expect(r.best?.kind == .interval)
        #expect(r.best?.symbol == "C + E")
        #expect(r.best?.detail == "Major 3rd")
    }

    @Test func minorSixthIsSpelledFromBass() {
        let r = identify("x3x1xx") // C3 and G♯3, spelled from C as A♭
        #expect(r.best?.kind == .interval)
        #expect(r.best?.detail == "Minor 6th")
        #expect(r.best?.symbol == "C + A♭")
    }

    @Test func powerChordFromFourthIsInverted() {
        // E2 then A2: a 4th, i.e. an A5 with E in the bass.
        let r = ChordEngine.identify([Note("E2")!, Note("A2")!])
        #expect(r.best?.kind == .powerChord)
        #expect(r.best?.symbol == "A5/E")
    }

    @Test func clusterIsListedNotNamed() {
        let r = identify("x 3 11 x 3 x")
        #expect(r.best?.kind == .unrecognized)
        #expect(r.best?.symbol == "C · C♯ · D")
    }

    @Test func voicingAndOrderDoNotMatter() {
        let a = ChordEngine.identify([Note("C3")!, Note("E3")!, Note("G3")!])
        let b = ChordEngine.identify([Note("G5")!, Note("C3")!, Note("E4")!, Note("C5")!, Note("G3")!])
        #expect(a.best?.symbol == "C")
        #expect(b.best?.symbol == "C")
    }

    @Test func doubledNotesDoNotChangeName() {
        #expect(identify("x35553").best?.symbol == identify("x3555x").best?.symbol)
    }

    @Test func alternativesOfferRelativeReading() {
        let r = identify("320000")
        #expect(r.best?.symbol == "G6")
        #expect(r.alternatives.contains { $0.symbol == "Em7/G" })
    }

    @Test func farFetchedAlternativesAreDropped() {
        let r = identify("xx0233")
        #expect(r.best?.symbol == "Dsus4")
        #expect(r.alternatives.map(\.symbol) == ["Gsus2/D"])
    }

    @Test func inversionsAlsoOfferThePlainChord() {
        let openG = identify("000000", "openG")
        #expect(openG.best?.symbol == "G/D")
        #expect(openG.alternatives.first?.symbol == "G")
        #expect(openG.alternatives.first?.displayName == "G major")
        #expect(identify("032010").alternatives.first?.symbol == "C")
        // D under a C triad: D isn't in the chord, so this isn't an inversion and plain "C" isn't offered.
        let cOverD = ChordEngine.identify([Note("D2")!, Note("C3")!, Note("E3")!, Note("G3")!])
        #expect(cOverD.best?.symbol == "C/D")
        #expect(cOverD.best?.rootPosition == nil)
        #expect(cOverD.best?.toneNames == ["D", "C", "E", "G"])
    }

    @Test func slashBassAvoidsAwkwardSpellings() {
        let symbols = identify("x3211x").alternatives.map(\.symbol)
        #expect(!symbols.contains { $0.contains("B♯") })
        #expect(symbols.contains("Eaug/C"))
    }

    @Test func displayNamesSpellOutTriads() {
        #expect(identify("x32010").best?.displayName == "C major")
        #expect(identify("x02210").best?.displayName == "A minor")
        #expect(identify("xx3210").best?.displayName == "Fmaj7")
    }

    @Test func chordTonesAreSpelledInKey() {
        #expect(identify("x32010").best?.toneNames == ["C", "E", "G"])
        #expect(identify("x13331").best?.toneNames == ["B♭", "D", "F"])
        #expect(identify("244222").best?.toneNames == ["F♯", "A", "C♯"])
        #expect(identify("x32310").best?.toneNames == ["C", "E", "B♭"])
        #expect(identify("466544").best?.toneNames == ["A♭", "C", "E♭"])
        #expect(identify("022100", "halfStepDown").best?.toneNames == ["E♭", "G", "B♭"])
        #expect(identify("xx1212").best?.toneNames == ["D♯", "F♯", "A", "C"])
    }

    @Test func spellingLookupForFretboardDots() {
        let best = identify("x13331").best!
        #expect(best.name(for: PitchClass(10)) == "B♭")
        #expect(best.name(for: PitchClass(2)) == "D")
    }
}

struct MusicModelTests {
    @Test func noteParsingAndMIDI() {
        #expect(Note("E2")?.midi == 40)
        #expect(Note("A4")?.midi == 69)
        #expect(Note("C4")?.midi == 60)
        #expect(Note("Eb2")?.midi == 39)
        #expect(Note("F#3")?.midi == 54)
        #expect(Note("E♭2")?.midi == 39)
    }

    @Test func frequencies() {
        #expect(abs(Note("A4")!.frequency() - 440) < 0.001)
        #expect(abs(Note("E2")!.frequency() - 82.4069) < 0.001)
        let (note, cents) = Note.nearest(to: 445)
        #expect(note == Note("A4"))
        #expect(abs(cents - 19.56) < 0.1)
        #expect(Note.nearest(to: 73.42).note == Note("D2"))
    }

    @Test func presetTuningNames() {
        #expect(Tuning.standard.stringNames == ["E", "A", "D", "G", "B", "E"])
        #expect(Tuning.halfStepDown.stringNames == ["E♭", "A♭", "D♭", "G♭", "B♭", "E♭"])
        #expect(Tuning.openD.stringNames == ["D", "A", "D", "F♯", "A", "D"])
        #expect(Tuning.openE.stringNames == ["E", "B", "E", "G♯", "B", "E"])
        #expect(Tuning.presets.count == 7)
        // Custom tunings use the same neutral spelling as the custom tuning editor.
        #expect(Tuning.custom([Note("Eb2")!, Note("A2")!, Note("D3")!, Note("G3")!, Note("B3")!, Note("E4")!]).stringNames.first == "E♭")
    }

    @Test func fretToNoteRespectsTuning() {
        #expect(Fretboard.note(string: 0, fret: 3, tuning: .standard) == Note("G2"))
        #expect(Fretboard.note(string: 0, fret: 3, tuning: .dropD) == Note("F2"))
        #expect(Fretboard.note(string: 4, fret: 1, tuning: .standard) == Note("C4"))
        #expect(Fretboard.note(string: 4, fret: 0, tuning: .dadgad) == Note("A3"))
    }

    @Test func noteToFretAndImpossibleNotes() {
        #expect(Fretboard.fret(for: Note("C3")!, string: 1, tuning: .standard) == 3)
        #expect(Fretboard.fret(for: Note("D2")!, string: 0, tuning: .standard) == nil) // below open E
        #expect(Fretboard.fret(for: Note("D2")!, string: 0, tuning: .dropD) == 0)
        #expect(Fretboard.fret(for: Note("E4")!, string: 0, tuning: .standard) == 24)
        #expect(Fretboard.fret(for: Note("F4")!, string: 0, tuning: .standard) == nil) // above fret 24
    }

    @Test func shapeParsingAndDisplay() {
        #expect(ChordShape("x32010")?.frets == [nil, 3, 2, 0, 1, 0])
        #expect(ChordShape("x 10 12 12 11 x")?.frets == [nil, 10, 12, 12, 11, nil])
        #expect(ChordShape("x32010")?.displayString == "x 3 2 0 1 0")
        #expect(ChordShape("x3201q") == nil)
    }

    @Test func soundingNotesAreLowestFirst() {
        let notes = ChordShape("x32010")!.soundingNotes(in: .standard)
        #expect(notes.map(\.midi) == [48, 52, 55, 60, 64])
    }
}
