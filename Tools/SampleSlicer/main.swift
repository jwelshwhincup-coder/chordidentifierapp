// Cuts the University of Iowa guitar recordings (one file = a chromatic run on one
// string) into single notes, checks each note's pitch with the app's PitchDetector,
// and writes trimmed AAC files the app bundles.
//
// Build & run (from the repo root):
//   swiftc -O -o /tmp/slicer Tools/SampleSlicer/main.swift chordid/Audio/PitchDetector.swift chordid/Model/Music.swift
//   /tmp/slicer <folder with Guitar.*.aif> chordid/Resources/GuitarSamples
import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: slicer <in dir> <out dir> [--dry-run]"); exit(1) }
let inDir = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let dryRun = args.contains("--dry-run")

/// Recorded string tags in file names → string index (0 = low E) and open note.
let strings: [(tag: String, open: Note)] = [
    ("sulE", Note("E2")!), ("sulA", Note("A2")!), ("sulD", Note("D3")!),
    ("sulG", Note("G3")!), ("sulB", Note("B3")!), ("sul_E", Note("E4")!),
]
/// Length kept per note: long enough to ring out under a strum.
let keepSeconds = 4.0
let preRollSeconds = 0.004
let fadeOutSeconds = 0.6

struct NoteSlice { let start: Int; let end: Int }

func readStereo(_ url: URL) throws -> (l: [Float], r: [Float], rate: Double) {
    let file = try AVAudioFile(forReading: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    let n = Int(buffer.frameLength)
    let l = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: n))
    let r = Array(UnsafeBufferPointer(start: buffer.floatChannelData![1], count: n))
    return (l, r, format.sampleRate)
}

/// 6th-order Butterworth high-pass (three biquads). The recordings carry low rumble
/// (room/stand thumps, mostly < 60 Hz) in the note tails; the lowest guitar note is 82 Hz.
func highPass(_ x: [Float], rate: Double, cutoff: Double = 65) -> [Float] {
    var y = x
    // Pole angles for a 6th-order Butterworth: Q values of its three sections.
    for q in [0.5176, 0.7071, 1.9319] {
        let w0 = 2 * Double.pi * cutoff / rate
        let alpha = sin(w0) / (2 * q), c = cos(w0)
        let a0 = 1 + alpha
        let b0 = (1 + c) / 2 / a0, b1 = -(1 + c) / a0, b2 = (1 + c) / 2 / a0
        let a1 = -2 * c / a0, a2 = (1 - alpha) / a0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<y.count {
            let xi = Double(y[i])
            let yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = xi; y2 = y1; y1 = yi
            y[i] = Float(yi)
        }
    }
    return y
}

/// Finds plucks: the (rumble-filtered) level jumps at least 12 dB above its
/// recent minimum. Digital-silence gaps between notes count as a minimum too.
func findOnsets(_ filtered: [Float], rate: Double, rise: Float = 4, minFraction: Float = 0.02) -> [Int] {
    let hop = Int(rate * 0.005)
    var env: [Float] = []
    var i = 0
    while i + hop <= filtered.count {
        var s: Float = 0
        for j in i..<(i + hop) { s += filtered[j] * filtered[j] }
        env.append(sqrt(s / Float(hop)))
        i += hop
    }
    let peak = env.max() ?? 0
    let lookback = 40                 // 200 ms
    let refractory = Int(0.8 / 0.005)
    var onsets: [Int] = []
    var last = -refractory
    for k in lookback..<env.count where k - last >= refractory {
        let recentMin = env[(k - lookback)..<k].min()!
        if env[k] > peak * minFraction && env[k] > max(recentMin, 1e-6) * rise {
            var start = k
            while start > 0 && env[start - 1] > recentMin * 1.5 && k - start < 8 { start -= 1 }
            onsets.append(max(0, start * hop - Int(rate * 0.002)))
            last = k
        }
    }
    return onsets
}

func parse(_ name: String) -> (dyn: String, string: Int, notes: [Note])? {
    let parts = name.replacingOccurrences(of: ".aif", with: "").split(separator: ".").map(String.init)
    guard parts.count == 4, parts[0] == "Guitar", let s = strings.firstIndex(where: { $0.tag == parts[2] }) else { return nil }
    let range = parts[3]
    // "E2B2", "C5Gb5", or a single note "B3".
    let regex = try! NSRegularExpression(pattern: "[A-G]b?\\d")
    let found = regex.matches(in: range, range: NSRange(range.startIndex..., in: range)).map { String(range[Range($0.range, in: range)!]) }
    guard let lo = found.first.flatMap(Note.init), let hi = found.last.flatMap(Note.init) else { return nil }
    return (parts[1], s, (lo.midi...hi.midi).map { Note(midi: $0) })
}

