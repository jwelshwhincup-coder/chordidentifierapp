import SwiftUI

/// The Chord ID logo drawn as shapes, using the geometry of `logo-rounded.svg`
/// (a 200 × 200 unit square), so each part can animate on the logo screen.
struct LogoMark: View {
    /// 0…1: how much of the fretboard lines have drawn in.
    var lines: CGFloat = 1
    /// 0…1: how much of the question mark has stroked on.
    var mark: CGFloat = 1
    /// 0 = dot above its spot and hidden, 1 = in place (a spring overshoots past 1).
    var dot: CGFloat = 1
    /// Opacity of everything on the tile (used for the quick fade).
    var detail: Double = 1

    private static let ink = Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x17 / 255)
    private static let blue = Color(red: 0x2B / 255, green: 0x5B / 255, blue: 0xFF / 255)

    /// Strings, then the nut, then the three frets, in the order they draw in.
    private static let gridLines: [(CGPoint, CGPoint)] =
        [44, 72, 100, 128, 156].map { (CGPoint(x: $0, y: 40), CGPoint(x: $0, y: 172)) }
        + [84, 128, 172].map { (CGPoint(x: 44, y: $0), CGPoint(x: 156, y: $0)) }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 200
            ZStack {
                RoundedRectangle(cornerRadius: 46 * s, style: .continuous)
                    .fill(.white)

                Group {
                    ForEach(Self.gridLines.indices, id: \.self) { i in
                        UnitLine(from: Self.gridLines[i].0, to: Self.gridLines[i].1)
                            .trim(from: 0, to: stagger(lines, index: i, count: Self.gridLines.count + 1))
                            .stroke(Self.ink.opacity(0.14), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
                    }
                    UnitLine(from: CGPoint(x: 44, y: 40), to: CGPoint(x: 156, y: 40))
                        .trim(from: 0, to: stagger(lines, index: Self.gridLines.count, count: Self.gridLines.count + 1))
                        .stroke(Self.ink.opacity(0.4), style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))

                    // A white halo under the mark keeps it clear of the grid.
                    QuestionMarkShape()
                        .trim(from: 0, to: mark)
                        .stroke(.white, style: StrokeStyle(lineWidth: 30 * s, lineCap: .round, lineJoin: .round))
                    QuestionMarkShape()
                        .trim(from: 0, to: mark)
                        .stroke(Self.ink, style: StrokeStyle(lineWidth: 16 * s, lineCap: .round, lineJoin: .round))

                    ZStack {
                        Circle().fill(.white).frame(width: 38 * s, height: 38 * s)
                        Circle().fill(Self.blue).frame(width: 24 * s, height: 24 * s)
                    }
                    .position(x: 100 * s, y: (151 - (1 - dot) * 34) * s)
                    .opacity(Double(min(max(dot * 3, 0), 1)))
                }
                .opacity(detail)
            }
            .frame(width: 200 * s, height: 200 * s)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Lines start one after another but overlap, finishing together at `progress` = 1.
    private func stagger(_ progress: CGFloat, index: Int, count: Int) -> CGFloat {
        let spread: CGFloat = 0.45
        let start = spread * CGFloat(index) / CGFloat(max(count - 1, 1))
        return min(max((progress - start) / (1 - spread), 0), 1)
    }
}

/// A straight line given in the logo's 200-unit coordinates.
private struct UnitLine: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 200
        var p = Path()
        p.move(to: CGPoint(x: from.x * s, y: from.y * s))
        p.addLine(to: CGPoint(x: to.x * s, y: to.y * s))
        return p
    }
}

/// "M72 74 A28 28 0 1 1 116 97 Q100 106 100 124": an arc round centre (100, 74),
/// clockwise from the left over the top, then a curve down into the stem.
private struct QuestionMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 200
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var p = Path()
        let start = CGFloat.pi                       // (72, 74)
        let end = 2 * CGFloat.pi + atan2(23, 16)     // (116, 97)
        let steps = 48
        for i in 0...steps {
            let a = start + (end - start) * CGFloat(i) / CGFloat(steps)
            let point = pt(100 + 28 * cos(a), 74 + 28 * sin(a))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.addQuadCurve(to: pt(100, 124), control: pt(100, 106))
        return p
    }
}

/// The logo screen's fixed layout: the logo tile with a soft shadow and "Chord ID"
/// under it. The static launch image is a rendering of this with nothing drawn on
/// the tile, and the animated screen places it at exactly the same spot, so the
/// hand-over from iOS's launch screen doesn't jump.
struct LaunchCanvas: View {
    var lines: CGFloat = 0
    var mark: CGFloat = 0
    var dot: CGFloat = 0
    var detail: Double = 1

    /// Taller than the content so the block sits a little above centre, as in the mockup.
    static let size = CGSize(width: 280, height: 364)
    static let tileSize: CGFloat = 168

    var body: some View {
        VStack(spacing: 0) {
            LogoMark(lines: lines, mark: mark, dot: dot, detail: detail)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .shadow(color: .black.opacity(0.08), radius: 22, y: 10)
                .padding(.top, 30)
            Text("Chord ID")
                // Fixed size so it matches the launch image pixel for pixel.
                .font(.custom("BricolageGrotesque-ExtraBold", fixedSize: 36))
                .tracking(-1.2)
                .foregroundStyle(Theme.text)
                .padding(.top, 26)
            Spacer(minLength: 0)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}
