import AVFoundation
import Foundation
import Observation

/// Drives "tap the mic and play each string": permission, the microphone,
/// note confirmation, and placing each note on the fretboard.
@Observable
final class ListeningController {
    enum Phase: Equatable {
        case idle
        case listening
        /// Microphone permission was refused; show how to turn it on.
        case denied
        /// The microphone couldn't start (e.g. in use by a call).
        case failed
    }

    private(set) var phase: Phase = .idle
    /// Showing the listening screen for the demo, with no microphone running.
    private(set) var isPreview = false
    private(set) var session: ListeningSession?
    /// A problem with the last note heard, e.g. too low for the string.
    private(set) var problem: String?
    /// Live input level 0…1, for the meter (0 = room level, 1 = 40 dB above it).
    private(set) var level: Double = 0

    @ObservationIgnored private let tracker = PitchTracker()
    @ObservationIgnored private var stabilizer = NoteStabilizer()
    @ObservationIgnored private weak var model: ChordIDModel?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    var isListening: Bool { phase == .listening }

    init() {
        tracker.onReading = { [weak self] reading in
            guard let self else { return }
            Task { @MainActor in self.handle(reading) }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.stop() }
        }
    }

    // MARK: - Controls

    func toggle(model: ChordIDModel) {
        if isListening { stop() } else { Task { await start(model: model) } }
    }

    func start(model: ChordIDModel) async {
        self.model = model
        problem = nil

        var permission = AudioSessionManager.micPermission
        if permission == .undetermined {
            permission = await AudioSessionManager.requestMicPermission() ? .granted : .denied
        }
        guard permission == .granted else {
            phase = .denied
            return
        }

        do {
            try AudioSessionManager.activateForListening()
            stabilizer.reset()
            try tracker.start()
        } catch {
            AudioSessionManager.deactivate()
            phase = .failed
            return
        }

        model.clear()
        let newSession = ListeningSession(tuning: model.tuning, capo: model.capo)
        session = newSession
        tracker.setExpectedRange(Self.expectedRange(for: newSession))
        phase = .listening
    }

    /// The demo's listening screen: "Play the E string", without touching the
    /// microphone or asking for permission.
    func beginPreview(model: ChordIDModel) {
        stop()
        self.model = model
        model.clear()
        session = ListeningSession(tuning: model.tuning, capo: model.capo)
        problem = nil
        level = 0.3
        isPreview = true
        phase = .listening
    }

    func endPreview() {
        guard isPreview else { return }
        isPreview = false
        phase = .idle
        session = nil
        level = 0
    }

    func stop() {
        if isPreview { endPreview(); return }
        // Nothing to tear down unless the mic is on (avoids touching the audio session needlessly).
        guard phase == .listening || tracker.isRunning else { return }
        tracker.stop()
        AudioSessionManager.deactivate()
        if phase == .listening { phase = .idle }
        session = nil
        level = 0
        tracker.setExpectedRange(nil)
    }

    func skipString() {
        guard var session else { return }
        session.skip()
        problem = nil
        apply(session)
    }

    func startOver() {
        guard var session else { return }
        session.startOver()
        problem = nil
        stabilizer.reset()
        apply(session)
    }

    /// Leave the denied / failed message.
    func dismissProblem() {
        if phase == .denied || phase == .failed { phase = .idle }
    }

    // MARK: - Audio

    private func handle(_ reading: PitchReading) {
        guard phase == .listening else { return }
        level = min(max((reading.decibels - PitchReading.decibels(stabilizer.noiseFloor)) / 40, 0), 1)

        guard let note = stabilizer.process(reading), var session else { return }
        let openName = session.currentString.map { model?.soundingTuning.stringNames[$0] ?? "" } ?? ""
        switch session.hear(note) {
        case .placed:
            Haptics.noteAccepted()
            problem = nil
            apply(session)
        case .tooLow(_, let note):
            problem = "Heard \(note.nameWithOctave), which is lower than the open \(openName) string. Check your tuning and try again."
        case .tooHigh(_, let note):
            problem = "Heard \(note.nameWithOctave), which is too high for the \(openName) string. Try again."
        case .notListening:
            break
        }
    }

    /// What the string being listened for can produce: its open note (with capo,
    /// allowing a string tuned up to 1.5 semitones flat so "check your tuning" can
    /// still be shown) up to the highest fret.
    static func expectedRange(for session: ListeningSession) -> ClosedRange<Double>? {
        guard let open = session.currentOpenNote else { return nil }
        let low = open.frequency() * pow(2, -1.5 / 12)
        let high = Note(midi: open.midi + session.maxShapeFret).frequency() * pow(2, 0.5 / 12)
        return low...high
    }

    private func apply(_ updated: ListeningSession) {
        session = updated
        tracker.setExpectedRange(Self.expectedRange(for: updated))
        model?.shape = updated.shape
        if updated.isFinished { stop() }
    }
}
