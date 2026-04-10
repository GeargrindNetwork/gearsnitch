import SwiftUI

// MARK: - GearSnitch Color Palette

extension Color {

    // MARK: Brand

    /// Emerald-500 — primary brand accent
    static let gsEmerald = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)

    /// Cyan-400 — secondary accent / gradient endpoint
    static let gsCyan = Color(red: 34 / 255, green: 211 / 255, blue: 238 / 255)

    // MARK: Surfaces

    /// Pure black background
    static let gsBackground = Color.black

    /// Zinc-900 — card / container background
    static let gsSurface = Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255)

    /// Zinc-800 — raised surface (popovers, sheets)
    static let gsSurfaceRaised = Color(red: 39 / 255, green: 39 / 255, blue: 42 / 255)

    // MARK: Text

    /// Zinc-100 — primary text
    static let gsText = Color(red: 244 / 255, green: 244 / 255, blue: 245 / 255)

    /// Zinc-400 — secondary / muted text
    static let gsTextSecondary = Color(red: 161 / 255, green: 161 / 255, blue: 170 / 255)

    // MARK: Borders

    /// Zinc-700 — default border color
    static let gsBorder = Color(red: 63 / 255, green: 63 / 255, blue: 70 / 255)

    // MARK: Semantic

    /// Green-500 — success states
    static let gsSuccess = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)

    /// Amber-500 — warning states
    static let gsWarning = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)

    /// Red-500 — error / danger states
    static let gsDanger = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)

    // MARK: Gradients

    /// Standard brand gradient (emerald → cyan)
    static let gsBrandGradient = LinearGradient(
        colors: [gsEmerald, gsCyan],
        startPoint: .leading,
        endPoint: .trailing
    )
}
