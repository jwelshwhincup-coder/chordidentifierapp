import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case chordID, library
}

/// App shell: the current tab plus the floating bottom bar.
struct RootView: View {
    @State private var model = ChordIDModel()
    @State private var listener = ListeningController()
    @State private var player = GuitarPlayer()
    @State private var demo = DemoController()
    @State private var store = ProStore()
    @State private var tab: AppTab = .chordID
    @State private var showDebug = false
    @State private var libraryPath: [PersistentIdentifier] = []
    @State private var sheetShown = false
    @Query private var saved: [SavedChord]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The logo screen for this launch; nil once it has faded away.
    @State private var launchStyle: LaunchStyle? = LaunchStyle.choose(
        hasLaunchedBefore: UserDefaults.standard.bool(forKey: LaunchStyle.hasLaunchedKey),
        reduceMotion: UIAccessibility.isReduceMotionEnabled)

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // Tabs slide: Chord ID lives to the left, Library to the right.
            switch tab {
            case .chordID:
                ChordIDView(model: model, listener: listener, player: player, store: store, sheetShown: $sheetShown,
                            demoRunning: demo.isRunning)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            case .library:
                LibraryView(path: $libraryPath, player: player)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The saved-chord screen hides the bar.
            if tab != .library || libraryPath.isEmpty {
            BottomBar(tab: $tab, isListening: listener.isListening && !listener.isPreview,
                      highlightMic: tab == .library && saved.isEmpty, micAction: {
                withAnimation(tabAnimation) { tab = .chordID }
                // Playback and the microphone never run at the same time.
                player.stop()
                listener.toggle(model: model)
            }, micLongPress: {
                // Hidden: hold the mic button for a second to open the pitch debug view.
                listener.stop()
                player.stop()
                showDebug = true
            })
            .environment(\.demoAnchorsEnabled, true)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: libraryPath.isEmpty)
        .overlayPreferenceValue(DemoAnchorKey.self) { anchors in
            if demo.isRunning {
                GeometryReader { proxy in
                    DemoOverlay(demo: demo, rects: anchors.mapValues { proxy[$0] })
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        // A sheet scales the screen behind it back slightly.
        .mask {
            // Masking with a full-screen shape keeps the edge-to-edge background visible.
            RoundedRectangle(cornerRadius: sheetShown && !reduceMotion ? 38 : 0, style: .continuous)
                .ignoresSafeArea()
        }
        .scaleEffect(sheetShown && !reduceMotion ? 0.93 : 1)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sheetShown)
        .background(Color.black.ignoresSafeArea())
        .environment(\.tabAnimation, tabAnimation)
        .overlay {
            if let launchStyle {
                LogoScreen(style: launchStyle, onDotLanded: { Haptics.fretTap() }) {
                    UserDefaults.standard.set(true, forKey: LaunchStyle.hasLaunchedKey)
                    withAnimation(.easeInOut(duration: launchStyle.fadeSeconds)) { self.launchStyle = nil }
                    // The demo runs once, straight after the logo screen.
                    if !demo.hasSeen { startDemo() }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: tab) { _, newTab in
            if newTab != .chordID { listener.stop() }
            player.stop()
        }
        .task { store.start() }
        .sheet(isPresented: $showDebug) {
            PitchDebugView(tuning: model.soundingTuning)
        }
        .environment(\.replayDemo) {
            // Wait for the Settings sheet to finish closing.
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                startDemo()
            }
        }
    }

    private func startDemo() {
        if tab != .chordID { tab = .chordID }
        demo.onStartPlaying = {
            listener.toggle(model: model)
        }
        demo.start(model: model, listener: listener, player: player)
    }

    private var tabAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.88)
    }
}

private struct TabAnimationKey: EnvironmentKey {
    static let defaultValue: Animation = .default
}

extension EnvironmentValues {
    var tabAnimation: Animation {
        get { self[TabAnimationKey.self] }
        set { self[TabAnimationKey.self] = newValue }
    }
}

/// Floating pill with two tabs, plus the round mic button.
struct BottomBar: View {
    /// Height of the bar including its bottom padding.
    static let reservedHeight: CGFloat = 76

    @Binding var tab: AppTab
    var isListening = false
    /// Halo around the mic, used by the empty library to point at it.
    var highlightMic = false
    var micAction: () -> Void
    var micLongPress: () -> Void = {}
    @Environment(\.tabAnimation) private var tabAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .demoTarget(.mic)
                // The icon morphs between mic and stop.
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: 64, height: 64)
                .background(Theme.accent, in: Circle())
                .background {
                    ZStack {
                        Circle()
                            .fill(Theme.accent.opacity(0.22))
                            .frame(width: 80, height: 80)
                            .opacity(isListening || highlightMic ? 1 : 0)
                        if isListening && !reduceMotion {
                            ExpandingRing()
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isListening)
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
            withAnimation(tabAnimation) { tab = value }
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

/// A ring that keeps expanding out from the mic button and fading while listening.
private struct ExpandingRing: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Theme.accent, lineWidth: 2)
            .frame(width: 64, height: 64)
            .scaleEffect(expanded ? 1.75 : 1)
            .opacity(expanded ? 0 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { expanded = true }
            }
    }
}

#Preview {
    RootView()
        .modelContainer(for: SavedChord.self, inMemory: true)
}
