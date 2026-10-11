import SwiftUI
import Testing
import UIKit
@testable import chordid

/// Draws a CGImage into an RGBA buffer of the given size so two images can be compared.
private func rgba(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    data.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return data
}

/// Mean absolute difference per channel (0…255) and the share of pixels that differ by more than 24.
private func compare(_ a: [UInt8], _ b: [UInt8]) -> (mean: Double, badShare: Double) {
    var total = 0, bad = 0
    for p in stride(from: 0, to: a.count, by: 4) {
        var worst = 0
        for c in 0..<4 {
            let d = abs(Int(a[p + c]) - Int(b[p + c]))
            total += d
            worst = max(worst, d)
        }
        if worst > 24 { bad += 1 }
    }
    return (Double(total) / Double(a.count), Double(bad) / Double(a.count / 4))
}

struct LaunchTests {
    /// Regenerates the static launch image from the live first frame, rendered on iOS
    /// so text smoothing matches exactly. Runs only when the marker file exists, and
    /// prints where the PNGs were written (macOS doesn't let the simulator write into
    /// the project folder), ready to copy into LaunchLogo.imageset:
    ///
    ///   touch chordidTests/.regenerate-launch-image
    ///   xcodebuild test … -only-testing:chordidTests/LaunchTests/writeLaunchImageIfRequested
    ///   cp <printed dir>/LaunchLogo@*.png chordid/Assets.xcassets/LaunchLogo.imageset/
    ///   rm chordidTests/.regenerate-launch-image
    @Test func writeLaunchImageIfRequested() throws {
        let marker = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".regenerate-launch-image")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let dir = FileManager.default.temporaryDirectory
        for scale in [2, 3] {
            let renderer = ImageRenderer(content: LaunchCanvas())
            renderer.scale = CGFloat(scale)
            let image = try #require(renderer.uiImage?.pngData())
            try image.write(to: dir.appendingPathComponent("LaunchLogo@\(scale)x.png"))
        }
        print("LAUNCHIMAGEDIR|\(dir.path)")
    }

    @Test func launchStyleChoice() {
        #expect(LaunchStyle.choose(hasLaunchedBefore: false, reduceMotion: false) == .full)
        #expect(LaunchStyle.choose(hasLaunchedBefore: true, reduceMotion: false) == .quick)
        #expect(LaunchStyle.choose(hasLaunchedBefore: false, reduceMotion: true) == .still)
        #expect(LaunchStyle.choose(hasLaunchedBefore: true, reduceMotion: true) == .still)
        #expect(LaunchStyle.full.holdSeconds == 1.2)
    }

    /// The static launch screen and the animated screen's first frame must be the
    /// same picture, or the hand-over would visibly jump.
    @Test func launchImageMatchesFirstFrame() throws {
        let bundled = try #require(UIImage(named: "LaunchLogo")?.cgImage)
        let renderer = ImageRenderer(content: LaunchCanvas())
        renderer.scale = 3
        let live = try #require(renderer.cgImage)
        let w = Int(LaunchCanvas.size.width * 3), h = Int(LaunchCanvas.size.height * 3)
        #expect(bundled.width == w && bundled.height == h)
        let result = compare(rgba(bundled, width: w, height: h), rgba(live, width: w, height: h))
        print(String(format: "LAUNCH|first frame vs launch image|mean diff %.3f/255|pixels off by >24: %.4f%%", result.mean, result.badShare * 100))
        #expect(result.mean < 0.5)
        #expect(result.badShare < 0.0005)
    }

    /// The hand-drawn shapes must match the original SVG asset.
    @Test func animatedLogoMatchesSVG() throws {
        let svg = try #require(UIImage(named: "Logo"))
        let size = CGSize(width: 200, height: 200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let reference = try #require(UIGraphicsImageRenderer(size: size, format: format).image { _ in
            svg.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage)
        let renderer = ImageRenderer(content: LogoMark().frame(width: 200, height: 200))
        renderer.scale = 2
        let drawn = try #require(renderer.cgImage)
        let result = compare(rgba(reference, width: 400, height: 400), rgba(drawn, width: 400, height: 400))
        print(String(format: "LAUNCH|shapes vs SVG|mean diff %.3f/255|pixels off by >24: %.3f%%", result.mean, result.badShare * 100))
        // Only the tile's corner curve differs slightly (continuous vs circular rounding).
        #expect(result.mean < 2.0)
        #expect(result.badShare < 0.01)
    }
}
