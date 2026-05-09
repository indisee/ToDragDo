import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Private UTType for in-app item-row reorder drags. External drags
    /// (browser links, files, images, plain text) never advertise this,
    /// so a `.dropDestination(for: ItemDragPayload.self)` won't intercept
    /// them — which lets a sibling `.onDrop(of: [.url, .fileURL, …])` on
    /// the same row handle external attachments cleanly.
    static let toDragDoItemID = UTType(exportedAs: "com.todragdo.item-id")
}

struct ItemDragPayload: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .toDragDoItemID)
    }
}
