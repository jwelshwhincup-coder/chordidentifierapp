import AVFoundation
import Foundation

/// Microphone → pitch readings. Runs analysis off the main thread and
/// delivers each `PitchReading` through `onReading` (on a background queue).
nonisolated final class PitchTracker: @unchecked Sendable {
    enum TrackerError: Error { case noInput }

    /// Called for every analysis frame, on the tracker's own queue.
    var onReading: (@Sendable (PitchReading) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "chordid.pitch", qos: .userInitiated)
    // Only touched on `queue`.
    private var detector: PitchDetector?
    private var history: [Float] = []
    private var pending: [Float] = []
    private var sampleRate: Double = 48_000
    private var windowSize = 4096
    /// ~21 ms between analyses at 48 kHz.
    private let hopSize = 1024
    private let maxWindow = 8192
    private var expected: ClosedRange<Double>?
    private(set) var isRunning = false

    /// The frequencies the string being listened for can produce (nil = anything).
    /// Also sizes the analysis window to suit that string.
    func setExpectedRange(_ range: ClosedRange<Double>?) {
        queue.async { [self] in
            expected = range
            windowSize = PitchDetector.windowSize(for: sampleRate, lowestFrequency: range?.lowerBound ?? 60)
        }
    }

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        // Belt and braces: voice processing would add gain control and noise suppression.
        if input.isVoiceProcessingEnabled { try? input.setVoiceProcessingEnabled(false) }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TrackerError.noInput }

        queue.sync {
            sampleRate = format.sampleRate
            detector = PitchDetector(sampleRate: format.sampleRate)
            windowSize = PitchDetector.windowSize(for: format.sampleRate, lowestFrequency: expected?.lowerBound ?? 60)
            history.removeAll(keepingCapacity: true)
            pending.removeAll(keepingCapacity: true)
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            self.queue.async { self.consume(samples) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        queue.async { [weak self] in
            self?.history.removeAll()
            self?.pending.removeAll()
        }
    }

    /// Slides forward one hop at a time, whatever buffer size iOS delivers, and
    /// analyses the most recent `windowSize` samples.
    private func consume(_ samples: [Float]) {
        guard let detector else { return }
        pending.append(contentsOf: samples)
        while pending.count >= hopSize {
            history.append(contentsOf: pending.prefix(hopSize))
            pending.removeFirst(hopSize)
            if history.count > maxWindow { history.removeFirst(history.count - maxWindow) }
            if history.count >= windowSize {
                onReading?(detector.analyze(Array(history.suffix(windowSize)), expected: expected))
            }
        }
    }
}

/// Microphone permission and audio session setup.
enum AudioSessionManager {
    enum Permission { case undetermined, granted, denied }

    static var micPermission: Permission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }

    static func requestMicPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Recording with the signal untouched: "measurement" mode turns off the
    /// automatic gain and noise processing that would smear a guitar note.
    static func activateForListening() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        // Most iPhones don't allow this; where they do, use the full input gain.
        if session.isInputGainSettable { try? session.setInputGain(1.0) }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
