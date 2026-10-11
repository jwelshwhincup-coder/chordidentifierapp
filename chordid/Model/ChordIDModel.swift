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
    /// Capo fret, 0 = no capo. Shapes are entered relative to the capo.
    var capo: Int {
        didSet { defaults.set(capo, forKey: Keys.capo) }
    }
    var shape: ChordShape

    static let maxCapo = 12

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let tuning = "tuning"
        static let customTuning = "customTuning"
        static let capo = "capo"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let tuning = Self.load(Tuning.self, key: Keys.tuning, from: defaults) ?? .standard
        self.tuning = tuning
        self.customTuning = Self.load(Tuning.self, key: Keys.customTuning, from: defaults) ?? .custom(Tuning.standard.openNotes)
        self.capo = min(max(defaults.integer(forKey: Keys.capo), 0), Self.maxCapo)
        self.shape = .empty(strings: tuning.stringCount)
    }

    /// What the open strings actually sound like with the capo on.
    var soundingTuning: Tuning {
        guard capo > 0 else { return tuning }
        var t = tuning
        t.openNotes = tuning.openNotes.map { Note(midi: $0.midi + capo) }
        return t
    }

    /// Highest fret you can tap above the capo.
    var maxShapeFret: Int { maxFret - capo }

    /// The chord that's sounding (capo included).
    var analysis: ChordAnalysis {
        ChordEngine.identify(shape: shape, tuning: soundingTuning)
    }

    /// With a capo, the name of the shape as if there were no capo ("C shape").
    var shapeName: String? {
        guard capo > 0, let best = ChordEngine.identify(shape: shape, tuning: tuning).best, best.kind == .chord else { return nil }
        return best.symbol
    }

    // MARK: - Fretboard editing

    /// Tap on a fret: place a dot there, or clear it if it's already there.
    /// Each string holds at most one note.
    func tapFret(string: Int, fret: Int) {
        guard shape.frets.indices.contains(string), (1...maxShapeFret).contains(fret) else { return }
        shape.frets[string] = shape.frets[string] == fret ? nil : fret
    }

    /// Tap above the nut: muted → open → muted. A fretted string becomes open.
    func tapMarker(string: Int) {
        guard shape.frets.indices.contains(string) else { return }
        shape.frets[string] = shape.frets[string] == 0 ? nil : 0
    }

    func setCapo(_ newCapo: Int) {
        capo = min(max(newCapo, 0), Self.maxCapo)
        // Drop any dot that would now sit past the last fret.
        shape.frets = shape.frets.map { fret in fret.flatMap { $0 <= maxShapeFret ? $0 : nil } }
    }

    func clear() {
        shape = .empty(strings: tuning.stringCount)
    }

    /// Note name to show on a string's dot, spelled to suit the current chord.
    func noteName(onString string: Int) -> String? {
        guard let note = shape.notesByString(in: soundingTuning)[string] else { return nil }
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
