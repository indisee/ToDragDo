import SwiftUI
import ToDragDoCore

/// Plug-in for one kind of attachment content (plain text, URL, file URL,
/// image, …). The host UI never switches on `Attachment.Kind` directly;
/// it resolves a provider through `ContentTypeRegistry` and asks the
/// provider to render badges + the full expanded view.
///
/// Per-provider auth (when applicable) lives in the host's `AuthStore`,
/// not here — providers stay pure rendering plus payload conversion.
@MainActor
public protocol ContentTypeProvider: AnyObject {
    /// Stable identifier — also the string written into
    /// `Item.typeIdentifier` when this provider's content is the item's
    /// primary content (`"text/plain"`, `"url"`, `"file"`, `"image"`,
    /// `"jira"`, …).
    nonisolated var identifier: String { get }

    /// Returns true if this provider claims the given attachment for its
    /// full view + chip badge. Providers are tried in registration order
    /// until one returns true.
    nonisolated func handles(attachment: Attachment) -> Bool

    /// Returns true if this provider owns rendering for the given item
    /// type identifier (for the leading row badge).
    nonisolated func handles(itemTypeIdentifier: String) -> Bool

    /// Leading row badge for an item whose `typeIdentifier` this provider
    /// owns. `nil` lets the registry fall back to the default badge.
    nonisolated func badge(forItemTypeIdentifier identifier: String) -> ContentBadge?

    /// Small chip glyph + tint shown in the attachment icon strip on a
    /// collapsed row. `nil` lets the host pick a generic look.
    nonisolated func chipBadge(for attachment: Attachment) -> ContentBadge?

    /// Full expanded-row view for one attachment. Type-erased so the
    /// registry can hold a heterogeneous list of providers.
    @ViewBuilder func fullView(for attachment: Attachment) -> AnyView
}

public extension ContentTypeProvider {
    nonisolated func badge(forItemTypeIdentifier _: String) -> ContentBadge? { nil }
    nonisolated func chipBadge(for _: Attachment) -> ContentBadge? { nil }
}
