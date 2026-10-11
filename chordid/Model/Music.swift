import Foundation

/// One of the 12 pitch classes, C = 0 … B = 11. Octave-independent.
nonisolated struct PitchClass: Hashable, Comparable, Codable, Sendable {
    let value: Int

    init(_ value: Int) {
        self.value = ((value % 12) + 12) % 12
    }

    static func < (lhs: PitchClass, rhs: PitchClass) -> Bool { lhs.value < rhs.value }

    /// Semitones from `root` up to this pitch class (0…11).
    func interval(from root: PitchClass) -> Int {
        PitchClass(value - root.value).value
    }

    /// Neutral spelling used when there is no chord or key context.
    var defaultName: String { Spelling.defaultNames[value] }

    var isNatural: Bool { Spelling.naturalPCs.contains(value) }
}

/// A concrete pitch, stored as a MIDI note number (middle C = C4 = 60).
nonisolated struct Note: Hashable, Comparable, Codable, Sendable {
    let midi: Int

    init(midi: Int) { self.midi = midi }

    static func < (lhs: Note, rhs: Note) -> Bool { lhs.midi < rhs.midi }

    var pitchClass: PitchClass { PitchClass(midi) }
    var octave: Int { Int((Double(midi) / 12).rounded(.down)) - 1 }

    /// Name with octave, e.g. "E2", "F♯3".
    var nameWithOctave: String { pitchClass.defaultName + String(octave) }

    func frequency(a4: Double = 440) -> Double {
        a4 * pow(2, Double(midi - 69) / 12)
    }

    /// The nearest equal-tempered note to `frequency`, and how many cents
    /// the frequency is above (+) or below (−) it.
    static func nearest(to frequency: Double, a4: Double = 440) -> (note: Note, cents: Double) {
        let exact = 69 + 12 * log2(frequency / a4)
        let midi = Int(exact.rounded())
        return (Note(midi: midi), (exact - Double(midi)) * 100)
    }
}

extension Note {
    /// Parses names like "E2", "F#3", "Bb4", "E♭2".
    init?(_ name: String) {
        let s = name.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        guard let first = s.first, let letterIndex = Spelling.letters.firstIndex(of: String(first).uppercased()) else { return nil }
        var rest = s.dropFirst()
        var accidental = 0
        while let c = rest.first, c == "#" || c == "b" {
            accidental += c == "#" ? 1 : -1
            rest = rest.dropFirst()
        }
        guard let octave = Int(rest) else { return nil }
        self.init(midi: (octave + 1) * 12 + Spelling.naturalPCs[letterIndex] + accidental)
    }
}

/// Note-name spelling helpers. Uses ♯ and ♭ glyphs for display.
nonisolated enum Spelling {
    static let letters = ["C", "D", "E", "F", "G", "A", "B"]
    static let naturalPCs = [0, 2, 4, 5, 7, 9, 11]

    static let defaultNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "G♯", "A", "B♭", "B"]
    static let sharpNames   = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static let flatNames    = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    /// Spell `pc` using the given letter (0 = C … 6 = B). Returns nil if that
    /// would need a double sharp or double flat.
    static func spell(_ pc: PitchClass, letter: Int) -> String? {
        let letter = ((letter % 7) + 7) % 7
        var diff = PitchClass(pc.value - naturalPCs[letter]).value
        if diff > 6 { diff -= 12 }
        switch diff {
        case 0: return letters[letter]
        case 1: return letters[letter] + "♯"
        case -1: return letters[letter] + "♭"
        default: return nil
        }
    }

    /// Letter index (0…6) of a spelled name such as "B♭".
    static func letterIndex(of name: String) -> Int {
        letters.firstIndex(of: String(name.prefix(1))) ?? 0
    }
}

