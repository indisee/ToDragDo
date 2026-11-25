import SwiftUI

extension View {
    /// Chrome for a settings pane: a grouped form inside the macOS
    /// Settings window, an inline-titled navigation page on iOS.
    func settingsPaneStyle(title: LocalizedStringKey) -> some View {
        #if os(macOS)
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
        #else
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

enum PlatformCopy {
    #if os(macOS)
    static let systemName = "macOS"
    #else
    static let systemName = "iOS"
    #endif
}
