import SwiftData
import SwiftUI

/// Saved chords, newest first, with search (mockups 4 and 5).
struct LibraryView: View {
    @Query(sort: \SavedChord.createdAt, order: .reverse) private var chords: [SavedChord]
    @Binding var path: [PersistentIdentifier]
    var player: GuitarPlayer
    @State private var search = ""

    private var filtered: [SavedChord] { chords.filter { $0.matches(search) } }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                if chords.isEmpty {
                    LibraryEmptyView()
                } else {
                    list
                }
            }
            // The floating bar's inset doesn't reach inside a NavigationStack, so reserve its space here.
            .safeAreaPadding(.bottom, BottomBar.reservedHeight)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let chord = chords.first(where: { $0.persistentModelID == id }) {
                    SavedChordView(chord: chord, player: player)
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Library")
                        .font(.brandLargeTitle)
                        .tracking(-1.2)
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(chords.count == 1 ? "1 chord" : "\(chords.count) chords")
                        .font(.brandBody)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 8)

                SearchField(text: $search)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(Theme.tertiaryText)
                        Text("No chords match “\(search)”")
                            .font(.brandHeadline)
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                        Text("Try a chord name like G, Am7 or Dsus4, or a tuning.")
                            .font(.brandSubheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(filtered) { chord in
                        NavigationLink(value: chord.persistentModelID) {
                            LibraryRow(chord: chord)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Theme.sideMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            TextField("Search chords", text: $text)
                .font(.brandBody)
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: Theme.minTouch, height: Theme.minTouch)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, text.isEmpty ? 20 : 4)
        .frame(minHeight: 52)
        .background(Theme.searchFill, in: Capsule())
    }
}

struct LibraryRow: View {
    let chord: SavedChord

    var body: some View {
        HStack(spacing: 18) {
            MiniChordDiagram(shape: chord.shape)
                .frame(width: 42, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(chord.name)
                    .font(.brandHeadline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(chord.summary)
                    .font(.brandBody)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minHeight: 76)
        .card()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chord.name), \(chord.summary.replacingOccurrences(of: "·", with: ","))")
        .accessibilityAddTraits(.isButton)
    }
}

/// Small chord box: nut (or starting fret number) and dots, as in the library list.
struct MiniChordDiagram: View {
    let shape: ChordShape

    var body: some View {
        Canvas { context, size in
            let strings = shape.frets.count
            let fretted = shape.frets.compactMap { $0 }.filter { $0 > 0 }
            let base = (fretted.max() ?? 0) <= 4 ? 1 : (fretted.min() ?? 1)
            let rows = 4
            let numberSpace: CGFloat = base > 1 ? 9 : 0
            // Inset by the dot radius so dots on the outer strings aren't clipped.
            let left = numberSpace + 4.5, right = size.width - 4.5
            let top: CGFloat = 4, bottom = size.height - 1
            let dx = (right - left) / CGFloat(strings - 1)
            let dy = (bottom - top) / CGFloat(rows)

            for s in 0..<strings {
                var p = Path()
                p.move(to: CGPoint(x: left + CGFloat(s) * dx, y: top))
                p.addLine(to: CGPoint(x: left + CGFloat(s) * dx, y: bottom))
                context.stroke(p, with: .color(Theme.fretLine), lineWidth: 1)
            }
            for r in 1...rows {
                var p = Path()
                p.move(to: CGPoint(x: left, y: top + CGFloat(r) * dy))
                p.addLine(to: CGPoint(x: right, y: top + CGFloat(r) * dy))
                context.stroke(p, with: .color(Theme.fretLine), lineWidth: 1)
            }
            if base == 1 {
                context.fill(Path(CGRect(x: left - 1, y: top - 2, width: right - left + 2, height: 2.5)), with: .color(Theme.text))
            } else {
                context.draw(Text("\(base)").font(BrandFont.font(9, .bold)).foregroundStyle(Theme.secondaryText),
                             at: CGPoint(x: numberSpace / 2, y: top + dy / 2))
            }
            let r: CGFloat = 3.6
            for (s, fret) in shape.frets.enumerated() {
                guard let fret, fret > 0, fret - base < rows else { continue }
                let c = CGPoint(x: left + CGFloat(s) * dx, y: top + (CGFloat(fret - base) + 0.5) * dy)
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.accent))
            }
        }
        .accessibilityHidden(true)
    }
}

/// "No chords saved yet" with the illustration and a pointer to the mic button (mockup 5).
struct LibraryEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(.brandLargeTitle)
                .tracking(-1.2)
                .foregroundStyle(Theme.text)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            VStack(spacing: 14) {
                EmptyIllustration()
                    .frame(width: 200, height: 170)
                    .padding(.bottom, 28)
                Text("No chords saved yet")
                    .font(BrandFont.font(24, .extraBold, relativeTo: .title2))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.text)
                Text("Work out a chord and save it. It will be here ready to strum back.")
                    .font(.brandBody)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            Spacer()
            MicTooltip(text: "Tap the mic and play each string, or tap the frets yourself.")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 4)
        }
        .padding(.horizontal, Theme.sideMargin)
    }
}

