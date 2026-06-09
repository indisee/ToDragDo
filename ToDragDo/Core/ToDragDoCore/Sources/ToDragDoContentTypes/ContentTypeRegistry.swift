import Observation
import SwiftUI
import ToDragDoCore

/// Central lookup that maps an attachment / item type identifier to the
/// provider that renders it. Apps build one at launch, register every
/// known provider (the four built-ins land automatically; extension
/// providers `register(_:)` against the singleton), and inject it into
/// the SwiftUI environment so views can resolve without threading the
/// registry through every initializer.
@MainActor
@Observable
public final class ContentTypeRegistry {
    private var providers: [any ContentTypeProvider] = []
    private let fallback: any ContentTypeProvider

    public init(fallback: any ContentTypeProvider = FallbackProvider()) {
        self.fallback = fallback
    }

    /// Registers a provider. Order matters: providers are tried in
    /// registration order, first match wins.
    public func register(_ provider: any ContentTypeProvider) {
        providers.append(provider)
    }

    /// Convenience: registers all four shipped-in-box providers. Hosts
    /// typically call this at launch, then `register(_:)` additional
    /// providers afterwards.
    public func registerBuiltIns() {
        register(TextProvider())
        register(URLProvider())
        register(FileURLProvider())
        register(ImageProvider())
    }

    public func resolve(attachment: Attachment) -> any ContentTypeProvider {
        for provider in providers where provider.handles(attachment: attachment) {
            return provider
        }
        return fallback
    }

    public func resolve(itemTypeIdentifier: String) -> any ContentTypeProvider {
        for provider in providers where provider.handles(itemTypeIdentifier: itemTypeIdentifier) {
            return provider
        }
        return fallback
    }

    public var registeredIdentifiers: [String] {
        providers.map(\.identifier)
    }
}

/// Last-resort provider for content the host registered nothing for.
/// Renders a generic chip + empty full view so the UI doesn't crash on
/// unknown types.
public final class FallbackProvider: ContentTypeProvider {
    public nonisolated let identifier = "fallback"
    public init() {}
    public nonisolated func handles(attachment _: Attachment) -> Bool { true }
    public nonisolated func handles(itemTypeIdentifier _: String) -> Bool { true }
    public nonisolated func badge(forItemTypeIdentifier _: String) -> ContentBadge? {
        ContentBadge(symbol: "=", color: .secondary)
    }
    public nonisolated func chipBadge(for _: Attachment) -> ContentBadge? {
        ContentBadge(symbol: "=", color: .secondary)
    }
    public func fullView(for _: Attachment) -> AnyView { AnyView(EmptyView()) }
}

// MARK: - SwiftUI environment

@MainActor
private struct ContentTypeRegistryKey: @preconcurrency EnvironmentKey {
    static let defaultValue: ContentTypeRegistry = {
        let registry = ContentTypeRegistry()
        registry.registerBuiltIns()
        return registry
    }()
}

public extension EnvironmentValues {
    /// Registry resolved from the SwiftUI environment. Host injects the
    /// real one with `.environment(\.contentTypes, registry)`; preview
    /// code that doesn't bother gets the default with built-ins.
    @MainActor var contentTypes: ContentTypeRegistry {
        get { self[ContentTypeRegistryKey.self] }
        set { self[ContentTypeRegistryKey.self] = newValue }
    }
}
