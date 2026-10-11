import Foundation
import Observation
import StoreKit

/// What free users can do, and what needs Pro. Kept separate from StoreKit so it's easy to test.
enum ProGate {
    static let freeSaveLimit = 3

    static func allows(tuning: Tuning, isPro: Bool) -> Bool {
        isPro || tuning.id == Tuning.standard.id
    }

    static func allowsCapo(_ fret: Int, isPro: Bool) -> Bool {
        isPro || fret == 0
    }

    static func allowsSave(savedCount: Int, isPro: Bool) -> Bool {
        isPro || savedCount < freeSaveLimit
    }
}

/// The one-off "Chord ID Pro" purchase (StoreKit 2, non-consumable).
///
/// The unlock comes from StoreKit's own record of the user's purchases
/// (`Transaction.currentEntitlements`), which iOS keeps on the device, so it
/// works offline after the first check and comes back after a reinstall.
/// A cached flag only avoids a flash of locks while that check runs.
@Observable
final class ProStore {
    static let productID = "com.wellyboot.chordid.pro"
    static let cacheKey = "isProCached"

    enum PurchaseOutcome: Equatable {
        case purchased
        /// Waiting for approval (Ask to Buy).
        case pending
        case cancelled
        case failed(String)
    }

    private(set) var isPro: Bool
    private(set) var product: Product?
    /// The product couldn't be loaded (no connection, or not set up in App Store Connect).
    private(set) var productUnavailable = false
    private(set) var isBusy = false

    /// The localised price from the App Store, e.g. "£4.99". Never hard-coded.
    var displayPrice: String? { product?.displayPrice }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPro = defaults.bool(forKey: Self.cacheKey)
    }

    /// Call once at launch: loads the product, checks existing purchases and
    /// listens for purchases made elsewhere (another device, Ask to Buy approval, refunds).
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            productUnavailable = product == nil
        } catch {
            productUnavailable = true
        }
    }

    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setPro(owned)
    }

    func purchase() async -> PurchaseOutcome {
        if product == nil { await loadProduct() }
        guard let product else { return .failed("The App Store isn't available right now. Check your connection and try again.") }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("The purchase couldn't be verified. Nothing was charged twice; try Restore purchase.")
                }
                await transaction.finish()
                setPro(true)
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Asks the App Store for the user's purchases again. Returns whether Pro is unlocked.
    func restore() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        try? await AppStore.sync()
        await refreshEntitlements()
        return isPro
    }

    private func setPro(_ value: Bool) {
        isPro = value
        defaults.set(value, forKey: Self.cacheKey)
    }

    #if DEBUG
    /// Test hook: pretend the unlock state changed.
    func setProForTesting(_ value: Bool) { setPro(value) }
    #endif
}
