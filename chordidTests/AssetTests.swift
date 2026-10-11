import Testing
import UIKit
@testable import chordid

struct AssetTests {
    /// Colour of the pixel at (x, y) in a 200×200 rendering of the logo (SVG coordinates).
    private func pixel(_ image: UIImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        guard let cg = rendered.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return (-1, -1, -1) }
        let i = y * cg.bytesPerRow + x * (cg.bitsPerPixel / 8)
        // Rendered images are BGRA on iOS.
        return (Int(bytes[i + 2]), Int(bytes[i + 1]), Int(bytes[i]))
    }

    @Test func logoAssetRendersFromTheSVG() throws {
        let logo = try #require(UIImage(named: "Logo"))
        let dot = pixel(logo, 100, 151)          // blue dot: #2B5BFF
        #expect(abs(dot.r - 0x2B) < 12 && abs(dot.g - 0x5B) < 12 && abs(dot.b - 0xFF) < 12, "dot \(dot)")
        let background = pixel(logo, 100, 20)    // white tile
        #expect(background.r > 245 && background.g > 245 && background.b > 245)
        let mark = pixel(logo, 100, 120)         // question mark stem: #121417
        #expect(mark.r < 40 && mark.g < 40 && mark.b < 40, "mark \(mark)")
    }
}
