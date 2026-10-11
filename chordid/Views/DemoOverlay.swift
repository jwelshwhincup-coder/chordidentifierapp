import SwiftUI
import UIKit

/// The dimmed layer, spotlight, tap ring, speech bubble and Skip button drawn
/// over the real app while the first-launch demo runs (mockups 02–05).
struct DemoOverlay: View {
    let demo: DemoController
    /// Target frames in this view's coordinate space (full screen).
    let rects: [DemoTarget: CGRect]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var bubbleFocused: Bool
    @State private var bubbleHeight: CGFloat = 160
    /// Last known spotlight, kept while a target is between layouts.
    @State private var lastSpotlight: CGRect = .zero

    var body: some View {
        GeometryReader { geo in
            let insets = Self.windowInsets
            let spotlight = spotlightRect()
            ZStack(alignment: .topLeading) {
                SpotlightCutout(rect: spotlight, radius: spotlightRadius(spotlight))
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86), value: spotlight)
                    .accessibilityHidden(true)

                if let ring = demo.tapRing, let rect = rects[ring] {
                    TapRing(reduceMotion: reduceMotion)
                        .frame(width: 58, height: 58)
                        .position(x: rect.midX, y: rect.midY)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }

                bubble(in: geo.size, insets: insets, spotlight: spotlight)

                Button("Skip", action: demo.skip)
                    .font(.brandBodyBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 50)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.85), lineWidth: 2))
                    .contentShape(Capsule())
                    .position(x: geo.size.width - Theme.sideMargin - 40, y: insets.top + 8 + SetupBar.height / 2)
                    .accessibilityLabel("Skip demo")
                    .accessibilitySortPriority(-1)
            }
            .contentShape(Rectangle())
            .onTapGesture { demo.advance() }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onChange(of: demo.stepIndex, initial: true) { _, _ in
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                bubbleFocused = true
            }
        }
        .onChange(of: spotlightRect()) { _, rect in if rect != .zero { lastSpotlight = rect } }
    }

    // MARK: - Spotlight

    private func spotlightRect() -> CGRect {
        guard let target = rects[demo.step.target] else { return lastSpotlight }
        switch demo.step.spotlight {
        case .circle(let d):
            return CGRect(x: target.midX - d / 2, y: target.midY - d / 2, width: d, height: d)
        case .roundedRect(let padding, _):
            return target.insetBy(dx: -padding, dy: -padding)
        }
    }

    private func spotlightRadius(_ rect: CGRect) -> CGFloat {
        switch demo.step.spotlight {
        case .circle: min(rect.width, rect.height) / 2
        case .roundedRect(_, let r): r
        }
    }

    // MARK: - Bubble

    @ViewBuilder
    private func bubble(in size: CGSize, insets: UIEdgeInsets, spotlight: CGRect) -> some View {
        let width = min(size.width - 2 * Theme.sideMargin, 360)
        let target = rects[demo.step.target] ?? spotlight
        let x = min(max(target.midX - width / 2, Theme.sideMargin), size.width - Theme.sideMargin - width)
        let gap: CGFloat = 14
        let pointer: CGFloat = 12
        let roomBelow = size.height - insets.bottom - 16 - (spotlight.maxY + gap + pointer)
        let roomAbove = spotlight.minY - gap - pointer - insets.top - 16
        let below = demo.step.bubbleSide == .below
            ? bubbleHeight <= roomBelow || roomBelow >= roomAbove
            : !(bubbleHeight <= roomAbove || roomAbove >= roomBelow)
        let y = below ? spotlight.maxY + gap + pointer : spotlight.minY - gap - pointer - bubbleHeight
        let pointerX = min(max(target.midX - x, 34), width - 34)

        BubbleCard(demo: demo, pointerOnTop: below, pointerX: pointerX)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { g in
                Color.clear.preference(key: BubbleHeightKey.self, value: g.size.height)
            })
            .onPreferenceChange(BubbleHeightKey.self) { bubbleHeight = $0 }
            .offset(x: x, y: max(insets.top + 8, y))
            .id(demo.stepIndex)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .scale(scale: 0.88, anchor: below ? .top : .bottom).combined(with: .opacity),
                removal: .opacity))
            .accessibilityFocused($bubbleFocused)
    }

    private static var windowInsets: UIEdgeInsets {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return window?.safeAreaInsets ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
    }
}

