import SwiftUI
import CoreText

/// Colours, type and shapes from the design spec. Light mode only for now.
enum Theme {
    static let background = Color(hex: 0xF4F5F7)
    static let card = Color.white
    static let text = Color(hex: 0x121417)
    static let secondaryText = Color(hex: 0x5C6370)
    static let tertiaryText = Color(hex: 0xA0A6B1)
    static let accent = Color(hex: 0x2B5BFF)
    static let accentSoft = Color(hex: 0xE8EDFF)
    static let searchFill = Color(hex: 0xE9EBEF)
    static let divider = Color(hex: 0xE6E8EC)
    static let warning = Color(hex: 0xC2410C)

    // Fretboard
    static let stringColor = Color(hex: 0x9AA0AB)
    static let fretLine = Color(hex: 0xE1E4EA)
    static let inlay = Color(hex: 0xE3E6EB)
    static let muteMark = Color(hex: 0x3A3F47)

    static let cornerRadius: CGFloat = 24
    static let minTouch: CGFloat = 44
    static let sideMargin: CGFloat = 24
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Bricolage Grotesque, scaled with Dynamic Type.
enum BrandFont {
    enum Weight: String {
        case regular = "Regular", medium = "Medium", semibold = "SemiBold", bold = "Bold", extraBold = "ExtraBold"
    }

    static func font(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("BricolageGrotesque-\(weight.rawValue)", size: size, relativeTo: style)
    }

    /// Registers the bundled .ttf files so `Font.custom` can find them.
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    static let brandLargeTitle = BrandFont.font(36, .extraBold, relativeTo: .largeTitle)
    static let brandChordName = BrandFont.font(46, .extraBold, relativeTo: .largeTitle)
    static let brandTitle = BrandFont.font(22, .bold, relativeTo: .title2)
    static let brandHeadline = BrandFont.font(20, .bold, relativeTo: .title3)
    static let brandBody = BrandFont.font(17, .medium, relativeTo: .body)
    static let brandBodySemibold = BrandFont.font(17, .semibold, relativeTo: .body)
    static let brandBodyBold = BrandFont.font(17, .bold, relativeTo: .body)
    static let brandSubheadline = BrandFont.font(15, .medium, relativeTo: .subheadline)
    static let brandCaption = BrandFont.font(13, .semibold, relativeTo: .footnote)
}

/// White rounded card used across screens.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// Large pill-ish button used for Strum / Save.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primaryDark, secondary, accent }
    var kind: Kind

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .secondary ? .brandBodySemibold : .brandBodyBold)
            .foregroundStyle(kind == .secondary ? Theme.text : .white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primaryDark: Theme.text
        case .secondary: Theme.card
        case .accent: Theme.accent
        }
    }
}
