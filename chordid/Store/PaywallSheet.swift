import SwiftUI

/// Why a paywall is showing; decides the headline, tiles and first table row.
enum PaywallReason: Identifiable, Equatable {
    /// Saving a chord past the free limit. `saved` = names of the chords already saved.
    case libraryFull(newChord: String, saved: [String])
    /// Picking a tuning other than Standard (or opening Custom tuning).
    case tuning(name: String)
    case capo(fret: Int)

    var id: String {
        switch self {
        case .libraryFull(let c, _): "library-\(c)"
        case .tuning(let n): "tuning-\(n)"
        case .capo(let f): "capo-\(f)"
        }
    }

    enum Feature: CaseIterable { case savedChords, alternateTunings, customTunings, capo, nameChords, strum }

    /// Table rows, with the feature that was tapped first.
    var rows: [Feature] {
        let first: Feature = switch self {
        case .libraryFull: .savedChords
        case .tuning(let name): name == PaywallReason.customName ? .customTunings : .alternateTunings
        case .capo: .capo
        }
        let paid: [Feature] = [.alternateTunings, .customTunings, .capo, .savedChords].filter { $0 != first }
        return [first] + paid + [.nameChords, .strum]
    }

    static let customName = "your own tuning"

    var eyebrow: String {
        switch self {
        case .libraryFull: "LIBRARY FULL · \(ProGate.freeSaveLimit) OF \(ProGate.freeSaveLimit)"
        case .tuning: "PRO TUNINGS"
        case .capo: "PRO CAPO"
        }
    }

    var headline: String {
        switch self {
        case .libraryFull(let chord, _): "Keep \(chord), and every chord after it"
        case .tuning(let name): "Play in \(name), and every other tuning"
        case .capo: "Capo on? Get the real chord names"
        }
    }

    var subtitle: String? {
        switch self {
        case .libraryFull: nil
        case .tuning: "Retuned strings change every chord name. Pro gets them right."
        case .capo: "A capo shifts every chord up. Pro names what you actually hear."
        }
    }

    var buttonTitle: String {
        switch self {
        case .libraryFull: "Unlock everything"
        case .tuning: "Unlock every tuning"
        case .capo: "Unlock the capo"
        }
    }

    /// The row of tiles under the headline: (label, locked, highlighted).
    var tiles: [(label: String, locked: Bool, highlighted: Bool)] {
        switch self {
        case .libraryFull(let chord, let saved):
            return saved.prefix(ProGate.freeSaveLimit).map { ($0, false, false) } + [(chord, true, true)]
        case .tuning(let name):
            var names = ["Standard", "Drop D", "DADGAD", "Open G"]
            let label = name == PaywallReason.customName ? "Custom" : name
            if !names.contains(label) { names[2] = label }
            return names.map { ($0, $0 != "Standard", $0 == label) }
        case .capo(let fret):
            // "Off" plus four frets around the one tapped.
            let start = min(max(fret - 1, 1), ChordIDModel.maxCapo - 3)
            return [("Off", false, false)] + (start..<(start + 4)).map { ("\($0)", true, $0 == fret) }
        }
    }
}

