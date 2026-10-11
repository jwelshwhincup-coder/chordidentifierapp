import Foundation
import SwiftData
import Testing
@testable import chordid

struct LibraryTests {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: SavedChord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func savesAndRoundTrips() throws {
        let ctx = try context()
        let shape = ChordShape("x32010")!
        #expect(SavedChord.save(shape: shape, tuning: .standard, capo: 2, name: "C major", in: ctx) == .saved)
        let all = try ctx.fetch(FetchDescriptor<SavedChord>())
        #expect(all.count == 1)
        let c = all[0]
        #expect(c.shape == shape)
        #expect(c.tuning == .standard)
        #expect(c.capo == 2)
        #expect(c.summary == "Standard · Capo 2 · x 3 2 0 1 0")
        #expect(c.analysis.best?.displayName == "D major")
    }

    @Test func identicalChordIsNotSavedTwice() throws {
        let ctx = try context()
        let g = ChordShape("320003")!
        #expect(SavedChord.save(shape: g, tuning: .standard, capo: 0, name: "G major", in: ctx) == .saved)
        #expect(SavedChord.save(shape: g, tuning: .standard, capo: 0, name: "G major", in: ctx) == .alreadySaved)
        #expect(try ctx.fetchCount(FetchDescriptor<SavedChord>()) == 1)
    }

    @Test func sameChordElsewhereIsANewEntry() throws {
        let ctx = try context()
        #expect(SavedChord.save(shape: ChordShape("320003")!, tuning: .standard, capo: 0, name: "G major", in: ctx) == .saved)
        // Different position (barre G)
        #expect(SavedChord.save(shape: ChordShape("355433")!, tuning: .standard, capo: 0, name: "G major", in: ctx) == .saved)
        // Different capo
        #expect(SavedChord.save(shape: ChordShape("320003")!, tuning: .standard, capo: 3, name: "G major", in: ctx) == .saved)
        // Different tuning
        #expect(SavedChord.save(shape: ChordShape("320003")!, tuning: .dropD, capo: 0, name: "G major", in: ctx) == .saved)
        #expect(try ctx.fetchCount(FetchDescriptor<SavedChord>()) == 4)
    }

    @Test func emptyBoardIsNotSaved() throws {
        let ctx = try context()
        #expect(SavedChord.save(shape: .empty(), tuning: .standard, capo: 0, name: "x", in: ctx) == .nothingToSave)
    }

    @Test func searchMatchesNamesAndTunings() {
        let c = SavedChord(name: "F♯m", shape: ChordShape("244222")!, tuning: .dadgad, capo: 0)
        #expect(c.matches(""))
        #expect(c.matches("f#m"))
        #expect(c.matches("F♯"))
        #expect(c.matches("dadgad"))
        #expect(!c.matches("Em"))
        c.name = "Intro chord"
        #expect(c.matches("intro"))
        #expect(c.matches("F#m")) // still finds it by the detected name
    }
}
