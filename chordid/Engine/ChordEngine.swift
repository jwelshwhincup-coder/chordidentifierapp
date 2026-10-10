import Foundation

/// One way of naming a set of notes.
nonisolated struct ChordName: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case note, interval, powerChord, chord, unrecognized
    }

    let kind: Kind
    /// Compact symbol, e.g. "C", "Am7", "C/E", "G5".
    let symbol: String
    /// What the result area shows, e.g. "C major", "A minor", "Fmaj7".
    let displayName: String
    /// Optional extra line, e.g. "Single note", "Major 3rd", "Power chord".
    let detail: String?
    let root: PitchClass?
    let bass: PitchClass?
    let type: ChordType?
    /// Spelled chord tones in chord order (root, 3rd, 5th …), e.g. ["C", "E", "G"].
    let toneNames: [String]
    /// Higher is a better fit. Only meaningful relative to other readings of the same notes.
    let score: Double
    /// How each pitch class is spelled in this chord's context.
    let spellings: [Int: String]

    /// Name for `pc` in this chord's spelling, falling back to the neutral name.
    func name(for pc: PitchClass) -> String {
        spellings[pc.value] ?? pc.defaultName
    }
}

nonisolated struct ChordAnalysis: Hashable, Sendable {
    /// Sounding notes, lowest first.
    let notes: [Note]
    /// The best name, or nil when nothing is sounding.
    let best: ChordName?
    /// Other plausible names, best first. Never includes `best`.
    let alternatives: [ChordName]
}

