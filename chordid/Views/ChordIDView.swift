import SwiftUI

/// The main screen: tuning and capo pickers, fretboard, then either the
/// chord result or, while the mic is on, the string-by-string prompt.
struct ChordIDView: View {
    @Bindable var model: ChordIDModel
    var listener: ListeningController
    @State private var showTuning = false
    @State private var showCapo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                PillMenuButton(title: model.tuning.name, accessibilityLabel: "Tuning: \(model.tuning.name)",
                               hint: "Opens the tuning picker") { showTuning = true }
                Spacer(minLength: 0)
                PillMenuButton(title: model.capo == 0 ? "No capo" : "Capo \(model.capo)",
                               accessibilityLabel: model.capo == 0 ? "No capo" : "Capo on fret \(model.capo)",
                               hint: "Opens the capo picker") { showCapo = true }
            }
            .disabled(listener.isListening)
            .padding(.top, 8)

            FretboardView(
                tuning: model.soundingTuning,
                shape: model.shape,
                capo: model.capo,
                highlightedStrings: listener.session?.currentString.map { [$0] } ?? [],
                listeningString: listener.isListening ? (listener.session?.currentString ?? model.tuning.stringCount) : nil,
                noteName: { model.noteName(onString: $0) },
                onTapFret: listener.isListening ? nil : { model.tapFret(string: $0, fret: $1) },
                onTapMarker: listener.isListening ? nil : { model.tapMarker(string: $0) }
            )
            .frame(minHeight: 240, maxHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .card()
            .layoutPriority(1)
            .padding(.top, 16)

            Group {
                switch listener.phase {
                case .listening:
                    ListeningPanel(model: model, listener: listener)
                case .denied:
                    MicProblemView(title: "Microphone is off",
                                   message: "To listen to your guitar, allow Chord ID to use the microphone in Settings.",
                                   showSettings: true, onDismiss: listener.dismissProblem)
                case .failed:
                    MicProblemView(title: "Couldn't start the microphone",
                                   message: "Another app or a call may be using it. Close it and tap the mic again.",
                                   showSettings: false, onDismiss: listener.dismissProblem)
                case .idle:
                    resultSection
                }
            }
            .padding(.top, 24)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.sideMargin)
        .sheet(isPresented: $showTuning) {
            TuningSheet(model: model)
        }
        .sheet(isPresented: $showCapo) {
            CapoSheet(model: model)
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ResultView(analysis: model.analysis,
                       shapeNote: model.shapeName.map { "\($0) shape, capo \(model.capo)" },
                       onClear: model.shape.isEmpty ? nil : { model.clear() })

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
        }
    }
}

/// White capsule with a title and a chevron (tuning, capo).
struct PillMenuButton: View {
    let title: String
    let accessibilityLabel: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(hint)
    }
}

/// "Play the D string / String 3 of 6, low to high" with Skip and Start over (mockup 1).
struct ListeningPanel: View {
    let model: ChordIDModel
    let listener: ListeningController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(BrandFont.font(30, .extraBold, relativeTo: .title))
                        .tracking(-0.8)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(subtitle)
                        .font(.brandBody)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "waveform", variableValue: listener.level)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)

            if let problem = listener.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.brandSubheadline)
                    .foregroundStyle(Theme.warning)
                    .accessibilityLabel(problem)
            }

            HStack(spacing: 12) {
                Button("Skip string", action: listener.skipString)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .accessibilityHint("Marks this string as not played")
                Button("Start over", action: listener.startOver)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
        }
    }

    private var stringIndex: Int { listener.session?.currentString ?? 0 }

    private var title: String {
        let name = model.soundingTuning.stringNames[min(stringIndex, model.tuning.stringCount - 1)]
        return "Play the \(name) string"
    }

    private var subtitle: String {
        "String \(stringIndex + 1) of \(model.tuning.stringCount), low to high"
    }
}

/// Shown when the microphone can't be used.
struct MicProblemView: View {
    let title: String
    let message: String
    let showSettings: Bool
    let onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(BrandFont.font(28, .extraBold, relativeTo: .title))
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.brandBody)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 12) {
                if showSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(PillButtonStyle(kind: .primaryDark))
                }
                Button("Not now", action: onDismiss)
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
            .padding(.top, 8)
        }
    }
}

/// Bottom sheet for the capo fret, styled like the tuning sheet.
struct CapoSheet: View {
    @Bindable var model: ChordIDModel
    @Environment(\.dismiss) private var dismiss
    @State private var staged: Int

    init(model: ChordIDModel) {
        self.model = model
        _staged = State(initialValue: model.capo)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(systemName: "xmark", style: .plain, label: "Cancel") { dismiss() }
                Spacer()
                Text("Capo")
                    .font(.brandTitle)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                CircleIconButton(systemName: "checkmark", style: .accent, label: "Use this capo") {
                    if staged != model.capo { model.setCapo(staged) }
                    dismiss()
                }
            }
            .padding(.horizontal, Theme.sideMargin)
            .padding(.top, 28)
            .padding(.bottom, 20)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0...ChordIDModel.maxCapo, id: \.self) { fret in
                    let selected = staged == fret
                    Button {
                        staged = fret
                    } label: {
                        Text(fret == 0 ? "None" : "\(fret)")
                            .font(.brandHeadline)
                            .foregroundStyle(selected ? .white : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(selected ? Theme.accent : Theme.background,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(fret == 0 ? "No capo" : "Capo on fret \(fret)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.sideMargin)

            Text("Tap the shape you're fretting. Chord names show what actually sounds.")
                .font(.brandSubheadline)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.sideMargin)
                .padding(.top, 16)
            Spacer(minLength: 0)
        }
        .background(Theme.card)
        .presentationDetents([.height(440), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
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
    /// e.g. "C shape, capo 2".
    var shapeNote: String?
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

                if let shapeNote {
                    Text(shapeNote)
                        .font(.brandSubheadline)
                        .foregroundStyle(Theme.accent)
                }
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
    ChordIDView(model: ChordIDModel(), listener: ListeningController())
        .background(Theme.background)
}
