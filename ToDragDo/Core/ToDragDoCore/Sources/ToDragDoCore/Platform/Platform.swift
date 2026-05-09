import Foundation

public enum Platform: String, Sendable, Hashable {
    case macOS
    case iOS
    case windows
    case linux
    case unknown

    public static var current: Platform {
        #if os(macOS)
        return .macOS
        #elseif os(iOS)
        return .iOS
        #elseif os(Windows)
        return .windows
        #elseif os(Linux)
        return .linux
        #else
        return .unknown
        #endif
    }
}
