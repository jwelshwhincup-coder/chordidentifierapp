import SwiftData
import SwiftUI

/// The main screen: tuning and capo pickers, fretboard, then either the
/// chord result or, while the mic is on, the string-by-string prompt.
struct ChordIDView: View {
    @Bindable var model: ChordIDModel
    var listener: ListeningController
    var player: GuitarPlayer
    var store: ProStore
    /// Tells the shell a sheet is up, so it can scale the screen back.
    @Binding var sheetShown: Bool
    /// The first-launch demo is playing over this screen.
    var demoRunning = false
    @State private var showTuning = false
    @State private var showCapo = false
    @State private var showSettings = false
    @State private var toast: String?
    @State private var paywall: PaywallReason?
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupBar(
                tuningName: model.tuning.name,
                capo: model.capo,
                capoLocked: !store.isPro,
                onTuning: { showTuning = true },
                onCapo: { showCapo = true },
                onSettings: { showSettings = true }
            )
            .disabled(listener.isListening)
            .padding(.top, 8)

            FretboardView(
                tuning: model.soundingTuning,
                shape: model.shape,
                capo: model.capo,
                // With a capo, keep the tuning's own string names (what you'd call the strings).
                stringLabels: model.tuning.stringNames,
                highlightedStrings: listener.isListening
                    ? (listener.session?.currentString.map { [$0] } ?? [])
                    : player.activeStrings,
                listeningString: listener.isListening ? (listener.session?.currentString ?? model.tuning.stringCount) : nil,
                vibratingSince: player.vibratingSince,
                noteName: { model.noteName(onString: $0) },
                onTapFret: listener.isListening ? nil : { Haptics.fretTap(); model.tapFret(string: $0, fret: $1) },
                onTapMarker: listener.isListening ? nil : { Haptics.fretTap(); model.tapMarker(string: $0) }
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
        .overlay(alignment: .top) {
            if let toast {
                Label(toast, systemImage: toast.hasPrefix("Saved") ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.brandBodySemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.text, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .sheet(isPresented: $showTuning) {
            TuningSheet(model: model, store: store)
        }
        .sheet(isPresented: $showCapo) {
            CapoSheet(model: model, store: store)
        }
        .sheet(item: $paywall) { reason in
            PaywallSheet(reason: reason, store: store) { save() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .onChange(of: showTuning || showCapo || showSettings || paywall != nil) { _, shown in sheetShown = shown }
        .environment(\.demoAnchorsEnabled, true)
        .onAppear { Haptics.prepare() }
        // Success haptic once a chord settles (not on every intermediate tap or mic step).
        .task(id: model.analysis.best?.symbol) {
            guard let best = model.analysis.best, best.kind == .chord, !listener.isListening, !demoRunning else { return }
            try? await Task.sleep(for: .milliseconds(450))
            if !Task.isCancelled { Haptics.chordNamed() }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ResultView(analysis: model.analysis,
                       shapeNote: model.shapeName.map { "\($0) shape, capo \(model.capo)" },
                       onClear: model.shape.isEmpty ? nil : { model.clear() })

            HStack(spacing: 12) {
                Button {
                    player.strum(shape: model.shape, tuning: model.soundingTuning)
                } label: {
                    Label("Strum", systemImage: "play")
                        .labelStyle(SpacedLabelStyle())
                }
                .buttonStyle(PillButtonStyle(kind: .secondary))
                .frame(maxWidth: 140)
                .demoTarget(.strum)
                .disabled(model.shape.isEmpty || !player.isAvailable)
                .accessibilityHint("Plays the chord")

                Button("Save to library", action: save)
                    .buttonStyle(PillButtonStyle(kind: .primaryDark))
                    .disabled(model.shape.isEmpty)
            }
        }
        .demoTarget(.result)
    }
}

extension ChordIDView {
    /// Saves straight away under the detected name. An identical shape in the same
    /// tuning and capo is only saved once.
    fileprivate func save() {
        let name = model.analysis.best?.displayName ?? "Chord"
        guard !model.shape.isEmpty else { return }
        if SavedChord.exists(shape: model.shape, tuning: model.tuning, capo: model.capo, in: context) {
            show("Already in your library")
            return
        }
        let saved = SavedChord.savedNames(in: context)
        guard ProGate.allowsSave(savedCount: saved.count, isPro: store.isPro) else {
            // Library full: offer Pro, naming the chord they're saving. Nothing already saved is touched.
            paywall = .libraryFull(newChord: model.analysis.best?.symbol ?? name, saved: Array(saved.prefix(ProGate.freeSaveLimit)))
            return
        }
        let result = SavedChord.save(shape: model.shape, tuning: model.tuning, capo: model.capo, name: name, in: context)
        switch result {
        case .saved:
            Haptics.saved()
            show("Saved to library")
        case .alreadySaved: show("Already in your library")
        case .nothingToSave: break
        }
    }

    fileprivate func show(_ message: String) {
        withAnimation(.spring(duration: 0.35)) { toast = message }
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.3)) { if toast == message { toast = nil } }
        }
    }
}

/// Top bar: one capsule split into Tuning and Capo, plus a round settings button
/// of the same height, so the three read as one set of controls.
struct SetupBar: View {
    let tuningName: String
    let capo: Int
    var capoLocked = false
    let onTuning: () -> Void
    let onCapo: () -> Void
    let onSettings: () -> Void

    static let height: CGFloat = 58

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                segment(caption: "Tuning", value: tuningName, padding: 20, action: onTuning)
                    .layoutPriority(1)
                    .accessibilityLabel("Tuning, \(tuningName)")
                    .accessibilityHint("Opens the tuning picker")
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1, height: 28)
                segment(caption: "Capo", value: capo == 0 ? "None" : "Fret \(capo)", padding: 16,
                        locked: capoLocked, action: onCapo)
                    .frame(width: 112)
                    .accessibilityLabel(capo == 0 ? "No capo" : "Capo on fret \(capo)")
                    .accessibilityHint("Opens the capo picker")
            }
            .frame(height: Self.height)
            .background(Theme.card, in: Capsule())

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.text)
                    .frame(width: Self.height, height: Self.height)
                    .background(Theme.card, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
    }

    private func segment(caption: String, value: String, padding: CGFloat, locked: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(caption.uppercased())
                            .font(BrandFont.font(11, .semibold, relativeTo: .caption2))
                            .tracking(0.8)
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .accessibilityLabel("Pro")
                        }
                    }
                    .foregroundStyle(Theme.secondaryText)
                    Text(value)
                        .font(.brandBodySemibold)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
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
                LevelMeter(level: listener.level)
                    .frame(width: 44, height: 36)
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

