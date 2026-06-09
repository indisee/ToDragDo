import SwiftUI
import ToDragDoCore

/// Phase 1 placeholder. Phase 2 replaces this with the real folder view
/// (input bar + filterable list of items).
struct FolderTabStub: View {
    @Environment(Repository.self) private var repository

    let folder: Folder

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("\(folder.title) — \(itemCount)")
                    .font(.title3.weight(.semibold))
                Text("Real folder view lands in Phase 2.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(folder.title)
        }
    }

    private var itemCount: Int {
        repository.items[folder]?.count ?? 0
    }
}

private extension Folder {
    var title: String {
        switch self {
        case .today:    "Today"
        case .tomorrow: "Tomorrow"
        case .libmo:    "Limbo"
        case .done:     "Done"
        }
    }
}
