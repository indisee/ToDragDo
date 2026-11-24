import OSLog

extension Logger {
    /// Unified-logging subsystem for every ToDragDo target.
    public nonisolated static let todragdoSubsystem = "com.turtle.todragdo"

    /// Logger under the shared ToDragDo subsystem.
    public nonisolated static func todragdo(category: String) -> Logger {
        Logger(subsystem: todragdoSubsystem, category: category)
    }
}
