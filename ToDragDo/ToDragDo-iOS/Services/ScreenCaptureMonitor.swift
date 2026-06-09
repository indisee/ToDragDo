import Foundation
import Observation
import UIKit

/// Tracks `UIScreen.isCaptured` for the privacy-during-capture feature
/// (`AppSettings.hideFromScreenSharing`). Replaces the macOS
/// `NSWindow.sharingType = .none` shim — iOS has no per-window opt-out,
/// so we hide the list inside the app instead.
///
/// Observes `UIScreen.capturedDidChangeNotification` on the main screen
/// and republishes its `isCaptured` as a SwiftUI-observable property.
/// `FolderTabView` reads this and swaps the list for a caption when
/// capture is active.
@MainActor
@Observable
final class ScreenCaptureMonitor {
    private(set) var isCaptured: Bool

    @ObservationIgnored private var observation: NSObjectProtocol?

    init() {
        self.isCaptured = UIScreen.main.isCaptured
        self.observation = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Notification can arrive off-main; bounce through MainActor.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isCaptured = UIScreen.main.isCaptured
            }
        }
    }

    deinit {
        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }
    }
}
