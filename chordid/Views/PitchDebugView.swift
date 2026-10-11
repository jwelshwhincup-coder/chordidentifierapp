import SwiftUI

/// Hidden tuner-style readout for checking detection with a real guitar.
/// Opened by holding the mic button for a second.
struct PitchDebugView: View {
    let tuning: Tuning
    @State private var monitor = PitchMonitor()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Pitch debug")
                    .font(.brandTitle)
                Spacer()
                CircleIconButton(systemName: "xmark", style: .plain, label: "Close") { dismiss() }
            }

            if let error = monitor.error {
                Text(error).font(.brandBody).foregroundStyle(Theme.warning)
            }

            let reading = monitor.reading
            let nearest = reading?.frequency.map { Note.nearest(to: $0) }

            let passes = (reading?.clarity ?? 0) >= NoteStabilizer.Config().minClarity
                && (reading?.rms ?? 0) >= NoteStabilizer.Config().gateRMS
            Text(nearest?.note.nameWithOctave ?? "–")
                .font(BrandFont.font(72, .extraBold, relativeTo: .largeTitle))
                .foregroundStyle(passes ? Theme.text : Theme.divider)
                .frame(maxWidth: .infinity)

            CentsBar(cents: nearest?.cents)
                .frame(height: 28)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                row("Frequency", reading?.frequency.map { String(format: "%.2f Hz", $0) } ?? "–")
                row("Cents off", nearest.map { String(format: "%+.1f", $0.cents) } ?? "–")
                row("Confidence", reading.map { String(format: "%.3f", $0.clarity) } ?? "–",
                    good: (reading?.clarity ?? 0) >= NoteStabilizer.Config().minClarity)
                row("Level", reading.map { String(format: "%.1f dBFS", $0.decibels) } ?? "–",
                    good: (reading?.rms ?? 0) >= NoteStabilizer.Config().gateRMS)
                row("Accepted", monitor.accepted.map(\.nameWithOctave).suffix(6).joined(separator: "  "))
            }
            .font(.brandBody)

            Text("Green means that value passes the gate. A note is accepted after 5 steady frames following the pluck. Open strings: \(tuning.openNotes.map(\.nameWithOctave).joined(separator: " "))")
                .font(.brandSubheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
        }
        .padding(Theme.sideMargin)
        .background(Theme.card)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
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

    func stop() {
        tracker.stop()
        AudioSessionManager.deactivate()
    }

    private func handle(_ reading: PitchReading) {
        self.reading = reading
        if let note = stabilizer.process(reading) { accepted.append(note) }
    }
}
