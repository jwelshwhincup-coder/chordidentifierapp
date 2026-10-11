import SwiftUI

/// Vertical six-string fretboard, nut at the top, scrolling down to fret 24.
/// String names and open/muted markers stay pinned above the scrolling frets.
struct FretboardView: View {
    let tuning: Tuning
    let shape: ChordShape
    /// Strings drawn in the accent colour (listening / strumming).
    var highlightedStrings: Set<Int> = []
    /// Spelled note name for the dot on a string.
    var noteName: (Int) -> String? = { _ in nil }
    /// nil makes the fretboard read-only.
    var onTapFret: ((_ string: Int, _ fret: Int) -> Void)?
    var onTapMarker: ((_ string: Int) -> Void)?

    static let fretHeight: CGFloat = 65
    static let nutHeight: CGFloat = 4
    static let headerHeight: CGFloat = 70
    private static let dotSize: CGFloat = 31
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
            ForEach(0..<tuning.stringCount, id: \.self) { string in
                let highlighted = highlightedStrings.contains(string)
                Text(tuning.stringNames[string])
                    .font(.brandCaption)
                    .foregroundStyle(highlighted ? Theme.accent : Theme.secondaryText)
                    .position(x: m.x(string), y: 26)

                marker(for: string, highlighted: highlighted)
                    .frame(width: max(m.spacing, Theme.minTouch), height: Theme.minTouch)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapMarker?(string) }
                    .position(x: m.x(string), y: 52)
                    .accessibilityElement()
                    .accessibilityLabel("\(tuning.stringNames[string]) string, \(markerDescription(string))")
                    .accessibilityHint(onTapMarker == nil ? "" : "Double tap to switch between open and muted")
                    .accessibilityAddTraits(onTapMarker == nil ? [] : .isButton)
            }
        }
    }

    @ViewBuilder
    private func marker(for string: Int, highlighted: Bool) -> some View {
        let color = highlighted ? Theme.accent : Theme.text
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

    // MARK: - Board

    private func board(_ m: Metrics) -> some View {
        let height = Self.nutHeight + Self.fretHeight * CGFloat(maxFret) + 16
        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
                drawBoard(context: &context, size: size, m: m)
            }

            // Invisible anchors so we can scroll to a fret.
            VStack(spacing: 0) {
                Color.clear.frame(height: Self.nutHeight)
                ForEach(1...maxFret, id: \.self) { fret in
                    Color.clear.frame(height: Self.fretHeight).id(fret)
                }
            }
            .allowsHitTesting(false)

            ForEach(0..<tuning.stringCount, id: \.self) { string in
                if let fret = shape.frets[string], fret > 0 {
                    dot(name: noteName(string) ?? "")
                        .position(x: m.x(string), y: Self.nutHeight + (CGFloat(fret) - 0.5) * Self.fretHeight)
                }
            }
        }
        .frame(width: m.width, height: height)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                guard let onTapFret, let string = m.string(at: value.location.x) else { return }
                let fret = Int((value.location.y - Self.nutHeight) / Self.fretHeight) + 1
                if (1...maxFret).contains(fret) { onTapFret(string, fret) }
            },
            including: onTapFret == nil ? .none : .all
        )
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

    private func drawBoard(context: inout GraphicsContext, size: CGSize, m: Metrics) {
        let first = m.x(0), last = m.x(tuning.stringCount - 1)
        let top = Self.nutHeight

        // Fret lines and inlays
        for fret in 1...maxFret {
            let y = top + CGFloat(fret) * Self.fretHeight
            var line = Path()
            line.move(to: CGPoint(x: first, y: y))
            line.addLine(to: CGPoint(x: last, y: y))
            context.stroke(line, with: .color(Theme.fretLine), lineWidth: 1.5)

            let centreY = y - Self.fretHeight / 2
            let r: CGFloat = 4.5
            var xs: [CGFloat] = []
            if Self.inlayFrets.contains(fret) { xs = [(m.x(2) + m.x(3)) / 2] }
            if Self.doubleInlayFrets.contains(fret) { xs = [(m.x(1) + m.x(2)) / 2, (m.x(3) + m.x(4)) / 2] }
            for x in xs {
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: centreY - r, width: 2 * r, height: 2 * r)), with: .color(Theme.inlay))
            }
            if !xs.isEmpty || fret == 1 {
                context.draw(Text("\(fret)").font(BrandFont.font(11, .semibold)).foregroundStyle(Theme.tertiaryText),
                             at: CGPoint(x: first / 2 - 2, y: centreY))
            }
        }

        // Highlight bands behind active strings
        for string in highlightedStrings where string < tuning.stringCount {
            let band = CGRect(x: m.x(string) - 7, y: 0, width: 14, height: size.height)
            context.fill(Path(roundedRect: band, cornerRadius: 7), with: .color(Theme.accent.opacity(0.14)))
        }

        // Strings
        for string in 0..<tuning.stringCount {
            let width = Self.stringWidths[min(string, Self.stringWidths.count - 1)]
            let highlighted = highlightedStrings.contains(string)
            let rect = CGRect(x: m.x(string) - width / 2, y: 0, width: highlighted ? max(width, 2.5) : width, height: size.height)
            context.fill(Path(rect), with: .color(highlighted ? Theme.accent : Theme.stringColor))
        }

        // Nut
        let nut = CGRect(x: first - 9, y: 0, width: last - first + 18, height: Self.nutHeight)
        context.fill(Path(roundedRect: nut, cornerRadius: 2), with: .color(Theme.text))
    }

    // MARK: - Helpers

    private func scrollToShape(_ proxy: ScrollViewProxy) {
        let fretted = shape.frets.compactMap { $0 }.filter { $0 > 0 }
        guard let highest = fretted.max(), highest > 4, let lowest = fretted.min() else { return }
        proxy.scrollTo(max(lowest - 1, 1), anchor: .top)
    }

    private func markerDescription(_ string: Int) -> String {
        switch shape.frets[string] {
        case nil: "muted"
        case 0: "open"
        case let fret?: "fret \(fret)"
        }
    }

    private var accessibilitySummary: String {
        (0..<tuning.stringCount).map { "\(tuning.stringNames[$0]) \(markerDescription($0))" }.joined(separator: ", ")
    }
}

#Preview {
    FretboardView(tuning: .standard, shape: ChordShape("x32010")!, noteName: { _ in "C" })
        .frame(height: 350)
        .card()
        .padding()
        .background(Theme.background)
}
