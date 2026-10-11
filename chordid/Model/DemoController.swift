import Foundation
import Observation
import SwiftUI
import UIKit

/// Something on the real Chord ID screen the demo can point at.
enum DemoTarget: Hashable {
    case fret(string: Int, fret: Int)
    case marker(Int)
    case markerRow
    case result
    case strum
    case mic
}

/// A scripted input the demo performs on the real UI.
enum DemoAction: Equatable {
    case tapFret(string: Int, fret: Int)
    case tapMarker(Int)
    /// Silent strum: strings light and vibrate, no sound.
    case strum
    /// Show the listening screen with scripted state (no microphone).
    case listeningPreview

    /// Where the tap ring appears before the UI reacts.
    var target: DemoTarget {
        switch self {
        case .tapFret(let s, let f): .fret(string: s, fret: f)
        case .tapMarker(let s): .marker(s)
        case .strum: .strum
        case .listeningPreview: .mic
        }
    }
}

struct DemoStep: Equatable {
    enum Spotlight: Equatable { case circle(diameter: CGFloat), roundedRect(padding: CGFloat, radius: CGFloat) }
    enum Side: Equatable { case above, below }

    let title: String
    let body: String
    let target: DemoTarget
    let spotlight: Spotlight
    let bubbleSide: Side
    let actions: [DemoAction]
}

/// Runs the four-step first-launch demo over the real Chord ID screen.
///
/// It drives the real model with scripted taps (building C major, x 3 2 0 1 0),
/// shows the listening screen without touching the microphone, and when it ends
/// or is skipped puts the fretboard, tuning and capo back exactly as they were.
@Observable
final class DemoController {
    static let seenKey = "hasSeenDemo"
    /// Time to read a step after its animation before moving on by itself.
    static let readingSeconds = 4.0

    static let steps: [DemoStep] = [
        DemoStep(title: "Tap any fret to place a finger.",
                 body: "Tap it again to take it off.",
                 target: .fret(string: 1, fret: 3),
                 spotlight: .circle(diameter: 92), bubbleSide: .below,
                 actions: [.tapFret(string: 1, fret: 3), .tapFret(string: 2, fret: 2), .tapFret(string: 4, fret: 1)]),
        DemoStep(title: "Tap above a string to switch it.",
                 body: "A circle means it rings open. A cross means it's muted or not played.",
                 target: .markerRow,
                 spotlight: .roundedRect(padding: 8, radius: 28), bubbleSide: .below,
                 actions: [.tapMarker(3), .tapMarker(5)]),
        DemoStep(title: "The chord name appears straight away.",
                 body: "Strum to hear it. Save to keep it.",
                 target: .result,
                 spotlight: .roundedRect(padding: 14, radius: 30), bubbleSide: .above,
                 actions: [.strum]),
        DemoStep(title: "Or tap the mic and play each string.",
                 body: "Go low to high. Tap Skip string for any you don't play.",
                 target: .mic,
                 spotlight: .circle(diameter: 108), bubbleSide: .above,
                 actions: [.listeningPreview]),
    ]

    private(set) var isRunning = false
    private(set) var stepIndex = 0
    /// Where a tap ring is pulsing right now.
    private(set) var tapRing: DemoTarget?
    /// The current step's scripted actions have all happened.
    private(set) var stepSettled = false

    var step: DemoStep { Self.steps[stepIndex] }
    var isLastStep: Bool { stepIndex == Self.steps.count - 1 }
    var hasSeen: Bool { defaults.bool(forKey: Self.seenKey) }

    /// Called after "Start playing" closes the demo.
    @ObservationIgnored var onStartPlaying: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var model: ChordIDModel?
    @ObservationIgnored private var listener: ListeningController?
    @ObservationIgnored private var player: GuitarPlayer?
    @ObservationIgnored private var snapshot: (tuning: Tuning, capo: Int, shape: ChordShape)?
    @ObservationIgnored private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    @ObservationIgnored private var voiceOver: Bool { UIAccessibility.isVoiceOverRunning }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Controls

    func start(model: ChordIDModel, listener: ListeningController, player: GuitarPlayer) {
        guard !isRunning else { return }
        self.model = model
        self.listener = listener
        self.player = player
        listener.stop()
        player.stop()
        // The demo plays in Standard tuning with no capo so the C major names correctly.
        snapshot = (model.tuning, model.capo, model.shape)
        if model.tuning != .standard { model.tuning = .standard }
        if model.capo != 0 { model.setCapo(0) }
        model.clear()
        isRunning = true
        run(step: 0)
    }