/// A six-string tuning, lowest string first.
nonisolated struct Tuning: Hashable, Codable, Identifiable, Sendable {
    var id: String
    var name: String
    /// Open-string notes from the 6th (lowest) string to the 1st.
    var openNotes: [Note]
    /// Show open-string names with flats (e.g. half step down).
    var usesFlats: Bool = false

    var stringCount: Int { openNotes.count }

    /// Open-string names for display, e.g. ["E", "A", "D", "G", "B", "E"].
    var stringNames: [String] {
        openNotes.map { usesFlats ? Spelling.flatNames[$0.pitchClass.value] : $0.pitchClass.defaultName }
    }

    var isCustom: Bool { id.hasPrefix("custom") }

    static func make(_ id: String, _ name: String, _ notes: String, flats: Bool = false) -> Tuning {
        Tuning(id: id, name: name, openNotes: notes.split(separator: " ").map { Note(String($0))! }, usesFlats: flats)
    }

    static let standard     = make("standard", "Standard", "E2 A2 D3 G3 B3 E4")
    static let dropD        = make("dropD", "Drop D", "D2 A2 D3 G3 B3 E4")
    static let halfStepDown = make("halfStepDown", "Half step down", "Eb2 Ab2 Db3 Gb3 Bb3 Eb4", flats: true)
    static let dadgad       = make("dadgad", "DADGAD", "D2 A2 D3 G3 A3 D4")
    static let openG        = make("openG", "Open G", "D2 G2 D3 G3 B3 D4")
    static let openD        = make("openD", "Open D", "D2 A2 D3 F#3 A3 D4")
    static let openE        = make("openE", "Open E", "E2 B2 E3 G#3 B3 E4")

    static let presets: [Tuning] = [.standard, .dropD, .halfStepDown, .dadgad, .openG, .openD, .openE]

    static func custom(_ notes: [Note], name: String = "Custom") -> Tuning {
        Tuning(id: "custom", name: name, openNotes: notes, usesFlats: false)
    }
}

/// The highest fret the app supports.
nonisolated let maxFret = 24

/// What each string is doing: `nil` = muted, 0 = open, n = fretted at n.
/// Index 0 is the lowest (6th) string.
nonisolated struct ChordShape: Hashable, Codable, Sendable {
    var frets: [Int?]

    init(frets: [Int?]) { self.frets = frets }

    static func empty(strings: Int = 6) -> ChordShape {
        ChordShape(frets: Array(repeating: nil, count: strings))
    }

    /// Parses "x32010" (one character per string) or "x 10 12 11 x x" (space-separated).
    init?(_ text: String) {
        let tokens: [Substring] = text.contains(" ") || text.contains(",")
            ? text.split(whereSeparator: { $0 == " " || $0 == "," })
            : text.map { Substring(String($0)) }
        var frets: [Int?] = []
        for t in tokens {
            if t.lowercased() == "x" { frets.append(nil) }
            else if let n = Int(t), (0...maxFret).contains(n) { frets.append(n) }
            else { return nil }
        }
        self.frets = frets
    }

    /// "x 3 2 0 1 0" — matches the library list style.
    var displayString: String {
        frets.map { $0.map(String.init) ?? "x" }.joined(separator: " ")
    }

    /// The note each string produces, or nil if muted.
    func notesByString(in tuning: Tuning) -> [Note?] {
        zip(frets, tuning.openNotes).map { fret, open in fret.map { Note(midi: open.midi + $0) } }
    }

    /// Sounding notes, lowest pitch first.
    func soundingNotes(in tuning: Tuning) -> [Note] {
        notesByString(in: tuning).compactMap { $0 }.sorted()
    }

    var isEmpty: Bool { frets.allSatisfy { $0 == nil } }
}

nonisolated enum Fretboard {
    /// The note at `fret` on `string` (0 = lowest string).
    static func note(string: Int, fret: Int, tuning: Tuning) -> Note {
        Note(midi: tuning.openNotes[string].midi + fret)
    }

    /// The fret that produces `note` on `string`, or nil if the note is below
    /// the open string or above `maxFret`.
    static func fret(for note: Note, string: Int, tuning: Tuning) -> Int? {
        let fret = note.midi - tuning.openNotes[string].midi
        return (0...maxFret).contains(fret) ? fret : nil
    }
}
