import CoreGraphics

/// Small size tweaks where iOS needs slightly larger glyphs than macOS
/// for legibility and touch. Kept in one place so shared views don't
/// sprinkle `#if os` around every literal.
enum PlatformMetrics {
    #if os(macOS)
    static let iconStripGlyph: CGFloat = 10
    static let iconStripFrame: CGFloat = 14
    static let badgeDay: CGFloat = 11
    static let badgeMonth: CGFloat = 9
    static let badgeDateWidth: CGFloat = 24
    static let badgeSymbolWidth: CGFloat = 18
    static let pillHorizontal: CGFloat = 10
    static let pillVertical: CGFloat = 4
    #else
    static let iconStripGlyph: CGFloat = 11
    static let iconStripFrame: CGFloat = 16
    static let badgeDay: CGFloat = 12
    static let badgeMonth: CGFloat = 10
    static let badgeDateWidth: CGFloat = 26
    static let badgeSymbolWidth: CGFloat = 20
    static let pillHorizontal: CGFloat = 12
    static let pillVertical: CGFloat = 6
    #endif
}
