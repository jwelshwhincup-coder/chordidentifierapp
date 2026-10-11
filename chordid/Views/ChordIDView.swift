import SwiftUI

/// The main screen: tuning picker, fretboard, chord result, Strum and Save.
struct ChordIDView: View {
    @Bindable var model: ChordIDModel
    @State private var showTuning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Chord ID")
                    .font(.brandLargeTitle)
                    .tracking(-1.2)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                tuningButton
            }
            .padding(.top, 8)

            FretboardView(
                tuning: model.tuning,
                shape: model.shape,
                noteName: { model.noteName(onString: $0) },
                onTapFret: { model.tapFret(string: $0, fret: $1) },
                onTapMarker: { model.tapMarker(string: $0) }
            )
            .frame(minHeight: 240, maxHeight: 380)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .card()
            .layoutPriority(1)
            .padding(.top, 20)

            ResultView(analysis: model.analysis, onClear: model.shape.isEmpty ? nil : { model.clear() })
                .padding(.top, 24)

            HStack(spacing: 12) {
                Button {} label: {
                    Label("Strum", systemImage: "play")
                        .labelStyle(SpacedLabelStyle())
                }
                .buttonStyle(PillButtonStyle(kind: .secondary))
                .frame(maxWidth: 140)
                .disabled(true)
                .accessibilityHint("Playback arrives in a later update")

                Button("Save to library") {}
                    .buttonStyle(PillButtonStyle(kind: .primaryDark))
                    .disabled(true)
                    .accessibilityHint("Saving arrives in a later update")
            }
            .padding(.top, 20)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.sideMargin)
        .sheet(isPresented: $showTuning) {
            TuningSheet(model: model)
        }
    }

    private var tuningButton: some View {
        Button {
            showTuning = true
        } label: {
            HStack(spacing: 8) {
                Text(model.tuning.name)
                    .font(.brandBody)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18)
            .frame(minHeight: Theme.minTouch)
            .background(Theme.card, in: Capsule())
        }
        .accessibilityLabel("Tuning: \(model.tuning.name)")
        .accessibilityHint("Opens the tuning picker")
    }
}

/// Icon and title with a little more breathing room than the default.
struct SpacedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
            configuration.title
        }
    }
}

/// "That's a / C major / C · E · G" plus other possible names.
struct ResultView: View {
    let analysis: ChordAnalysis
    var onClear: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(lead)
                    .font(.brandBody)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if let onClear {
                    Button("Clear", action: onClear)
                        .font(.brandSubheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(minWidth: Theme.minTouch, minHeight: 28)
                        .accessibilityHint("Removes every note from the fretboard")
                }
            }

            if let best = analysis.best {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(best.displayName)
                        .font(.brandChordName)
                        .tracking(-1.5)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Spacer(minLength: 8)
                    if best.kind != .unrecognized {
                        Text(best.toneNames.joined(separator: " · "))
                            .font(.brandBodySemibold)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .accessibilityElement(children: .combine)

                if let detail = best.detail {
                    Text(detail)
                        .font(.brandSubheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                if !analysis.alternatives.isEmpty {
                    Text("Could also be " + analysis.alternatives.map(\.symbol).joined(separator: ", "))
                        .font(.brandSubheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
            } else {
                Text("Pick a chord")
                    .font(.brandChordName)
                    .tracking(-1.5)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("Tap the frets, or tap the mic and play each string.")
                    .font(.brandSubheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var lead: String {
        guard let best = analysis.best else { return "Nothing yet" }
        switch best.kind {
        case .note: return "That's the note"
        case .unrecognized: return "Notes played"
        default:
            // "an" before names that start with a vowel sound: A, E, F ("eff").
            let first = best.displayName.first.map(String.init) ?? ""
            return ["A", "E", "F"].contains(first) ? "That's an" : "That's a"
        }
    }
}

#Preview {
    ChordIDView(model: ChordIDModel())
        .background(Theme.background)
}
