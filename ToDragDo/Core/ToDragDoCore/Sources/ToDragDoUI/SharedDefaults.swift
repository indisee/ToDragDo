import Foundation
#if os(iOS)
import ToDragDoIntents
#endif

/// The `UserDefaults` app state lives in: the App Group suite on iOS (so
/// the widget and share extension see the same values), the app's own
/// defaults on macOS.
public enum SharedDefaults {
    public static var store: UserDefaults {
        #if os(iOS)
        AppGroup.defaults
        #else
        .standard
        #endif
    }
}
