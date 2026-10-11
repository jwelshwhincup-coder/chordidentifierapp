import Foundation
import SwiftData

/// A chord in the library.
@Model
final class SavedChord {
    /// What the user calls it. Starts as the detected name; can be renamed.
    var name: String
    /// The name the chord engine gave it when saved.
    var detectedName: String
    var tuningID: String
    var tuningName: String
    /// Open-string MIDI notes, lowest string first.
    var tuningMIDI: [Int]
    var tuningUsesFlats: Bool
    /// One per string: −1 = muted, 0 = open, n = fret n (relative to the capo).
    var fretValues: [Int]
    var capo: Int
    var createdAt: Date
    /// Identity for duplicate checks: same frets, same tuning notes, same capo.
    var key: String

    init(name: String, shape: ChordShape, tuning: Tuning, capo: Int, createdAt: Date = .now) {
        self.name = name
        self.detectedName = name
        self.tuningID = tuning.id
        self.tuningName = tuning.name
        self.tuningMIDI = tuning.openNotes.map(\.midi)
        self.tuningUsesFlats = tuning.usesFlats
        self.fretValues = shape.frets.map { $0 ?? -1 }
        self.capo = capo
        self.createdAt = createdAt
        self.key = Self.makeKey(shape: shape, tuning: tuning, capo: capo)
    }

    var shape: ChordShape {
        ChordShape(frets: fretValues.map { $0 < 0 ? nil : $0 })
    }

    var tuning: Tuning {
        Tuning(id: tuningID, name: tuningName, openNotes: tuningMIDI.map { Note(midi: $0) }, usesFlats: tuningUsesFlats)
    }

    /// What the open strings sound like with the capo on.
    var soundingTuning: Tuning {
        var t = tuning
        t.openNotes = tuningMIDI.map { Note(midi: $0 + capo) }
        return t
    }

    var analysis: ChordAnalysis {
        ChordEngine.identify(shape: shape, tuning: soundingTuning)
    }

    /// "Standard · Capo 2 · x 3 2 0 1 0"
    var summary: String {
        ([tuningName] + (capo > 0 ? ["Capo \(capo)"] : []) + [shape.displayString]).joined(separator: " · ")
    }

    func matches(_ search: String) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        // Accept "F#" / "Bb" as well as "F♯" / "B♭".
        let normal = q.replacingOccurrences(of: "#", with: "♯").replacingOccurrences(of: "b", with: "♭")
        return [name, detectedName, tuningName].contains {
            $0.localizedCaseInsensitiveContains(q) || $0.localizedCaseInsensitiveContains(normal)
        }
    }

    static func makeKey(shape: ChordShape, tuning: Tuning, capo: Int) -> String {
        let frets = shape.frets.map { $0.map(String.init) ?? "x" }.joined(separator: ",")
        let notes = tuning.openNotes.map { String($0.midi) }.joined(separator: ",")
        return "t:\(notes)|c:\(capo)|f:\(frets)"
    }

    enum SaveResult: Equatable { case saved, alreadySaved, nothingToSave }

    static func exists(shape: ChordShape, tuning: Tuning, capo: Int, in context: ModelContext) -> Bool {
        let key = makeKey(shape: shape, tuning: tuning, capo: capo)
        let existing = FetchDescriptor<SavedChord>(predicate: #Predicate { $0.key == key })
        return ((try? context.fetchCount(existing)) ?? 0) > 0
    }

    /// Names of saved chords, oldest first.
    static func savedNames(in context: ModelContext) -> [String] {
        let all = FetchDescriptor<SavedChord>(sortBy: [SortDescriptor(\.createdAt)])
        return ((try? context.fetch(all)) ?? []).map(\.name)
    }

    /// Saves the chord unless that exact shape, tuning and capo is already in the library.
    @discardableResult
    static func save(shape: ChordShape, tuning: Tuning, capo: Int, name: String, in context: ModelContext) -> SaveResult {
        guard !shape.isEmpty else { return .nothingToSave }
        let key = makeKey(shape: shape, tuning: tuning, capo: capo)
        let existing = FetchDescriptor<SavedChord>(predicate: #Predicate { $0.key == key })
        if ((try? context.fetchCount(existing)) ?? 0) > 0 { return .alreadySaved }
        context.insert(SavedChord(name: name, shape: shape, tuning: tuning, capo: capo))
        try? context.save()
        return .saved
    }
}