    /// A tap anywhere: finish the current step at once if it's still animating, then move on.
    func advance() {
        guard isRunning else { return }
        if isLastStep {
            finish(startPlaying: false)
            return
        }
        task?.cancel()
        applyFinalState(through: stepIndex)
        run(step: stepIndex + 1)
    }

    func skip() { finish(startPlaying: false) }

    func startPlaying() { finish(startPlaying: true) }

    // MARK: - Steps

    private func run(step index: Int) {
        task?.cancel()
        tapRing = nil
        stepSettled = false
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.85)) {
            stepIndex = index
        }
        Haptics.fretTap()
        let actions = Self.steps[index].actions
        task = Task { [weak self] in
            // Let the spotlight slide and the bubble spring in first.
            try? await Task.sleep(for: .milliseconds(self?.reduceMotion == true ? 250 : 650))
            for action in actions {
                guard let self, !Task.isCancelled else { return }
                await self.perform(action)
            }
            guard let self, !Task.isCancelled else { return }
            self.stepSettled = true
            // VoiceOver users move on themselves; the last step waits for a choice.
            guard !self.voiceOver, !self.isLastStep else { return }
            try? await Task.sleep(for: .seconds(Self.readingSeconds))
            guard !Task.isCancelled else { return }
            self.advance()
        }
    }

    private func perform(_ action: DemoAction) async {
        // The tap ring pulses before the UI reacts.
        withAnimation(.easeOut(duration: 0.2)) { tapRing = action.target }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 600))
        guard !Task.isCancelled else { return }
        apply(action)
        withAnimation(.easeOut(duration: 0.2)) { tapRing = nil }
        try? await Task.sleep(for: .milliseconds(action == .strum ? 900 : 350))
    }

    private func apply(_ action: DemoAction) {
        guard let model else { return }
        switch action {
        case .tapFret(let s, let f):
            if model.shape.frets[s] != f { model.tapFret(string: s, fret: f) }
        case .tapMarker(let s):
            if model.shape.frets[s] != 0 { model.tapMarker(string: s) }
        case .strum:
            player?.previewStrum(shape: model.shape, tuning: model.soundingTuning)
        case .listeningPreview:
            listener?.beginPreview(model: model)
        }
    }

    /// Jump straight to how the screen looks once steps 0…`index` have played.
    private func applyFinalState(through index: Int) {
        guard let model else { return }
        tapRing = nil
        player?.stop()
        model.shape = Self.shape(afterStep: index)
        if index >= 3 { listener?.beginPreview(model: model) }
    }

    /// The fretboard after the scripted taps of steps 0…`index`.
    static func shape(afterStep index: Int) -> ChordShape {
        var shape = ChordShape.empty()
        for step in steps.prefix(index + 1) {
            for action in step.actions {
                switch action {
                case .tapFret(let s, let f): shape.frets[s] = f
                case .tapMarker(let s): shape.frets[s] = 0
                case .strum: break
                case .listeningPreview: shape = .empty()
                }
            }
        }
        return shape
    }

    private func finish(startPlaying: Bool) {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        tapRing = nil
        listener?.endPreview()
        player?.stop()
        if let model, let snapshot {
            if model.tuning != snapshot.tuning { model.tuning = snapshot.tuning }
            if model.capo != snapshot.capo { model.setCapo(snapshot.capo) }
            model.shape = snapshot.shape
        }
        snapshot = nil
        defaults.set(true, forKey: Self.seenKey)
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.3)) { isRunning = false }
        if startPlaying { onStartPlaying?() }
    }
}

// MARK: - Finding targets on screen

struct DemoAnchorKey: PreferenceKey {
    static let defaultValue: [DemoTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [DemoTarget: Anchor<CGRect>], nextValue: () -> [DemoTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct DemoAnchorsEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ReplayDemoKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Only the main Chord ID screen publishes demo targets.
    var demoAnchorsEnabled: Bool {
        get { self[DemoAnchorsEnabledKey.self] }
        set { self[DemoAnchorsEnabledKey.self] = newValue }
    }

    /// Starts the demo again (Settings → Replay demo).
    var replayDemo: () -> Void {
        get { self[ReplayDemoKey.self] }
        set { self[ReplayDemoKey.self] = newValue }
    }
}

private struct DemoTargetModifier: ViewModifier {
    let target: DemoTarget
    @Environment(\.demoAnchorsEnabled) private var enabled

    func body(content: Content) -> some View {
        if enabled {
            content.anchorPreference(key: DemoAnchorKey.self, value: .bounds) { [target: $0] }
        } else {
            content
        }
    }
}

extension View {
    /// Marks this view as something the first-launch demo can spotlight.
    func demoTarget(_ target: DemoTarget) -> some View {
        modifier(DemoTargetModifier(target: target))
    }
}
