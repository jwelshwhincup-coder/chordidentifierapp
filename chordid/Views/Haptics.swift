import SwiftUI
import UIKit

/// Every haptic in the app, each a different strength. All respect the
/// "Haptics" switch in Settings.
enum Haptics {
    static let enabledKey = "hapticsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    /// A fret or open/muted marker was tapped.
    static func fretTap() { guard isEnabled else { return }; light.impactOccurred(intensity: 0.7) }

    /// The microphone accepted a note.
    static func noteAccepted() { guard isEnabled else { return }; medium.impactOccurred() }

    /// One string sounding during a strum.
    static func strumTick() { guard isEnabled else { return }; soft.impactOccurred(intensity: 0.45) }

    /// A chord has been named.
    static func chordNamed() { guard isEnabled else { return }; notification.notificationOccurred(.success) }

    /// Saved to the library.
    static func saved() { guard isEnabled else { return }; rigid.impactOccurred(intensity: 0.9) }

    /// About to delete something.
    static func warning() { guard isEnabled else { return }; notification.notificationOccurred(.warning) }

    /// Wake the Taptic Engine so the first haptic isn't late.
    static func prepare() {
        guard isEnabled else { return }
        light.prepare(); soft.prepare()
    }
}

/// Settings sheet: haptics switch and credits.
struct SettingsSheet: View {
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.replayDemo) private var replayDemo

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Color.clear.frame(width: Theme.minTouch, height: Theme.minTouch)
                Spacer()
                Text("Settings")
                    .font(.brandTitle)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                CircleIconButton(systemName: "xmark", style: .plain, label: "Close") { dismiss() }
            }
            .padding(.horizontal, Theme.sideMargin)
            .padding(.top, 28)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Toggle(isOn: $hapticsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Haptics")
                                .font(.brandHeadline)
                                .foregroundStyle(Theme.text)
                            Text("Gentle taps when you place notes, strum and save.")
                                .font(.brandSubheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .tint(Theme.accent)
                    .onChange(of: hapticsEnabled) { _, on in if on { Haptics.fretTap() } }
                    .padding(18)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Button {
                        dismiss()
                        replayDemo()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Replay demo")
                                    .font(.brandHeadline)
                                    .foregroundStyle(Theme.text)
                                Text("See the quick tour of Chord ID again.")
                                    .font(.brandSubheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "play.circle")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(18)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Credits")
                            .font(.brandHeadline)
                            .foregroundStyle(Theme.text)
                        Text("Guitar recordings: University of Iowa Electronic Music Studios, Musical Instrument Samples.")
                        Text("Typeface: Bricolage Grotesque, SIL Open Font License 1.1.")
                    }
                    .font(.brandSubheadline)
                    .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, Theme.sideMargin)
            }
        }
        .background(Theme.card)
        .presentationDetents([.height(500), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }
}
