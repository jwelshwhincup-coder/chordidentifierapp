import AVFoundation
import Foundation
import Observation

/// Plays strums through the speaker and reports which strings are sounding,
/// so the fretboard can light them up in time with the audio.
@Observable
final class GuitarPlayer {
    /// Strings currently lighting up (0 = lowest).
    private(set) var activeStrings: Set<Int> = []
    private(set) var isAvailable = true

    /// The strum the user picked from the previews.
    var style: StrumStyle = .gentle

    @ObservationIgnored private let library = GuitarSampleLibrary.bundled()
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    @ObservationIgnored private var highlightTask: Task<Void, Never>?
    @ObservationIgnored private var strumID = 0
    /// How long a string stays lit after it sounds.
    private let highlightSeconds = 0.35

    init() {
        isAvailable = library != nil
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func strum(shape: ChordShape, tuning: Tuning) {
        guard let library, !shape.isEmpty else { return }
        strumID += 1
        let id = strumID
        let style = style

        // Plan and render off the main thread; a strum is only a few seconds of audio.
        Task.detached(priority: .userInitiated) { [format] in
            var rng = SystemRandomNumberGenerator()
            let events = StrumPlanner(source: library).plan(shape: shape, tuning: tuning, style: style, rng: &rng)
            library.preload(events.map(\.sample))
            let rendered = StrumRenderer.render(events, source: library)
            let buffer = Self.makeBuffer(rendered, format: format)
            await MainActor.run { [weak self] in
                guard let self, id == self.strumID, let buffer else { return }
                self.play(buffer, events: rendered.events)
            }
        }
    }

    func stop() {
        strumID += 1
        highlightTask?.cancel()
        activeStrings = []
        if engine.isRunning {
            node.stop()
            engine.stop()
        }
    }

    // MARK: - Playback

    private func play(_ buffer: AVAudioPCMBuffer, events: [StrumEvent]) {
        do {
            // .playback: Strum is the only sound the app makes, and it plays even with the
            // silent switch on because the user asked for it. Other audio (music) keeps playing.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
        } catch {
            return
        }
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
        highlight(events, latency: AVAudioSession.sharedInstance().outputLatency)
    }

    /// Light each string as its note starts.
    private func highlight(_ events: [StrumEvent], latency: TimeInterval) {
        highlightTask?.cancel()
        activeStrings = []
        let hold = highlightSeconds
        highlightTask = Task { [weak self] in
            let start = ContinuousClock.now + .milliseconds(Int(latency * 1000))
            // Every start and end time, in order.
            var changes: [(time: Double, string: Int, on: Bool)] = []
            for e in events {
                changes.append((e.time, e.string, true))
                changes.append((e.time + hold, e.string, false))
            }
            changes.sort { $0.time < $1.time }
            for change in changes {
                try? await Task.sleep(until: start + .milliseconds(Int(change.time * 1000)), clock: .continuous)
                guard !Task.isCancelled, let self else { return }
                if change.on { self.activeStrings.insert(change.string) } else { self.activeStrings.remove(change.string) }
            }
        }
    }

    nonisolated private static func makeBuffer(_ r: RenderedStrum, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(r.left.count)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(r.left.count)
        r.left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: r.left.count) }
        r.right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: r.right.count) }
        return buffer
    }
}
