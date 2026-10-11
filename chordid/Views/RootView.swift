import SwiftUI

enum AppTab: Hashable {
    case chordID, library
}

/// App shell: the current tab plus the floating bottom bar.
struct RootView: View {
    @State private var model = ChordIDModel()
    @State private var listener = ListeningController()
    @State private var player = GuitarPlayer()
    @State private var tab: AppTab = .chordID
    @State private var showDebug = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch tab {
            case .chordID: ChordIDView(model: model, listener: listener, player: player)
            case .library: LibraryPlaceholderView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar(tab: $tab, isListening: listener.isListening, micAction: {
                tab = .chordID
                // Playback and the microphone never run at the same time.
                player.stop()
                listener.toggle(model: model)
            }, micLongPress: {
                // Hidden: hold the mic button for a second to open the pitch debug view.
                listener.stop()
                player.stop()
                showDebug = true
            })
        }
        .onChange(of: tab) { _, newTab in
            if newTab != .chordID { listener.stop() }
        }
        .sheet(isPresented: $showDebug) {
            PitchDebugView(tuning: model.soundingTuning)
        }
    }
}

/// Floating pill with two tabs, plus the round mic button.
struct BottomBar: View {
    @Binding var tab: AppTab
    var isListening = false
    var micAction: () -> Void
    var micLongPress: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                tabButton(.chordID, title: "Chord ID", icon: "square.split.2x2")
                tabButton(.library, title: "Library", icon: "bookmark")
            }
            .padding(6)
            .background(Theme.card, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 18, y: 6)

            Image(systemName: isListening ? "stop.fill" : "mic")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Theme.accent, in: Circle())
                .background {
                    // Halo while listening (animated in a later phase).
                    Circle()
                        .fill(Theme.accent.opacity(0.22))
                        .frame(width: 80, height: 80)
                        .opacity(isListening ? 1 : 0)
                }
                .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 6)
                .contentShape(Circle())
                .onTapGesture(perform: micAction)
                .onLongPressGesture(minimumDuration: 1, perform: micLongPress)
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, micAction)
            .accessibilityLabel(isListening ? "Stop listening" : "Listen")
            .accessibilityHint("Play each string, low to high, and Chord ID will place the notes")
        }
        .padding(.horizontal, Theme.sideMargin)
        .padding(.bottom, 8)
    }

    private func tabButton(_ value: AppTab, title: String, icon: String) -> some View {
        let selected = tab == value
        return Button {
            tab = value
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? icon + ".fill" : icon)
                    .font(.system(size: 19, weight: .regular))
                Text(title)
                    .font(.brandBodySemibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selected ? Theme.accentSoft : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Stand-in until the library is built.
struct LibraryPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library")
                .font(.brandLargeTitle)
                .tracking(-1.2)
                .foregroundStyle(Theme.text)
                .padding(.top, 8)
            Spacer()
            Text("Saved chords will appear here.")
                .font(.brandBody)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.horizontal, Theme.sideMargin)
    }
}

#Preview {
    RootView()
}