private struct EmptyIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.searchFill)
                .frame(width: 112, height: 120)
                .rotationEffect(.degrees(8))
                .offset(x: 34, y: 2)
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                Canvas { context, size in
                    let left: CGFloat = 26, right = size.width - 26, top: CGFloat = 32, bottom = size.height - 22
                    for s in 0..<5 {
                        let x = left + CGFloat(s) * (right - left) / 4
                        var p = Path(); p.move(to: CGPoint(x: x, y: top)); p.addLine(to: CGPoint(x: x, y: bottom))
                        context.stroke(p, with: .color(Theme.fretLine), lineWidth: 1.5)
                    }
                    for r in 1...4 {
                        let y = top + CGFloat(r) * (bottom - top) / 4.4
                        var p = Path(); p.move(to: CGPoint(x: left, y: y)); p.addLine(to: CGPoint(x: right, y: y))
                        context.stroke(p, with: .color(Theme.fretLine), lineWidth: 1.5)
                    }
                    context.fill(Path(CGRect(x: left - 2, y: top - 3, width: right - left + 4, height: 4)), with: .color(Theme.text))
                }
                Text("?")
                    .font(BrandFont.font(64, .extraBold))
                    .foregroundStyle(Theme.text)
                    .offset(y: -10)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 15, height: 15)
                    .offset(y: 34)
            }
            .frame(width: 120, height: 136)
            .rotationEffect(.degrees(-5))
            .offset(x: -10)
            Circle()
                .fill(Theme.accentSoft)
                .frame(width: 10, height: 10)
                .offset(x: -78, y: -62)
            Image(systemName: "sparkle")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.accent)
                .offset(x: 72, y: 66)
        }
        .accessibilityHidden(true)
    }
}

/// Dark speech bubble pointing down at the mic button.
private struct MicTooltip: View {
    let text: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(text)
                .font(.brandBodySemibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: 228, alignment: .leading)
                .background(Theme.text, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Triangle()
                .fill(Theme.text)
                .frame(width: 16, height: 9)
                .padding(.trailing, 24)
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }
}

/// One saved chord: big diagram, Strum, and Rename / Delete (mockup 6).
struct SavedChordView: View {
    @Bindable var chord: SavedChord
    var player: GuitarPlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CircleIconButton(systemName: "chevron.left", style: .card, label: "Back") {
                    player.stop()
                    dismiss()
                }
                Spacer()
                Menu {
                    Button {
                        newName = chord.name
                        renaming = true
                    } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) {
                        Haptics.warning()
                        confirmDelete = true
                    } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: Theme.minTouch, height: Theme.minTouch)
                        .background(Theme.card, in: Circle())
                }
                .accessibilityLabel("More")
            }
            .padding(.top, 8)

            Text(chord.name)
                .font(.brandChordName)
                .tracking(-1.5)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.brandBodySemibold)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 4)

            FretboardView(
                tuning: chord.soundingTuning,
                shape: chord.shape,
                capo: chord.capo,
                stringLabels: chord.tuning.stringNames,
                highlightedStrings: player.activeStrings,
                vibratingSince: player.vibratingSince,
                noteName: { string in
                    guard let note = chord.shape.notesByString(in: chord.soundingTuning)[string] else { return nil }
                    return chord.analysis.best?.name(for: note.pitchClass) ?? note.pitchClass.defaultName
                }
            )
            .frame(minHeight: 240, maxHeight: 400)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .card()
            .padding(.top, 20)

            Spacer(minLength: 16)

            Button {
                player.strum(shape: chord.shape, tuning: chord.soundingTuning)
            } label: {
                Label("Strum", systemImage: "play.fill")
                    .labelStyle(SpacedLabelStyle())
                    .font(BrandFont.font(20, .bold, relativeTo: .title3))
            }
            .buttonStyle(PillButtonStyle(kind: .accent))
            .shadow(color: Theme.accent.opacity(0.3), radius: 16, y: 6)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, Theme.sideMargin)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { player.stop() }
        .alert("Rename chord", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    chord.name = trimmed
                    try? context.save()
                }
            }
        }
        .confirmationDialog("Delete “\(chord.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                player.stop()
                context.delete(chord)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("This removes it from your library.")
        }
    }

    /// "Standard tuning · G · B · D" (plus capo when there is one).
    private var subtitle: String {
        var parts = [chord.tuningName + " tuning"]
        if chord.capo > 0 { parts.append("Capo \(chord.capo)") }
        if let tones = chord.analysis.best?.toneNames { parts += tones }
        return parts.joined(separator: " · ")
    }
}