/// The Free vs Pro sheet (paywalls 01–03). One purchase unlocks everything.
struct PaywallSheet: View {
    let reason: PaywallReason
    let store: ProStore
    /// Called after a successful purchase or restore, before the sheet closes.
    let onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text(reason.eyebrow)
                            .font(BrandFont.font(15, .bold, relativeTo: .footnote))
                            .tracking(1)
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 12)
                        Spacer()
                        CircleIconButton(systemName: "xmark", style: .plain, label: "Close") { dismiss() }
                    }
                    Text(reason.headline)
                        .font(BrandFont.font(32, .extraBold, relativeTo: .largeTitle))
                        .tracking(-1)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle = reason.subtitle {
                        Text(subtitle)
                            .font(.brandBody)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                    tiles.padding(.top, 22)
                    FeatureTable(rows: reason.rows).padding(.top, 22)
                }
                .padding(.horizontal, Theme.sideMargin)
                .padding(.top, 24)
            }

            VStack(spacing: 10) {
                if let message {
                    Text(message)
                        .font(.brandSubheadline)
                        .foregroundStyle(Theme.warning)
                        .multilineTextAlignment(.center)
                }
                buyButton
                Text("Pay once. Yours forever. No subscription.")
                    .font(.brandBodyBold)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                if case .libraryFull = reason {
                    Text("Less than a set of strings.")
                        .font(.brandSubheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Button("Restore purchase") { Task { await restore() } }
                    .font(.brandBody)
                    .underline()
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minHeight: Theme.minTouch)
                    .disabled(store.isBusy)
            }
            .padding(.horizontal, Theme.sideMargin)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Theme.card)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .interactiveDismissDisabled(store.isBusy)
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            ForEach(Array(reason.tiles.enumerated()), id: \.offset) { _, tile in
                VStack(spacing: 2) {
                    if tile.locked {
                        Image(systemName: "lock")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Text(tile.label)
                        .font(BrandFont.font(17, .bold, relativeTo: .body))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(tile.highlighted ? Theme.accent : (tile.locked ? Theme.secondaryText : Theme.text))
                .frame(maxWidth: .infinity, minHeight: 72)
                .padding(.horizontal, 4)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                    if tile.highlighted {
                        shape.strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                    } else {
                        shape.fill(Theme.background)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.label + (tile.locked ? ", Pro" : ""))
            }
        }
    }

    private var buyButton: some View {
        Button {
            Task { await buy() }
        } label: {
            HStack {
                Text(reason.buttonTitle)
                    .font(BrandFont.font(20, .bold, relativeTo: .title3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if store.isBusy {
                    ProgressView().tint(.white)
                } else if let price = store.displayPrice {
                    Text(price).font(BrandFont.font(20, .bold, relativeTo: .title3))
                } else if !store.productUnavailable {
                    ProgressView().tint(.white)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Theme.accent, in: Capsule())
            .shadow(color: Theme.accent.opacity(0.3), radius: 16, y: 6)
        }
        .disabled(store.isBusy)
        .accessibilityLabel(store.displayPrice.map { "\(reason.buttonTitle), \($0)" } ?? reason.buttonTitle)
    }

    private func buy() async {
        message = nil
        switch await store.purchase() {
        case .purchased:
            unlocked()
        case .pending:
            message = "Waiting for approval. Pro unlocks as soon as it's approved."
        case .cancelled:
            break
        case .failed(let text):
            message = text
        }
    }

    private func restore() async {
        message = nil
        if await store.restore() {
            unlocked()
        } else {
            message = "No previous purchase found for this Apple Account."
        }
    }

    private func unlocked() {
        Haptics.chordNamed() // success pattern
        onUnlocked()
        dismiss()
    }
}

/// Free vs Pro comparison, the Pro column tinted.
private struct FeatureTable: View {
    let rows: [PaywallReason.Feature]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Color.clear.frame(height: 1)
                Text("Free").font(.brandBodySemibold).foregroundStyle(Theme.secondaryText)
                    .frame(width: 64).gridColumnAlignment(.center)
                Text("Pro").font(.brandBodySemibold).foregroundStyle(Theme.accent)
                    .frame(width: 104).gridColumnAlignment(.center)
            }
            .frame(minHeight: 50)
            ForEach(rows, id: \.self) { feature in
                Divider().gridCellColumns(2)
                GridRow {
                    Text(label(feature))
                        .font(isPaid(feature) ? .brandBodyBold : .brandBody)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    freeCell(feature).frame(width: 64)
                    proCell(feature).frame(width: 104)
                }
                .frame(minHeight: 50)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibility(feature))
            }
        }
        .background(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.accentSoft)
                .frame(width: 104)
        }
    }

    private func isPaid(_ f: PaywallReason.Feature) -> Bool { f != .nameChords && f != .strum }

    private func label(_ f: PaywallReason.Feature) -> String {
        switch f {
        case .savedChords: "Saved chords"
        case .alternateTunings: "Alternate tunings"
        case .customTunings: "Custom tunings"
        case .capo: "Capo, any fret"
        case .nameChords: "Name chords, tap or mic"
        case .strum: "Strum it back"
        }
    }

    @ViewBuilder private func freeCell(_ f: PaywallReason.Feature) -> some View {
        switch f {
        case .savedChords: Text("\(ProGate.freeSaveLimit)").font(.brandBody).foregroundStyle(Theme.secondaryText)
        case .nameChords, .strum: Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
        default: Text("–").font(.brandBody).foregroundStyle(Theme.tertiaryText)
        }
    }

    @ViewBuilder private func proCell(_ f: PaywallReason.Feature) -> some View {
        if f == .savedChords {
            Text("Unlimited").font(.brandBodyBold).foregroundStyle(Theme.accent).minimumScaleFactor(0.8)
        } else {
            Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.accent)
        }
    }

    private func accessibility(_ f: PaywallReason.Feature) -> String {
        switch f {
        case .savedChords: "Saved chords: free \(ProGate.freeSaveLimit), Pro unlimited"
        case .nameChords, .strum: "\(label(f)): free and Pro"
        default: "\(label(f)): Pro only"
        }
    }
}
