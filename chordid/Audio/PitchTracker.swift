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
    private var window: [Float] = []
    private var pending: [Float] = []
    private var windowSize = 4096
    private var hopSize = 1024
    private(set) var isRunning = false

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TrackerError.noInput }

        let size = PitchDetector.windowSize(for: format.sampleRate)
        queue.sync {
            detector = PitchDetector(sampleRate: format.sampleRate)
            windowSize = size
            hopSize = size / 4
            window.removeAll(keepingCapacity: true)
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
            self?.window.removeAll()
            self?.pending.removeAll()
        }
    }

    /// Slides the analysis window forward one hop at a time, whatever buffer size iOS delivers.
    private func consume(_ samples: [Float]) {
        guard let detector else { return }
        pending.append(contentsOf: samples)
        while pending.count >= hopSize {
            window.append(contentsOf: pending.prefix(hopSize))
            pending.removeFirst(hopSize)
            if window.count > windowSize { window.removeFirst(window.count - windowSize) }
            if window.count == windowSize {
                onReading?(detector.analyze(window))
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
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
