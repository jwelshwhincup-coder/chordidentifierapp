import SwiftUI

/// Hidden tuner-style readout for checking detection with a real guitar.
/// Opened by holding the mic button for a second.
struct PitchDebugView: View {
    let tuning: Tuning
    @State private var monitor = PitchMonitor()
    /// nil = listen for anything; otherwise constrain to that string like the listening flow does.
    @State private var string: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Pitch debug")
                        .font(.brandTitle)
                    Spacer()
                    CircleIconButton(systemName: "xmark", style: .plain, label: "Close") { dismiss() }
                }

                if let error = monitor.error {
                    Text(error).font(.brandBody).foregroundStyle(Theme.warning)
                }

                Picker("String", selection: $string) {
                    Text("Any").tag(Int?.none)
                    ForEach(0..<tuning.stringCount, id: \.self) { i in
                        Text(tuning.stringNames[i]).tag(Int?.some(i))
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: string) { _, s in monitor.setString(s, tuning: tuning) }

                let reading = monitor.reading
                let nearest = reading?.frequency.map { Note.nearest(to: $0) }
                let passes = (reading?.clarity ?? 0) >= monitor.minClarity && (reading?.rms ?? 0) >= monitor.gateRMS

                Text(nearest?.note.nameWithOctave ?? "–")
                    .font(BrandFont.font(72, .extraBold, relativeTo: .largeTitle))
                    .foregroundStyle(passes ? Theme.text : Theme.divider)
                    .frame(maxWidth: .infinity)

                CentsBar(cents: nearest?.cents)
                    .frame(height: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Input level")
                        .font(.brandSubheadline)
                        .foregroundStyle(Theme.secondaryText)
                    LevelBar(level: monitor.levelDB, floor: monitor.floorDB, gate: monitor.gateDB, onset: monitor.onsetDB)
                        .frame(height: 30)
                    HStack(spacing: 12) {
                        legend(Theme.tertiaryText, "room")
                        legend(.green, "note gate")
                        legend(Theme.accent, "pluck")
                    }
                    .font(.brandCaption)
                    .foregroundStyle(Theme.secondaryText)
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    row("Frequency", reading?.frequency.map { String(format: "%.2f Hz", $0) } ?? "–")
                    row("Cents off", nearest.map { String(format: "%+.1f", $0.cents) } ?? "–")
                    row("Confidence", reading.map { String(format: "%.3f", $0.clarity) } ?? "–",
                        good: (reading?.clarity ?? 0) >= monitor.minClarity)
                    row("Level", String(format: "%.1f dBFS", monitor.levelDB),
                        good: (reading?.rms ?? 0) >= monitor.gateRMS)
                    row("Room", String(format: "%.1f dBFS%@", monitor.floorDB, monitor.calibrated ? "" : " (measuring)"))
                    row("Octave fixed", reading?.octaveCorrected == true ? "yes" : "no")
                    row("Accepted", monitor.accepted.map(\.nameWithOctave).suffix(6).joined(separator: "  "))
                }
                .font(.brandBody)

                Text("A pluck must rise 12 dB above the room; the ringing note is analysed while it stays 6 dB above. Choose a string to limit answers to what that string can play (open to fret 24). Open strings: \(tuning.openNotes.map(\.nameWithOctave).joined(separator: " "))")
                    .font(.brandSubheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(Theme.sideMargin)
        }
        .background(Theme.card)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 3, height: 12)
            Text(text)
        }
    }

    private func row(_ label: String, _ value: String, good: Bool? = nil) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.secondaryText)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(good == nil ? Theme.text : (good! ? Color.green : Theme.warning))
        }
    }
}

/// −90 … 0 dBFS bar with markers for the room level, note gate and pluck threshold.
private struct LevelBar: View {
    let level: Double, floor: Double, gate: Double, onset: Double

    var body: some View {
        GeometryReader { geo in
            let x = { (db: Double) in CGFloat(min(max((db + 90) / 90, 0), 1)) * geo.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.background)
                Capsule().fill(level >= gate ? Color.green.opacity(0.6) : Theme.tertiaryText.opacity(0.5))
                    .frame(width: max(x(level), 6))
                marker(Theme.tertiaryText).offset(x: x(floor))
                marker(.green).offset(x: x(gate))
                marker(Theme.accent).offset(x: x(onset))
            }
        }
        .animation(.linear(duration: 0.05), value: level)
    }

    private func marker(_ color: Color) -> some View {
        Rectangle().fill(color).frame(width: 3)
    }
}

/// ±50 cent bar with a marker.
private struct CentsBar: View {
    let cents: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Capsule().fill(Theme.background)
                Rectangle().fill(Theme.tertiaryText).frame(width: 2)
                if let cents {
                    let x = CGFloat(max(-50, min(50, cents)) / 50) * (geo.size.width / 2 - 10)
                    Circle()
                        .fill(abs(cents) < 5 ? Color.green : Theme.accent)
                        .frame(width: 20, height: 20)
                        .offset(x: x)
                }
            }
        }
    }
}

/// Runs its own tracker and stabilizer for the debug view.
@Observable
final class PitchMonitor {
    private(set) var reading: PitchReading?
    private(set) var accepted: [Note] = []
    private(set) var error: String?
    private(set) var levelDB: Double = -90
    private(set) var floorDB: Double = -90
    private(set) var gateDB: Double = -90
    private(set) var onsetDB: Double = -90
    private(set) var gateRMS: Double = 1
    private(set) var calibrated = false
    let minClarity = NoteStabilizer.Config().minClarity

    @ObservationIgnored private let tracker = PitchTracker()
    @ObservationIgnored private var stabilizer = NoteStabilizer()

    func start() {
        tracker.onReading = { [weak self] reading in
            guard let self else { return }
            Task { @MainActor in self.handle(reading) }
        }
        Task {
            guard await AudioSessionManager.requestMicPermission() else {
                error = "Microphone permission is off. Turn it on in Settings."
                return
            }
            do {
                try AudioSessionManager.activateForListening()
                try tracker.start()
            } catch {
                self.error = "Couldn't start the microphone."
            }
        }
    }

    func setString(_ string: Int?, tuning: Tuning) {
        guard let string else { tracker.setExpectedRange(nil); return }
        let open = tuning.openNotes[string]
        tracker.setExpectedRange(open.frequency() * pow(2, -1.5 / 12)...Note(midi: open.midi + maxFret).frequency() * pow(2, 0.5 / 12))
    }

    func stop() {
        tracker.stop()
        AudioSessionManager.deactivate()
    }

    private func handle(_ reading: PitchReading) {
        self.reading = reading
        if let note = stabilizer.process(reading) { accepted.append(note) }
        levelDB = reading.decibels
        floorDB = PitchReading.decibels(stabilizer.noiseFloor)
        gateDB = PitchReading.decibels(stabilizer.gateRMS)
        onsetDB = PitchReading.decibels(stabilizer.onsetRMS)
        gateRMS = stabilizer.gateRMS
        calibrated = stabilizer.isCalibrated
    }
}