func writeAAC(_ l: [Float], _ r: [Float], rate: Double, to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
        AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 96_000,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(l.count))!
    buffer.frameLength = AVAudioFrameCount(l.count)
    for i in 0..<l.count { buffer.floatChannelData![0][i] = l[i]; buffer.floatChannelData![1][i] = r[i] }
    try file.write(from: buffer)
}

if !dryRun { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }

var problems: [String] = []
var written = 0
var manifest: [String] = []
let files = try FileManager.default.contentsOfDirectory(atPath: inDir.path).filter { $0.hasSuffix(".aif") }.sorted()

for name in files {
    guard let info = parse(name) else { problems.append("\(name): name not understood"); continue }
    let (rawL, rawR, rate) = try readStereo(inDir.appendingPathComponent(name))
    let l = highPass(rawL, rate: rate), r = highPass(rawR, rate: rate)
    let mono = zip(l, r).map { ($0 + $1) * 0.5 }
    // Strict pass first; a more sensitive pass then only fills in notes the strict pass missed.
    let strict = findOnsets(mono, rate: rate)
    let sensitive = findOnsets(mono, rate: rate, rise: 2, minFraction: 0.005)
    let detector = PitchDetector(sampleRate: rate)
    let window = PitchDetector.windowSize(for: rate)

    let open = strings[info.string].open
    let expectedSet = Set(info.notes)
    // Best take per expected note, by clarity.
    var chosen: [Note: (onset: Int, next: Int, clarity: Double, cents: Double)] = [:]
    var rejected = 0
    for (pass, onsets) in [strict, sensitive].enumerated() {
    for (k, onset) in onsets.enumerated() {
        let next = k + 1 < onsets.count ? onsets[k + 1] : mono.count
        // The pitch must be clear and the same at 150 ms and 400 ms (a real, sustained note).
        func read(_ seconds: Double) -> (Note, Double, Double)? {
            let at = onset + Int(rate * seconds)
            guard at + window < min(next, mono.count) else { return nil }
            let r = detector.analyze(Array(mono[at..<(at + window)]))
            guard let f = r.frequency, r.clarity > (pass == 0 ? 0.9 : 0.85) else { return nil }
            let n = Note.nearest(to: f)
            return (n.note, n.cents, r.clarity)
        }
        guard let a = read(0.15), let b = read(0.4), a.0 == b.0, expectedSet.contains(a.0) else {
            if pass == 0 { rejected += 1 }
            continue
        }
        if pass == 1 && chosen[a.0] != nil { continue }
        if chosen[a.0] == nil || a.2 > chosen[a.0]!.clarity {
            chosen[a.0] = (onset, next, a.2, a.1)
        }
    }
    }
    let missing = info.notes.filter { chosen[$0] == nil }
    print("\(name): \(chosen.count)/\(info.notes.count) notes, \(rejected) other sounds skipped" + (missing.isEmpty ? "" : "  MISSING \(missing.map(\.nameWithOctave))"))
    if !missing.isEmpty { problems.append("\(name): missing \(missing.map(\.nameWithOctave).joined(separator: " "))") }

    for note in info.notes {
        guard let take = chosen[note] else { continue }
        let fret = note.midi - open.midi
        manifest.append(String(format: "s%d f%02d %@ %@ %+.0f cents", info.string, fret, info.dyn, note.nameWithOctave, take.cents))
        guard !dryRun else { continue }
        let start = max(0, take.onset - Int(rate * preRollSeconds))
        let end = min(take.next - Int(rate * 0.01), start + Int(rate * keepSeconds), mono.count)
        var nl = Array(l[start..<end]), nr = Array(r[start..<end])
        // Short fade-in on the pre-roll and a gentle fade at the end: no clicks.
        let fadeIn = Int(rate * 0.002)
        for i in 0..<min(fadeIn, nl.count) { let g = Float(i) / Float(fadeIn); nl[i] *= g; nr[i] *= g }
        let fadeOut = min(Int(rate * fadeOutSeconds), nl.count)
        for i in 0..<fadeOut {
            let g = Float(cos(Double(i) / Double(fadeOut) * .pi / 2))
            nl[nl.count - fadeOut + i] *= g; nr[nr.count - fadeOut + i] *= g
        }
        let fileName = String(format: "s%d_f%02d_%@.m4a", info.string, fret, info.dyn)
        try writeAAC(nl, nr, rate: rate, to: outDir.appendingPathComponent(fileName))
        written += 1
    }
}

print("\nWrote \(written) notes. Kept \(manifest.count) notes in total.")
if !dryRun {
    try manifest.joined(separator: "\n").write(to: outDir.appendingPathComponent("manifest.txt"), atomically: true, encoding: .utf8)
}
print(problems.isEmpty ? "No problems." : "PROBLEMS:\n" + problems.joined(separator: "\n"))
