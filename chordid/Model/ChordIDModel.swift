import Foundation
import Observation

/// State for the Chord ID screen: the chosen tuning and what's on the fretboard.
@Observable
final class ChordIDModel {
    var tuning: Tuning {
        didSet { save(tuning, key: Keys.tuning) }
    }
    /// The last custom tuning the user built, kept so the editor reopens with it.
    var customTuning: Tuning {
        didSet { save(customTuning, key: Keys.customTuning) }
    }
    var shape: ChordShape

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let tuning = "tuning"
        static let customTuning = "customTuning"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let tuning = Self.load(Tuning.self, key: Keys.tuning, from: defaults) ?? .standard
        self.tuning = tuning
        self.customTuning = Self.load(Tuning.self, key: Keys.customTuning, from: defaults) ?? .custom(Tuning.standard.openNotes)
        self.shape = .empty(strings: tuning.stringCount)
    }

    var analysis: ChordAnalysis {
        ChordEngine.identify(shape: shape, tuning: tuning)
    }

    // MARK: - Fretboard editing

    /// Tap on a fret: place a dot there, or clear it if it's already there.
    /// Each string holds at most one note.
    func tapFret(string: Int, fret: Int) {
        guard shape.frets.indices.contains(string), (1...maxFret).contains(fret) else { return }
        shape.frets[string] = shape.frets[string] == fret ? nil : fret
    }

    /// Tap above the nut: muted → open → muted. A fretted string becomes open.
    func tapMarker(string: Int) {
        guard shape.frets.indices.contains(string) else { return }
        shape.frets[string] = shape.frets[string] == 0 ? nil : 0
    }

    func clear() {
        shape = .empty(strings: tuning.stringCount)
    }

    /// Note name to show on a string's dot, spelled to suit the current chord.
    func noteName(onString string: Int) -> String? {
        guard let note = shape.notesByString(in: tuning)[string] else { return nil }
        if let best = analysis.best { return best.name(for: note.pitchClass) }
        return note.pitchClass.defaultName
    }

    // MARK: - Persistence

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
