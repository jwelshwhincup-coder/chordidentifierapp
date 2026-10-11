import SwiftUI

/// Bottom sheet for choosing a tuning. Changes apply only when the check is tapped.
struct TuningSheet: View {
    @Bindable var model: ChordIDModel
    @Environment(\.dismiss) private var dismiss
    @State private var staged: Tuning
    @State private var showCustom = false

    init(model: ChordIDModel) {
        self.model = model
        _staged = State(initialValue: model.tuning)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Tuning.presets) { preset in
                            row(name: preset.name, notes: preset.stringNames, selected: staged == preset) {
                                staged = preset
                            }
                        }
                        row(name: "Custom tuning",
                            notes: staged.isCustom ? staged.stringNames : nil,
                            selected: staged.isCustom,
                            chevron: true,
                            divider: false) {
                            showCustom = true
                        }
                    }
                    .padding(.horizontal, Theme.sideMargin)
                }
            }
            .background(Theme.card)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showCustom) {
                CustomTuningView(start: staged.isCustom ? staged : model.customTuning) { custom in
                    model.customTuning = custom
                    staged = custom
                }
            }
        }
        .presentationDetents([.fraction(0.74), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private var header: some View {
        HStack {
            CircleIconButton(systemName: "xmark", style: .plain, label: "Cancel") { dismiss() }
            Spacer()
            Text("Tuning")
                .font(.brandTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            CircleIconButton(systemName: "checkmark", style: .accent, label: "Use this tuning") {
                if staged != model.tuning {
                    model.tuning = staged
                }
                dismiss()
            }
        }
        .padding(.horizontal, Theme.sideMargin)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private func row(name: String, notes: [String]?, selected: Bool, chevron: Bool = false,
                     divider: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(name)
                        .font(.brandHeadline)
                        .foregroundStyle(selected ? Theme.accent : Theme.text)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    if let notes {
                        // Space between notes rather than letter-spacing, so "E♭" stays together.
                        Text(notes.joined(separator: "\u{2002}"))
                            .font(.brandBodySemibold)
                            .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    if chevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(minHeight: 56)
                .padding(.vertical, 2)
                if divider { Rectangle().fill(Theme.divider).frame(height: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notes.map { "\(name), \($0.joined(separator: " "))" } ?? name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 44pt round icon button (sheet X / check, back, more).
struct CircleIconButton: View {
    enum Style { case plain, accent, card }
    let systemName: String
    var style: Style = .plain
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(style == .accent ? .white : Theme.text)
                .frame(width: Theme.minTouch, height: Theme.minTouch)
                .background(background, in: Circle())
        }
        .accessibilityLabel(label)
    }

    private var background: Color {
        switch style {
        case .plain: Theme.background
        case .accent: Theme.accent
        case .card: Theme.card
        }
    }
}

/// Pick any note for each string.
struct CustomTuningView: View {
    let onUse: (Tuning) -> Void
    @State private var notes: [Note]
    @Environment(\.dismiss) private var dismiss

    private static let range = 28...76 // E1 … E5

    init(start: Tuning, onUse: @escaping (Tuning) -> Void) {
        self.onUse = onUse
        _notes = State(initialValue: start.openNotes)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(systemName: "chevron.left", style: .plain, label: "Back") { dismiss() }
                Spacer()
                Text("Custom tuning")
                    .font(.brandTitle)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Menu {
                    ForEach(Tuning.presets) { preset in
                        Button(preset.name) { notes = preset.openNotes }
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: Theme.minTouch, height: Theme.minTouch)
                        .background(Theme.background, in: Circle())
                }
                .accessibilityLabel("Start from a preset")
            }
            .padding(.horizontal, Theme.sideMargin)
            .padding(.top, 28)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    Text("Lowest string first")
                        .font(.brandSubheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    ForEach(notes.indices, id: \.self) { i in
                        stringRow(i)
                    }
                }
                .padding(.horizontal, Theme.sideMargin)
            }

            Button("Use this tuning") {
                onUse(Tuning.custom(notes))
                dismiss()
            }
            .buttonStyle(PillButtonStyle(kind: .accent))
            .padding(.horizontal, Theme.sideMargin)
            .padding(.bottom, 12)
        }
        .background(Theme.card)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func stringRow(_ i: Int) -> some View {
        let stringNumber = notes.count - i
        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("String \(stringNumber)")
                    .font(.brandHeadline)
                    .foregroundStyle(Theme.text)
                Spacer()
                stepButton("minus", label: "Lower string \(stringNumber)", enabled: notes[i].midi > Self.range.lowerBound) {
                    notes[i] = Note(midi: notes[i].midi - 1)
                }
                Text(notes[i].nameWithOctave)
                    .font(.brandHeadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 56)
                    .accessibilityLabel("String \(stringNumber) tuned to \(notes[i].nameWithOctave)")
                stepButton("plus", label: "Raise string \(stringNumber)", enabled: notes[i].midi < Self.range.upperBound) {
                    notes[i] = Note(midi: notes[i].midi + 1)
                }
            }
            .frame(minHeight: 72)
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }

    private func stepButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: Theme.minTouch, height: Theme.minTouch)
                .background(Theme.background, in: Circle())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}
