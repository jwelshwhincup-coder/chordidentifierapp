import Foundation
import StoreKitTest
import Testing
@testable import chordid

struct ProGateTests {
    @Test func freeTier() {
        #expect(ProGate.allows(tuning: .standard, isPro: false))
        for tuning in Tuning.presets where tuning != .standard {
            #expect(!ProGate.allows(tuning: tuning, isPro: false), "\(tuning.name)")
        }
        #expect(!ProGate.allows(tuning: .custom(Tuning.standard.openNotes), isPro: false))
        #expect(ProGate.allowsCapo(0, isPro: false))
        #expect(!ProGate.allowsCapo(1, isPro: false))
        #expect(ProGate.allowsSave(savedCount: 2, isPro: false))
        #expect(!ProGate.allowsSave(savedCount: 3, isPro: false))
    }

    @Test func proUnlocksEverything() {
        #expect(Tuning.presets.allSatisfy { ProGate.allows(tuning: $0, isPro: true) })
        #expect(ProGate.allows(tuning: .custom(Tuning.dadgad.openNotes), isPro: true))
        #expect((0...12).allSatisfy { ProGate.allowsCapo($0, isPro: true) })
        #expect(ProGate.allowsSave(savedCount: 500, isPro: true))
    }
}

struct PaywallContentTests {
    @Test func libraryFull() {
        let r = PaywallReason.libraryFull(newChord: "F♯m7♭5", saved: ["Cmaj9", "E7♯9", "G/B"])
        #expect(r.eyebrow == "LIBRARY FULL · 3 OF 3")
        #expect(r.headline == "Keep F♯m7♭5, and every chord after it")
        #expect(r.tiles.map(\.label) == ["Cmaj9", "E7♯9", "G/B", "F♯m7♭5"])
        #expect(r.tiles.map(\.locked) == [false, false, false, true])
        #expect(r.rows.first == .savedChords)
        #expect(r.buttonTitle == "Unlock everything")
    }

    @Test func tuningHighlightsTheTappedOne() {
        let dadgad = PaywallReason.tuning(name: "DADGAD")
        #expect(dadgad.headline == "Play in DADGAD, and every other tuning")
        #expect(dadgad.tiles.map(\.label) == ["Standard", "Drop D", "DADGAD", "Open G"])
        #expect(dadgad.tiles.filter(\.highlighted).map(\.label) == ["DADGAD"])
        #expect(dadgad.rows.first == .alternateTunings)
        let openE = PaywallReason.tuning(name: "Open E")
        #expect(openE.tiles.map(\.label) == ["Standard", "Drop D", "Open E", "Open G"])
        #expect(openE.tiles.filter(\.highlighted).map(\.label) == ["Open E"])
        let custom = PaywallReason.tuning(name: PaywallReason.customName)
        #expect(custom.rows.first == .customTunings)
        #expect(custom.tiles.filter(\.highlighted).map(\.label) == ["Custom"])
    }

    @Test func capoTilesFollowTheFret() {
        #expect(PaywallReason.capo(fret: 2).tiles.map(\.label) == ["Off", "1", "2", "3", "4"])
        #expect(PaywallReason.capo(fret: 7).tiles.map(\.label) == ["Off", "6", "7", "8", "9"])
        #expect(PaywallReason.capo(fret: 12).tiles.map(\.label) == ["Off", "9", "10", "11", "12"])
        #expect(PaywallReason.capo(fret: 7).tiles.filter(\.highlighted).map(\.label) == ["7"])
        #expect(PaywallReason.capo(fret: 2).rows.first == .capo)
    }

    @Test func everyTableHasAllSixRowsOnce() {
        for r in [PaywallReason.libraryFull(newChord: "C", saved: []), .tuning(name: "Drop D"), .capo(fret: 1)] {
            #expect(Set(r.rows).count == 6 && r.rows.count == 6)
        }
    }
}

/// Real StoreKit 2 calls against the Products.storekit configuration, in a local test session.
@Suite(.serialized)
struct ProStoreTests {
    private func session() throws -> SKTestSession {
        let s = try SKTestSession(configurationFileNamed: "Products")
        s.resetToDefaultState()
        s.clearTransactions()
        s.disableDialogs = true
        return s
    }

    private func freshDefaults() -> UserDefaults {
        let name = "ProStoreTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func loadsTheLocalisedPrice() async throws {
        let s = try session()
        defer { s.clearTransactions() }
        let store = ProStore(defaults: freshDefaults())
        await store.loadProduct()
        #expect(store.product?.id == ProStore.productID)
        #expect(store.displayPrice == "£4.99")
        #expect(store.product?.type == .nonConsumable)
    }

    @Test func purchaseUnlocksAndPersists() async throws {
        let s = try session()
        defer { s.clearTransactions() }
        let defaults = freshDefaults()
        let store = ProStore(defaults: defaults)
        await store.refreshEntitlements()
        #expect(!store.isPro)
        await store.loadProduct()
        #expect(await store.purchase() == .purchased)
        #expect(store.isPro)
        // A fresh launch sees the purchase from StoreKit's records, not just the cache.
        let relaunched = ProStore(defaults: freshDefaults())
        #expect(!relaunched.isPro)
        await relaunched.refreshEntitlements()
        #expect(relaunched.isPro)
    }

    @Test func refundRemovesTheUnlock() async throws {
        let s = try session()
        defer { s.clearTransactions() }
        let store = ProStore(defaults: freshDefaults())
        await store.loadProduct()
        #expect(await store.purchase() == .purchased)
        let transaction = try #require(s.allTransactions().first)
        try s.refundTransaction(identifier: transaction.identifier)
        // The refund reaches StoreKit's records asynchronously.
        for _ in 0..<20 where store.isPro {
            try await Task.sleep(for: .milliseconds(100))
            await store.refreshEntitlements()
        }
        #expect(!store.isPro)
    }

    @Test func askToBuyIsPending() async throws {
        let s = try session()
        defer { s.clearTransactions(); s.askToBuyEnabled = false }
        s.askToBuyEnabled = true
        let store = ProStore(defaults: freshDefaults())
        await store.loadProduct()
        #expect(await store.purchase() == .pending)
        #expect(!store.isPro)
    }
}
