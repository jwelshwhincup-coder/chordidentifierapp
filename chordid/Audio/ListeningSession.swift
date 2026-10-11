import Foundation

/// The string-by-string listening flow, without any audio: which string is
/// due, where a heard note lands on it, and whether it's possible at all.
nonisolated struct ListeningSession: Sendable, Equatable {
    enum Outcome: Equatable, Sendable {
        case placed(string: Int, fret: Int)
        /// The note is lower than the string can play (open string, capo included).
        case tooLow(string: Int, note: Note)
        /// The note would need a fret above the highest one.
        case tooHigh(string: Int, note: Note)
        case notListening
    }

    let tuning: Tuning
    let capo: Int
    private(set) var shape: ChordShape
    /// The string being listened for, lowest first; nil when all strings are done.
    private(set) var currentString: Int?

    init(tuning: Tuning, capo: Int = 0) {
        self.tuning = tuning
        self.capo = capo
        self.shape = .empty(strings: tuning.stringCount)
        self.currentString = 0
    }

    var isFinished: Bool { currentString == nil }

    /// Highest fret above the capo.
    var maxShapeFret: Int { maxFret - capo }

    /// The pitch the current string makes when played open (capo included).
    var currentOpenNote: Note? {
        currentString.map { Note(midi: tuning.openNotes[$0].midi + capo) }
    }

    mutating func hear(_ note: Note) -> Outcome {
        guard let string = currentString, let open = currentOpenNote else { return .notListening }
        let fret = note.midi - open.midi
        if fret < 0 { return .tooLow(string: string, note: note) }
        if fret > maxShapeFret { return .tooHigh(string: string, note: note) }
        shape.frets[string] = fret
        advance()
        return .placed(string: string, fret: fret)
    }

    /// Mark the current string muted and move on.
    mutating func skip() {
        guard let string = currentString else { return }
        shape.frets[string] = nil
        advance()
    }

    mutating func startOver() {
        shape = .empty(strings: tuning.stringCount)
        currentString = 0
    }

    private mutating func advance() {
        guard let string = currentString else { return }
        currentString = string + 1 < tuning.stringCount ? string + 1 : nil
    }
}
