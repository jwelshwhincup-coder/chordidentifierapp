import AVFoundation
import Foundation

/// Reads the bundled note recordings (s<string>_f<fret>_<layer>.m4a) and the
/// per-note tuning table, decoding each note the first time it's needed.
nonisolated final class GuitarSampleLibrary: SampleSource, @unchecked Sendable {
    let sampleRate: Double = 44_100
    private let locate: (String) -> URL?
    private let cents: [String: Double]
    private var cache: [SampleKey: StereoSample] = [:]
    private let lock = NSLock()

    /// Samples in the app bundle.
    static func bundled() -> GuitarSampleLibrary? {
        let bundle = Bundle.main
        func find(_ name: String, _ ext: String) -> URL? {
            bundle.url(forResource: name, withExtension: ext)
                ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "GuitarSamples")
        }
        guard let table = find("samples", "json") else { return nil }
        return GuitarSampleLibrary(table: table) { find($0, "m4a") }
    }

    /// Samples in a folder (used by the preview renderer on the Mac).
    convenience init?(directory: URL) {
        self.init(table: directory.appendingPathComponent("samples.json")) { name in
            let url = directory.appendingPathComponent(name + ".m4a")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    private init?(table: URL, locate: @escaping (String) -> URL?) {
        struct Table: Decodable { let tuningCents: [String: Double] }
        guard let data = try? Data(contentsOf: table),
              let decoded = try? JSONDecoder().decode(Table.self, from: data) else { return nil }
        self.cents = decoded.tuningCents
        self.locate = locate
    }

    func has(_ key: SampleKey) -> Bool { cents[key.name] != nil }

    func tuningCents(_ key: SampleKey) -> Double { cents[key.name] ?? 0 }

    func sample(_ key: SampleKey) -> StereoSample? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        guard has(key), let url = locate(key.name), var decoded = Self.decode(url) else { return nil }
        Self.normalize(&decoded, layer: key.layer)
        // Each decoded note is ~1.4 MB; keep memory bounded.
        if cache.count >= 48 { cache.removeAll(keepingCapacity: true) }
        cache[key] = decoded
        return decoded
    }

    /// Decode the notes a strum will need before it's played.
    func preload(_ keys: [SampleKey]) {
        for key in keys { _ = sample(key) }
    }

    /// Level of the first half-second of every note after loading. The raw recordings
    /// vary by ~20 dB between loudness takes and strings; this evens them out.
    static let targetRMSdB: Double = -24
    /// Kept difference between takes, so soft strums still sound softer.
    static let layerOffsetdB: [SampleLayer: Double] = [.pp: -5, .mf: 0, .ff: 3]

    private static func normalize(_ s: inout StereoSample, layer: SampleLayer) {
        let n = min(s.count, Int(s.sampleRate * 0.5))
        guard n > 0 else { return }
        var sum: Double = 0
        for i in 0..<n { sum += Double(s.left[i] * s.left[i] + s.right[i] * s.right[i]) / 2 }
        let rmsDB = 10 * log10(max(sum / Double(n), 1e-12))
        let gain = Float(pow(10, (targetRMSdB + (layerOffsetdB[layer] ?? 0) - rmsDB) / 20))
        for i in 0..<s.count { s.left[i] *= gain; s.right[i] *= gain }
    }

    private static func decode(_ url: URL) -> StereoSample? {
        guard let file = try? AVAudioFile(forReading: url),
              let format = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData else { return nil }
        let n = Int(buffer.frameLength)
        let left = Array(UnsafeBufferPointer(start: channels[0], count: n))
        let right = file.processingFormat.channelCount > 1 ? Array(UnsafeBufferPointer(start: channels[1], count: n)) : left
        return StereoSample(left: left, right: right, sampleRate: format.sampleRate)
    }
}
