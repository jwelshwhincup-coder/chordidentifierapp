import Foundation

/// A chord quality, e.g. minor seventh, defined by its tones above the root.
nonisolated struct ChordType: Hashable, Sendable {
    /// How the root is spelled for this kind of chord.
    enum Family: Sendable { case major, minor, diminished, augmented, suspended }

    /// One chord tone: semitones above the root, which scale degree it is
    /// (1–7, so a 9th is degree 2), and whether it may be left out.
    struct Tone: Hashable, Sendable {
        let semitones: Int
        let degree: Int
        let optional: Bool
    }

    let id: String
    /// Text after the root in the chord symbol, e.g. "m7♭5".
    let suffix: String
    let family: Family
    /// Lower is simpler. Used to prefer the plainest name that fits.
    let complexity: Double
    let tones: [Tone]

    var requiredIntervals: Set<Int> { Set(tones.filter { !$0.optional }.map(\.semitones)) }
    var allIntervals: Set<Int> { Set(tones.map(\.semitones)) }

    /// Builds a type from a degree list such as "1 3 5? b7" (? = may be omitted).
    init(_ id: String, _ suffix: String, _ family: Family, _ complexity: Double, _ formula: String) {
        self.id = id
        self.suffix = suffix
        self.family = family
        self.complexity = complexity
        self.tones = formula.split(separator: " ").map { token in
            let optional = token.hasSuffix("?")
            let name = optional ? String(token.dropLast()) : String(token)
            guard let (semitones, degree) = ChordType.degrees[name] else {
                preconditionFailure("Unknown degree \(name) in \(id)")
            }
            return Tone(semitones: semitones, degree: degree, optional: optional)
        }
    }

    private static let degrees: [String: (Int, Int)] = [
        "1": (0, 1),
        "b9": (1, 2), "9": (2, 2), "#9": (3, 2),
        "b3": (3, 3), "3": (4, 3),
        "11": (5, 4), "#11": (6, 4),
        "b5": (6, 5), "5": (7, 5), "#5": (8, 5),
        "13": (9, 6),
        "bb7": (9, 7), "b7": (10, 7), "7": (11, 7),
    ]

    static let major = ChordType("maj", "", .major, 0, "1 3 5")
    static let minor = ChordType("min", "m", .minor, 0, "1 b3 5")

    /// Every chord quality the engine recognises.
    ///
    /// Rules of thumb behind the table:
    /// - The 5th may be dropped from 7th and extended chords, never from
    ///   triads, sixths or sus chords (C–E–A should read as Am/C, not C6).
    /// - The 3rd is never optional except in 11th chords, where it's usually left out.
    static let all: [ChordType] = [
        .major,
        .minor,
        ChordType("sus4", "sus4", .suspended, 1.5, "1 11 5"),
        ChordType("sus2", "sus2", .suspended, 1.6, "1 9 5"),
        ChordType("dim", "dim", .diminished, 2, "1 b3 b5"),
        ChordType("aug", "aug", .augmented, 2.5, "1 3 #5"),
        ChordType("7", "7", .major, 2, "1 3 5? b7"),
        ChordType("m7", "m7", .minor, 2, "1 b3 5? b7"),
        ChordType("maj7", "maj7", .major, 2.2, "1 3 5? 7"),
        ChordType("6", "6", .major, 2.4, "1 3 5 13"),
        ChordType("m6", "m6", .minor, 2.6, "1 b3 5 13"),
        ChordType("add9", "add9", .major, 2.8, "1 3 5? 9"),
        ChordType("madd9", "madd9", .minor, 3, "1 b3 5? 9"),
        ChordType("7sus4", "7sus4", .suspended, 3, "1 11 5 b7"),
        ChordType("m7b5", "m7♭5", .diminished, 3, "1 b3 b5 b7"),
        ChordType("dim7", "dim7", .diminished, 3, "1 b3 b5 bb7"),
        ChordType("mMaj7", "mMaj7", .minor, 3.5, "1 b3 5? 7"),
        ChordType("7sus2", "7sus2", .suspended, 3.6, "1 9 5 b7"),
        ChordType("9", "9", .major, 4, "1 3 5? b7 9"),
        ChordType("m9", "m9", .minor, 4, "1 b3 5? b7 9"),
        ChordType("maj9", "maj9", .major, 4.2, "1 3 5? 7 9"),
        ChordType("6/9", "6/9", .major, 4, "1 3 5? 13 9"),
        ChordType("m6/9", "m6/9", .minor, 4.4, "1 b3 5? 13 9"),
        ChordType("add11", "add11", .major, 4, "1 3 5? 11"),
        ChordType("7b5", "7♭5", .major, 4.5, "1 3 b5 b7"),
        ChordType("7#5", "7♯5", .augmented, 4.5, "1 3 #5 b7"),
        ChordType("maj7#5", "maj7♯5", .augmented, 5, "1 3 #5 7"),
        ChordType("7b9", "7♭9", .major, 5, "1 3 5? b7 b9"),
        ChordType("7#9", "7♯9", .major, 5, "1 3 5? b7 #9"),
        ChordType("7#11", "7♯11", .major, 5.5, "1 3 5? b7 #11"),
        ChordType("maj7#11", "maj7♯11", .major, 5.5, "1 3 5? 7 #11"),
        ChordType("11", "11", .major, 5.5, "1 3? 5? b7 9? 11"),
        ChordType("m11", "m11", .minor, 5.5, "1 b3 5? b7 9? 11"),
        ChordType("13", "13", .major, 6, "1 3 5? b7 9? 11? 13"),
        ChordType("maj13", "maj13", .major, 6.5, "1 3 5? 7 9? 13"),
        ChordType("m13", "m13", .minor, 6.5, "1 b3 5? b7 9? 11? 13"),
    ]
}