private struct BubbleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 160
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// White speech bubble: title, explanation, progress dots and "n of 4 · tap to continue"
/// (or "Start playing" on the last step).
private struct BubbleCard: View {
    let demo: DemoController
    let pointerOnTop: Bool
    let pointerX: CGFloat

    var body: some View {
        let step = demo.step
        let count = DemoController.steps.count
        VStack(alignment: .leading, spacing: 10) {
            Text(step.title)
                .font(BrandFont.font(22, .bold, relativeTo: .title3))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.body)
                .font(.brandBody)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i == demo.stepIndex ? Theme.accent : Theme.divider)
                        .frame(width: i == demo.stepIndex ? 22 : 7, height: 7)
                }
                Spacer(minLength: 12)
                if demo.isLastStep {
                    Button("Start playing", action: demo.startPlaying)
                        .font(.brandBodyBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 50)
                        .background(Theme.accent, in: Capsule())
                        .accessibilityHint("Closes the demo and starts listening")
                } else {
                    Text("\(demo.stepIndex + 1) of \(count) · tap to continue")
                        .font(.brandSubheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(
            BubbleShape(pointerOnTop: pointerOnTop, pointerX: pointerX)
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        )
        .accessibilityElement(children: demo.isLastStep ? .contain : .combine)
        .accessibilityLabel("Step \(demo.stepIndex + 1) of \(count). \(step.title) \(step.body)")
        .accessibilityHint(demo.isLastStep ? "" : "Double tap to continue")
        .accessibilityAction { demo.advance() }
    }
}

/// Rounded card with a small pointer aimed at the spotlight.
private struct BubbleShape: Shape {
    let pointerOnTop: Bool
    let pointerX: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: 28, style: .continuous)
        let w: CGFloat = 26, h: CGFloat = 12
        var tri = Path()
        if pointerOnTop {
            tri.move(to: CGPoint(x: pointerX - w / 2, y: rect.minY + 1))
            tri.addLine(to: CGPoint(x: pointerX, y: rect.minY - h))
            tri.addLine(to: CGPoint(x: pointerX + w / 2, y: rect.minY + 1))
        } else {
            tri.move(to: CGPoint(x: pointerX - w / 2, y: rect.maxY - 1))
            tri.addLine(to: CGPoint(x: pointerX, y: rect.maxY + h))
            tri.addLine(to: CGPoint(x: pointerX + w / 2, y: rect.maxY - 1))
        }
        tri.closeSubpath()
        p.addPath(tri)
        return p
    }
}

/// Full-screen dim with a rounded hole; the hole's frame animates so the spotlight slides.
private struct SpotlightCutout: Shape {
    var rect: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get { AnimatablePair(AnimatablePair(rect.origin.x, rect.origin.y), AnimatablePair(AnimatablePair(rect.width, rect.height), radius)) }
        set {
            rect = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first.first, height: newValue.second.first.second)
            radius = newValue.second.second
        }
    }

    func path(in bounds: CGRect) -> Path {
        var p = Path(bounds.insetBy(dx: -200, dy: -200))
        if rect.width > 0 {
            p.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return p
    }
}

/// White ring where a finger would tap; pulses before the UI reacts.
private struct TapRing: View {
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.28))
            Circle().strokeBorder(.white, lineWidth: 3)
        }
        .scaleEffect(reduceMotion ? 1 : (pulse ? 1.12 : 0.7))
        .opacity(reduceMotion ? 1 : (pulse ? 0.95 : 0.5))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
