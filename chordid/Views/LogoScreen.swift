import SwiftUI

/// How the logo screen plays this launch.
enum LaunchStyle: Equatable {
    /// First launch: fretboard draws, question mark strokes on, dot drops in (~1.2 s).
    case full
    /// Later launches: the logo fades in briefly, then the app.
    case quick
    /// Reduce Motion: the logo appears still, then fades.
    case still

    static let hasLaunchedKey = "hasLaunchedBefore"

    static func choose(hasLaunchedBefore: Bool, reduceMotion: Bool) -> LaunchStyle {
        if reduceMotion { return .still }
        return hasLaunchedBefore ? .quick : .full
    }

    /// When to start fading into the app, in seconds after the logo screen appears.
    var holdSeconds: Double {
        switch self {
        case .full: 1.2
        case .quick: 0.3
        case .still: 0.6
        }
    }

    /// Length of the cross-fade into the app.
    var fadeSeconds: Double { self == .full ? 0.35 : 0.25 }
}

/// Full-screen logo shown over the app at launch. Its first frame is identical to
/// the static launch screen (an empty tile and "Chord ID").
struct LogoScreen: View {
    let style: LaunchStyle
    var onDotLanded: () -> Void = {}
    var onFinished: () -> Void

    @State private var lines: CGFloat = 0
    @State private var mark: CGFloat = 0
    @State private var dot: CGFloat = 0
    @State private var detail: Double = 1

    var body: some View {
        ZStack {
            Theme.background
            LaunchCanvas(lines: lines, mark: mark, dot: dot, detail: detail)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chord ID")
        .task { await play() }
    }

    private func play() async {
        switch style {
        case .full:
            withAnimation(.easeOut(duration: 0.45)) { lines = 1 }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut(duration: 0.42)) { mark = 1 }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { dot = 1 }
            try? await Task.sleep(for: .milliseconds(140))
            onDotLanded()
            try? await Task.sleep(for: .milliseconds(310))
        case .quick, .still:
            detail = 0
            lines = 1; mark = 1; dot = 1
            withAnimation(.easeOut(duration: 0.15)) { detail = 1 }
            try? await Task.sleep(for: .seconds(style.holdSeconds))
        }
        onFinished()
    }
}
