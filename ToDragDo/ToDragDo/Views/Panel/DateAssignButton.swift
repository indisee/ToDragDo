import SwiftUI
import ToDragDoCore
import ToDragDoUI

/// Calendar button shown inside the expanded-row floating action menu.
/// Tapping reveals a popover with a graphical date picker; picking a
/// date assigns it to the item and routes the item to the right folder
/// (today / tomorrow / limbo) via `Repository.setDueDate`.
struct DateAssignButton: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    let item: Item

    @State private var isPresented = false
    @State private var draft: Date = .now

    var body: some View {
        Button {
            draft = item.dueDate ?? Calendar.autoupdatingCurrent.startOfDay(for: .now)
            isPresented.toggle()
        } label: {
            Image(systemName: item.dueDate == nil ? "calendar.badge.plus" : "calendar")
                .font(.system(size: theme.bodySize, weight: .medium))
                .foregroundStyle(item.dueDate == nil ? .secondary : theme.accent)
        }
        .buttonStyle(.plain)
        .help(item.dueDate == nil ? "Assign date" : "Change date")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            picker
        }
    }

    private var picker: some View {
        VStack(spacing: 8) {
            DatePicker(
                "",
                selection: $draft,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .fixedSize()

            HStack(spacing: 8) {
                if item.dueDate != nil {
                    Button("Clear", role: .destructive) {
                        apply(nil)
                    }
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("Cancel") { isPresented = false }
                    .controlSize(.small)
                Button("Set") { apply(draft) }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
    }

    private func apply(_ date: Date?) {
        let id = item.id
        Task {
            try? await repository.setDueDate(id: id, to: date)
        }
        isPresented = false
    }
}