/// Names chords from the notes being played.
///
/// Works on pitch classes, so voicing, inversion, doubling and tuning don't
/// matter. Every sounding pitch class is tried as the root, and the notes are
/// matched against `ChordType.all`. A reading is scored by how simple the
/// chord type is, how many optional tones are missing, and whether the bass
/// note is the root. When the bass isn't a chord tone, the notes above it are
/// also tried as a chord over that bass (e.g. D7/C, C/D).
nonisolated enum ChordEngine {
    private static let rootIsBassBonus = 2.5
    private static let foreignBassPenalty = 2.5
    private static let foreignBassDoubledPenalty = 1.0
    private static let missingFifthPenalty = 0.5
    private static let missingTonePenalty = 1.0
    private static let maxAlternatives = 4
    /// Alternatives scoring further than this below the best are too far-fetched to show.
    private static let alternativeScoreWindow = 6.0

    static func identify(shape: ChordShape, tuning: Tuning) -> ChordAnalysis {
        identify(shape.soundingNotes(in: tuning))
    }

    static func identify(_ notes: [Note]) -> ChordAnalysis {
        let notes = notes.sorted()
        guard let bassNote = notes.first else {
            return ChordAnalysis(notes: [], best: nil, alternatives: [])
        }
        let bass = bassNote.pitchClass
        // Pitch classes in order of first appearance from the bass up.
        var pcs: [PitchClass] = []
        for n in notes where !pcs.contains(n.pitchClass) { pcs.append(n.pitchClass) }

        switch pcs.count {
        case 1:
            return ChordAnalysis(notes: notes, best: singleNote(bass), alternatives: [])
        case 2:
            return ChordAnalysis(notes: notes, best: twoNotes(bass: bass, other: pcs[1]), alternatives: [])
        default:
            break
        }

        let bassCount = notes.filter { $0.pitchClass == bass }.count
        var readings: [ChordName] = []
        let pcSet = Set(pcs)

        for root in pcs {
            for type in ChordType.all {
                if let r = reading(of: pcSet, root: root, type: type, bass: bass, foreignBass: false, bassDoubled: false) {
                    readings.append(r)
                }
            }
        }
        // Chord over a non-chord-tone bass: the notes above the bass must form a chord by themselves.
        let upper = pcSet.subtracting([bass])
        if upper.count >= 3 {
            for root in upper {
                for type in ChordType.all {
                    if let r = reading(of: upper, root: root, type: type, bass: bass, foreignBass: true, bassDoubled: bassCount > 1) {
                        readings.append(r)
                    }
                }
            }
        }

        readings.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let aBass = a.root == bass, bBass = b.root == bass
            if aBass != bBass { return aBass }
            return (a.type?.complexity ?? 0) < (b.type?.complexity ?? 0)
        }

        var seen = Set<String>()
        let unique = readings.filter { seen.insert($0.symbol).inserted }
        guard let best = unique.first else {
            return ChordAnalysis(notes: notes, best: unrecognized(pcs), alternatives: [])
        }
        let alternatives = unique.dropFirst().filter { $0.score >= best.score - alternativeScoreWindow }
        return ChordAnalysis(notes: notes, best: best, alternatives: Array(alternatives.prefix(maxAlternatives)))
    }

    // MARK: - Readings

    private static func reading(of pcs: Set<PitchClass>, root: PitchClass, type: ChordType, bass: PitchClass,
                                foreignBass: Bool, bassDoubled: Bool) -> ChordName? {
        let intervals = Set(pcs.map { $0.interval(from: root) })
        guard intervals.isSubset(of: type.allIntervals), type.requiredIntervals.isSubset(of: intervals) else { return nil }

        let missing = type.allIntervals.subtracting(intervals)
        var score = -type.complexity
        score -= missing.reduce(0) { $0 + ($1 == 7 ? missingFifthPenalty : missingTonePenalty) }
        if root == bass { score += rootIsBassBonus }
        if foreignBass { score -= foreignBassPenalty + (bassDoubled ? foreignBassDoubledPenalty : 0) }

        let rootName = rootSpelling(root, family: type.family)
        let rootLetter = Spelling.letterIndex(of: rootName)
        var spellings: [Int: String] = [:]
        var toneNames: [String] = []
        for tone in type.tones where intervals.contains(tone.semitones) {
            let pc = PitchClass(root.value + tone.semitones)
            let name = tone.semitones == 0 ? rootName : (Spelling.spell(pc, letter: rootLetter + tone.degree - 1) ?? pc.defaultName)
            spellings[pc.value] = name
            toneNames.append(name)
        }

        var symbol = rootName + type.suffix
        var displayName: String
        switch type.id {
        case "maj": displayName = rootName + " major"
        case "min": displayName = rootName + " minor"
        default: displayName = symbol
        }
        if root != bass {
            var bassName = spellings[bass.value] ?? foreignBassSpelling(bass, rootName: rootName)
            // A lone bass note reads better as C than B♯, F than E♯, etc.
            if ["B♯", "E♯", "F♭", "C♭"].contains(bassName) { bassName = bass.defaultName }
            spellings[bass.value] = bassName
            if foreignBass { toneNames.insert(bassName, at: 0) }
            symbol += "/" + bassName
            displayName = symbol
        }

        return ChordName(kind: .chord, symbol: symbol, displayName: displayName, detail: nil,
                         root: root, bass: bass, type: type, toneNames: toneNames, score: score, spellings: spellings)
    }

    private static func singleNote(_ pc: PitchClass) -> ChordName {
        let name = pc.defaultName
        return ChordName(kind: .note, symbol: name, displayName: name, detail: "Single note",
                         root: pc, bass: pc, type: nil, toneNames: [name], score: 0, spellings: [pc.value: name])
    }

    private static let intervalNames = [
        1: "Minor 2nd", 2: "Major 2nd", 3: "Minor 3rd", 4: "Major 3rd", 5: "Perfect 4th", 6: "Tritone",
        7: "Perfect 5th", 8: "Minor 6th", 9: "Major 6th", 10: "Minor 7th", 11: "Major 7th",
    ]
    /// Scale degree (1–7) used to spell the upper note of each interval.
    private static let intervalDegrees = [1: 2, 2: 2, 3: 3, 4: 3, 5: 4, 6: 4, 7: 5, 8: 6, 9: 6, 10: 7, 11: 7]

    private static func twoNotes(bass: PitchClass, other: PitchClass) -> ChordName {
        let up = other.interval(from: bass)
        // A 5th above the bass, or a 4th (an inverted 5th), is a power chord.
        if up == 7 || up == 5 {
            let root = up == 7 ? bass : other
            let fifth = up == 7 ? other : bass
            let rootName = rootSpelling(root, family: .major)
            let fifthName = Spelling.spell(fifth, letter: Spelling.letterIndex(of: rootName) + 4) ?? fifth.defaultName
            let symbol = rootName + "5" + (root == bass ? "" : "/" + fifthName)
            return ChordName(kind: .powerChord, symbol: symbol, displayName: symbol, detail: "Power chord",
                             root: root, bass: bass, type: nil, toneNames: [rootName, fifthName], score: 0,
                             spellings: [root.value: rootName, fifth.value: fifthName])
        }
        let bassName = bass.defaultName
        let upperName = up == 6 ? other.defaultName
            : (Spelling.spell(other, letter: Spelling.letterIndex(of: bassName) + intervalDegrees[up]! - 1) ?? other.defaultName)
        let symbol = "\(bassName) + \(upperName)"
        return ChordName(kind: .interval, symbol: symbol, displayName: symbol, detail: intervalNames[up],
                         root: bass, bass: bass, type: nil, toneNames: [bassName, upperName], score: 0,
                         spellings: [bass.value: bassName, other.value: upperName])
    }

    private static func unrecognized(_ pcs: [PitchClass]) -> ChordName {
        let names = pcs.map(\.defaultName)
        let text = names.joined(separator: " · ")
        var spellings: [Int: String] = [:]
        for pc in pcs { spellings[pc.value] = pc.defaultName }
        return ChordName(kind: .unrecognized, symbol: text, displayName: text, detail: "No standard chord name",
                         root: nil, bass: pcs.first, type: nil, toneNames: names, score: -.infinity, spellings: spellings)
    }

    // MARK: - Spelling

    private static let majorRoots = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    private static let minorRoots = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "G♯", "A", "B♭", "B"]

    /// Root name chosen to suit the key the chord implies:
    /// major chords favour flat keys (D♭, A♭), minor and diminished chords favour sharps (C♯m, G♯dim).
    private static func rootSpelling(_ root: PitchClass, family: ChordType.Family) -> String {
        switch family {
        case .major, .augmented, .suspended: majorRoots[root.value]
        case .minor: minorRoots[root.value]
        case .diminished: Spelling.sharpNames[root.value]
        }
    }

    /// Spelling for a bass note that isn't in the chord, following the root's key.
    private static func foreignBassSpelling(_ pc: PitchClass, rootName: String) -> String {
        if pc.isNatural { return pc.defaultName }
        if rootName.contains("♭") || rootName == "F" { return Spelling.flatNames[pc.value] }
        if rootName.contains("♯") || ["D", "E", "A", "B"].contains(rootName) { return Spelling.sharpNames[pc.value] }
        return pc.defaultName
    }
}
