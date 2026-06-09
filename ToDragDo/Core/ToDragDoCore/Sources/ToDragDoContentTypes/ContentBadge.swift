import SwiftUI

/// Visual descriptor for the leading per-row badge a provider renders
/// when an item's primary content is of that type. Keeps the registry
/// API pure data — actual badge styling lives in `TypeBadge` (the
/// caller), which combines this with theme metrics.
public struct ContentBadge: Sendable, Hashable {
    /// Single-character monospaced glyph (`=`, `+`, `0`, `■`, `▤`, …).
    public var symbol: String
    /// Foreground color the host should tint the symbol with. Encoded as
    /// the small `Role` enum so the registry stays SwiftUI-light and the
    /// host can resolve to theme colors.
    public var color: Role

    public init(symbol: String, color: Role) {
        self.symbol = symbol
        self.color = color
    }

    public enum Role: Sendable, Hashable {
        case secondary
        case accent
        case blue
        case green
        case orange
    }
}

public extension Color {
    /// Maps `ContentBadge.Role` to a stock SwiftUI color. Callers that
    /// want theme-aware colors should branch on the role instead of
    /// reaching for this convenience.
    init(_ role: ContentBadge.Role) {
        switch role {
        case .secondary: self = .secondary
        case .accent:    self = .accentColor
        case .blue:      self = .blue
        case .green:     self = .green
        case .orange:    self = .orange
        }
    }
}
