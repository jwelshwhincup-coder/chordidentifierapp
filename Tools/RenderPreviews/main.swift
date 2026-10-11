// Renders listening previews with the app's own strum engine.
//
//   swiftc -O -o /tmp/previews Tools/RenderPreviews/main.swift chordid/Audio/StrumEngine.swift \
//       chordid/Audio/GuitarSamples.swift chordid/Model/Music.swift
//   /tmp/previews chordid/Resources/GuitarSamples AudioPreviews
import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let library = GuitarSampleLibrary(directory: URL(fileURLWithPath: args[1])) else {
    print("usage: previews <samples dir> <out dir>"); exit(1)
}
let out = URL(fileURLWithPath: args[2])
let fm = FileManager.default
try? fm.removeItem(at: out)
try fm.createDirectory(at: out.appendingPathComponent("1 Single notes"), withIntermediateDirectories: true)

func writeWAV(_ left: [Float], _ right: [Float], rate: Double, to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count))!
    buffer.frameLength = AVAudioFrameCount(left.count)
    for i in 0..<left.count { buffer.floatChannelData![0][i] = left[i]; buffer.floatChannelData![1][i] = right[i] }
    try file.write(from: buffer)
}

func peakDB(_ l: [Float], _ r: [Float]) -> String {
    String(format: "%.1f dBFS peak", 20 * log10(max(l.map(abs).max() ?? 0, r.map(abs).max() ?? 0, 1e-9)))
}

// 1. Single notes E2…E5, each on the string a player would normally use
//    (lowest fret position), at medium loudness.
var allL: [Float] = [], allR: [Float] = []
let spacing = Int(1.1 * library.sampleRate)
for (i, midi) in (40...76).enumerated() {
    let note = Note(midi: midi)
    let string = recordedOpenNotes.lastIndex { $0.midi <= midi } ?? 0
    let fret = midi - recordedOpenNotes[string].midi
    var shape = ChordShape.empty()
    shape.frets[string] = fret
    var rng = SeededRandom(seed: UInt64(midi))
    var style = StrumStyle.natural
    style.velocity = 0.6
    let events = StrumPlanner(source: library).plan(shape: shape, tuning: .standard, style: style, rng: &rng)
    let r = StrumRenderer.render(events, source: library)
    let name = String(format: "%02d %@.wav", i + 1, note.nameWithOctave.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b"))
    try writeWAV(r.left, r.right, rate: r.sampleRate, to: out.appendingPathComponent("1 Single notes/" + name))
    // Also lay them end to end in one file.
    let start = i * spacing
    if allL.count < start + r.left.count {
        allL += [Float](repeating: 0, count: start + r.left.count - allL.count)
        allR += [Float](repeating: 0, count: start + r.right.count - allR.count)
    }
    for k in r.left.indices { allL[start + k] += r.left[k]; allR[start + k] += r.right[k] }
    let e = events.first!
    print("note \(note.nameWithOctave): string \(e.sample.string) fret \(e.sample.fret) \(e.sample.layer) shift \(String(format: "%+.0f", e.pitchCents))¢")
}
try writeWAV(allL, allR, rate: library.sampleRate, to: out.appendingPathComponent("1 Single notes/00 All notes E2 to E5.wav"))

// 2. Chords, natural strum.
let chords: [(String, String)] = [("G major", "320003"), ("C major", "x32010"), ("Em7", "022030")]
for (k, (name, shape)) in chords.enumerated() {
    var rng = SeededRandom(seed: 100 + UInt64(k))
    let events = StrumPlanner(source: library).plan(shape: ChordShape(shape)!, tuning: .standard, style: .natural, rng: &rng)
    let r = StrumRenderer.render(events, source: library)
    try writeWAV(r.left, r.right, rate: r.sampleRate, to: out.appendingPathComponent("2 \(name) (\(shape)) down-strum.wav"))
    let gaps = zip(events.dropFirst(), events).map { String(format: "%.0f", ($0.time - $1.time) * 1000) }.joined(separator: " ")
    print("\(name): gaps ms [\(gaps)], \(peakDB(r.left, r.right))")
}

// 3. Same chord, three strum settings, each strummed three times so the variation is audible.
for (k, style) in [StrumStyle.gentle, .natural, .bright].enumerated() {
    let letter = ["A", "B", "C"][k]
    var l: [Float] = [], r: [Float] = []
    for take in 0..<3 {
        var rng = SeededRandom(seed: 200 + UInt64(k * 10 + take))
        let events = StrumPlanner(source: library).plan(shape: ChordShape("320003")!, tuning: .standard, style: style, rng: &rng)
        let rendered = StrumRenderer.render(events, source: library)
        let start = take * Int(2.2 * library.sampleRate)
        if l.count < start + rendered.left.count {
            l += [Float](repeating: 0, count: start + rendered.left.count - l.count)
            r += [Float](repeating: 0, count: start + rendered.left.count - r.count)
        }
        for i in rendered.left.indices { l[start + i] += rendered.left[i]; r[start + i] += rendered.right[i] }
    }
    let file = "3 G major setting \(letter) - \(style.name) (\(Int(style.gapMs)) ms) x3.wav"
    try writeWAV(l, r, rate: library.sampleRate, to: out.appendingPathComponent(file))
    print("\(file): \(peakDB(l, r))")
}
print("Done → \(out.path)")
