import SwiftUI

/// Vertical six-string fretboard, nut at the top, scrolling down to fret 24.
/// String names and open/muted markers stay pinned above the scrolling frets.
struct FretboardView: View {
    let tuning: Tuning
    let shape: ChordShape
    /// Capo fret. Dots are relative to the capo; fret numbers and inlays show the real fret.
    var capo: Int = 0
    /// Names shown above the strings. Defaults to the tuning's names.
    var stringLabels: [String]?
    /// Strings drawn in the accent colour (listening / strumming).
    var highlightedStrings: Set<Int> = []
    /// While listening: the string being listened for. Strings after it show no marker yet.
    var listeningString: Int?
    /// When each string started vibrating (strum), for the wobble animation.
    var vibratingSince: [Int: Date] = [:]
    /// Spelled note name for the dot on a string.
    var noteName: (Int) -> String? = { _ in nil }
    /// nil makes the fretboard read-only.
    var onTapFret: ((_ string: Int, _ fret: Int) -> Void)?
    var onTapMarker: ((_ string: Int) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How long a strummed string visibly vibrates.
    static let vibrationSeconds = 0.7

    static let fretHeight: CGFloat = 65
    static let nutHeight: CGFloat = 4
    static let headerHeight: CGFloat = 70
    private static let dotSize: CGFloat = 31
    private var fretCount: Int { maxFret - capo }
    private static let inlayFrets: Set<Int> = [3, 5, 7, 9, 15, 17, 19, 21]
    private static let doubleInlayFrets: Set<Int> = [12, 24]
    private static let stringWidths: [CGFloat] = [3, 2.6, 2.2, 1.8, 1.5, 1.2]

    /// Horizontal layout derived from the card width.
    struct Metrics {
        let width: CGFloat
        let stringCount: Int
        var inset: CGFloat { width * 0.142 }
        var spacing: CGFloat { (width - 2 * inset) / CGFloat(max(stringCount - 1, 1)) }
        func x(_ string: Int) -> CGFloat { inset + CGFloat(string) * spacing }

        /// Nearest string to an x position, or nil if outside the board.
        func string(at x: CGFloat) -> Int? {
            let i = Int(((x - inset) / spacing).rounded())
            guard (0..<stringCount).contains(i), abs(x - self.x(i)) <= max(spacing / 2, Theme.minTouch / 2) else { return nil }
            return i
        }
    }

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(width: geo.size.width, stringCount: tuning.stringCount)
            VStack(spacing: 0) {
                header(m)
                    .frame(height: Self.headerHeight)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        board(m)
                    }
                    .onAppear { scrollToShape(proxy) }
                    .onChange(of: shape) { old, new in
                        // While listening, bring a newly heard note into view.
                        guard listeningString != nil || new.isEmpty else { return }
                        if new.isEmpty { proxy.scrollTo(1, anchor: .top); return }
                        for (before, after) in zip(old.frets, new.frets) where before != after {
                            if let fret = after, fret > 0 {
                                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(fret, anchor: .center) }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: onTapFret == nil ? .ignore : .contain)
        .accessibilityLabel("Fretboard")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: - Header (string names + open/muted markers)

    private func header(_ m: Metrics) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: m.x(tuning.stringCount - 1) - m.x(0) + Theme.minTouch, height: Theme.minTouch)
                .demoTarget(.markerRow)
                .position(x: (m.x(0) + m.x(tuning.stringCount - 1)) / 2, y: 52)
                .allowsHitTesting(false)
            ForEach(0..<tuning.stringCount, id: \.self) { string in
                let highlighted = highlightedStrings.contains(string)
                Text(label(string))
                    .font(.brandCaption)
                    .foregroundStyle(highlighted ? Theme.accent : Theme.secondaryText)
                    .position(x: m.x(string), y: 26)

                marker(for: string, highlighted: highlighted)
                    .frame(width: max(m.spacing, Theme.minTouch), height: Theme.minTouch)
                    .demoTarget(.marker(string))
                    .contentShape(Rectangle())
                    .onTapGesture { onTapMarker?(string) }
                    .position(x: m.x(string), y: 52)
                    .accessibilityElement()
                    .accessibilityLabel("\(label(string)) string, \(markerDescription(string))")
                    .accessibilityHint(onTapMarker == nil ? "" : "Double tap to switch between open and muted")
                    .accessibilityAddTraits(onTapMarker == nil ? [] : .isButton)
            }
        }
    }

    @ViewBuilder
    private func marker(for string: Int, highlighted: Bool) -> some View {
        let color = highlighted ? Theme.accent : Theme.text
        if let listening = listeningString, string >= listening {
            if string == listening {
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: 2.6)
                    .frame(width: 17, height: 17)
            } else {
                Color.clear
            }
        } else {
            switch shape.frets[string] {
        case nil:
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(highlighted ? Theme.accent : Theme.muteMark)
        case 0:
            Circle()
                .strokeBorder(color, lineWidth: 2.2)
                .frame(width: 15, height: 15)
        default:
            Color.clear
            }
        }
    }

    // MARK: - Board

    private func board(_ m: Metrics) -> some View {
        let height = Self.nutHeight + Self.fretHeight * CGFloat(fretCount) + 16
        return ZStack(alignment: .topLeading) {
            // Only run a frame clock while a string is vibrating; otherwise draw once.
            if vibratingSince.isEmpty || reduceMotion {
                Canvas { context, size in
                    drawBoard(context: &context, size: size, m: m, now: .now)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    Canvas { context, size in
                        drawBoard(context: &context, size: size, m: m, now: timeline.date)
                    }
                }
            }

            // The string being listened for glows and pulses.
            if let listening = listeningString, listening < tuning.stringCount {
                ListeningGlow(reduceMotion: reduceMotion)
                    .frame(width: 22, height: height)
                    .position(x: m.x(listening), y: height / 2)
                    .allowsHitTesting(false)
            }

            // Invisible anchors so we can scroll to a fret.
            VStack(spacing: 0) {
                Color.clear.frame(height: Self.nutHeight)
                ForEach(1...fretCount, id: \.self) { fret in
                    Color.clear.frame(height: Self.fretHeight).id(fret)
                }
            }
            .allowsHitTesting(false)

            // Spots the first-launch demo taps.
            ForEach(0..<tuning.stringCount, id: \.self) { string in
                ForEach(1...3, id: \.self) { fret in
                    Color.clear
                        .frame(width: Theme.minTouch, height: Theme.minTouch)
                        .demoTarget(.fret(string: string, fret: fret))
                        .position(x: m.x(string), y: Self.nutHeight + (CGFloat(fret) - 0.5) * Self.fretHeight)
                        .allowsHitTesting(false)
                }
            }

            // Keyed by string and fret, so moving a dot springs out of the old spot and into the new.
            ForEach(dots, id: \.self) { item in
                dot(name: noteName(item.string) ?? "")
                    .position(x: m.x(item.string), y: Self.nutHeight + (CGFloat(item.fret) - 0.5) * Self.fretHeight)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.58), value: dots)
        .frame(width: m.width, height: height)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                guard let onTapFret, let string = m.string(at: value.location.x) else { return }
                let fret = Int((value.location.y - Self.nutHeight) / Self.fretHeight) + 1
                if (1...fretCount).contains(fret) { onTapFret(string, fret) }
            },
            including: onTapFret == nil ? .none : .all
        )
    }

    private struct DotItem: Hashable { let string: Int; let fret: Int }

    private var dots: [DotItem] {
        shape.frets.enumerated().compactMap { string, fret in
            guard let fret, fret > 0, fret <= fretCount else { return nil }
            return DotItem(string: string, fret: fret)
        }
    }

    private func dot(name: String) -> some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: Self.dotSize, height: Self.dotSize)
            .overlay {
                Text(name)
                    .font(BrandFont.font(name.count > 1 ? 12 : 14, .bold, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }
            .allowsHitTesting(false)
    }

    private func drawBoard(context: inout GraphicsContext, size: CGSize, m: Metrics, now: Date) {
        let first = m.x(0), last = m.x(tuning.stringCount - 1)
        let top = Self.nutHeight

        // Fret lines and inlays. `fret` counts from the capo; inlays and numbers use the real fret.
        for fret in 1...fretCount {
            let realFret = capo + fret
            let y = top + CGFloat(fret) * Self.fretHeight
            var line = Path()
            line.move(to: CGPoint(x: first, y: y))
            line.addLine(to: CGPoint(x: last, y: y))
            context.stroke(line, with: .color(Theme.fretLine), lineWidth: 1.5)

            let centreY = y - Self.fretHeight / 2
            let r: CGFloat = 4.5
            var xs: [CGFloat] = []
            if Self.inlayFrets.contains(realFret) { xs = [(m.x(2) + m.x(3)) / 2] }
            if Self.doubleInlayFrets.contains(realFret) { xs = [(m.x(1) + m.x(2)) / 2, (m.x(3) + m.x(4)) / 2] }
            for x in xs {
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: centreY - r, width: 2 * r, height: 2 * r)), with: .color(Theme.inlay))
            }
            if !xs.isEmpty || fret == 1 {
                context.draw(Text("\(realFret)").font(BrandFont.font(11, .semibold)).foregroundStyle(Theme.tertiaryText),
                             at: CGPoint(x: first / 2 - 2, y: centreY))
            }
        }

        // Highlight bands behind active strings
        for string in highlightedStrings where string < tuning.stringCount {
            let band = CGRect(x: m.x(string) - 7, y: 0, width: 14, height: size.height)
            context.fill(Path(roundedRect: band, cornerRadius: 7), with: .color(Theme.accent.opacity(0.14)))
        }

        // Strings (a strummed string wobbles as a decaying standing wave)
        for string in 0..<tuning.stringCount {
            let width = Self.stringWidths[min(string, Self.stringWidths.count - 1)]
            let highlighted = highlightedStrings.contains(string)
            let color = highlighted ? Theme.accent : Theme.stringColor
            let lineWidth = highlighted ? max(width, 2.5) : width
            let elapsed = vibratingSince[string].map { now.timeIntervalSince($0) } ?? .infinity
            if !reduceMotion, elapsed >= 0, elapsed < Self.vibrationSeconds {
                let amplitude = 3.2 * exp(-elapsed * 5) * sin(elapsed * 2 * .pi * (16 - Double(string)))
                var path = Path()
                let x = m.x(string)
                for y in stride(from: 0.0, through: Double(size.height), by: 6) {
                    // Half-wavelength of ~5 frets, so the wobble shows in the visible part of the board.
                    let dx = amplitude * sin(.pi * y / (Double(Self.fretHeight) * 5))
                    let point = CGPoint(x: x + dx, y: y)
                    if y == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
            } else {
                let rect = CGRect(x: m.x(string) - lineWidth / 2, y: 0, width: lineWidth, height: size.height)
                context.fill(Path(rect), with: .color(color))
            }
        }

        // Nut, or the capo bar when a capo is on
        let nut = CGRect(x: first - 9, y: 0, width: last - first + 18, height: Self.nutHeight)
        context.fill(Path(roundedRect: nut, cornerRadius: 2), with: .color(capo > 0 ? Theme.accent : Theme.text))
    }

    // MARK: - Helpers

    private func scrollToShape(_ proxy: ScrollViewProxy) {
        let fretted = shape.frets.compactMap { $0 }.filter { $0 > 0 && $0 <= fretCount }
        guard let highest = fretted.max(), highest > 4, let lowest = fretted.min() else { return }
        proxy.scrollTo(max(lowest - 1, 1), anchor: .top)
    }

    private func label(_ string: Int) -> String {
        stringLabels?[string] ?? tuning.stringNames[string]
    }

    private func markerDescription(_ string: Int) -> String {
        switch shape.frets[string] {
        case nil: "muted"
        case 0: "open"
        case let fret?: "fret \(fret)"
        }
    }

    private var accessibilitySummary: String {
        (capo > 0 ? "Capo on fret \(capo). " : "") + (0..<tuning.stringCount).map { "\(label($0)) \(markerDescription($0))" }.joined(separator: ", ")
    }
}

/// Soft pulsing band behind the string the microphone is waiting for.
private struct ListeningGlow: View {
    let reduceMotion: Bool
    @State private var pulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(Theme.accent.opacity(pulsing ? 0.26 : 0.08))
            .shadow(color: Theme.accent.opacity(pulsing ? 0.45 : 0), radius: 10)
            .onAppear {
                guard !reduceMotion else { pulsing = true; return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulsing = true }
            }
    }
}

#Preview {
    FretboardView(tuning: .standard, shape: ChordShape("x32010")!, noteName: { _ in "C" })
        .frame(height: 350)
        .card()
        .padding()
        .background(Theme.background)
}