/// Five bars that bounce with the microphone level (mockup 1's waveform, live).
struct LevelMeter: View {
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let shape: [Double] = [0.45, 0.8, 1.0, 0.7, 0.4]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(shape.indices, id: \.self) { i in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 4.5)
                    .frame(height: max(6, 36 * shape[i] * (0.2 + 0.8 * displayed)))
            }
        }
        .frame(maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: level)
    }

    private var displayed: Double { reduceMotion ? (level > 0.15 ? 0.7 : 0.2) : level }
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
    let store: ProStore
    @Environment(\.dismiss) private var dismiss
    @State private var staged: Int
    @State private var paywall: PaywallReason?
    @State private var closeAfterPaywall = false

    init(model: ChordIDModel, store: ProStore) {
        self.model = model
        self.store = store
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
                    // A capo a free user already had stays usable; new frets need Pro.
                    let locked = !ProGate.allowsCapo(fret, isPro: store.isPro) && fret != model.capo
                    Button {
                        if locked { paywall = .capo(fret: fret) } else { staged = fret }
                    } label: {
                        HStack(spacing: 4) {
                            if locked {
                                Image(systemName: "lock")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Text(fret == 0 ? "None" : "\(fret)")
                                .font(.brandHeadline)
                                .foregroundStyle(selected ? .white : Theme.text)
                        }
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(selected ? Theme.accent : Theme.background,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel((fret == 0 ? "No capo" : "Capo on fret \(fret)") + (locked ? ", Pro" : ""))
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
        .sheet(item: $paywall, onDismiss: { if closeAfterPaywall { dismiss() } }) { reason in
            PaywallSheet(reason: reason, store: store) {
                if case .capo(let fret) = reason { model.setCapo(fret) }
                closeAfterPaywall = true
            }
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    // Old and new names overlap while they cross-fade.
                    ZStack(alignment: .leading) {
                    Text(best.displayName)
                        .font(.brandChordName)
                        .tracking(-1.5)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        // A new name springs in; the old one fades out underneath.
                        .id(best.symbol)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .scale(scale: 0.7, anchor: .leading).combined(with: .opacity),
                            removal: .opacity))
                    }
                    .animation(nameAnimation, value: best.symbol)
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

    private var nameAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.62)
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
    ChordIDView(model: ChordIDModel(), listener: ListeningController(), player: GuitarPlayer(), store: ProStore(), sheetShown: .constant(false))
        .modelContainer(for: SavedChord.self, inMemory: true)
        .background(Theme.background)
}
