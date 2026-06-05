import SwiftUI
import SwiftData

/// The master/detail screen: list of notes on the left, editor on the right.
struct NoteListView: View {
    /// The `ModelContext` SwiftData injected from `.modelContainer`. It's the
    /// handle we use to insert and delete notes; saves are automatic.
    @Environment(\.modelContext) private var context

    /// `@Query` is SwiftData's live-fetch property wrapper. It runs the fetch,
    /// hands us the results, and — crucially — re-runs and re-renders the view
    /// automatically whenever matching data changes. No manual reload needed.
    /// We sort newest-first.
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    /// Which note the detail pane is showing. `Note?` because nothing may be
    /// selected. The sidebar `List` binds its selection to this.
    @State private var selection: Note?

    var body: some View {
        NavigationSplitView {
            // SIDEBAR
            List(selection: $selection) {
                ForEach(notes) { note in
                    // `.tag(note)` is what couples a row to the selection binding:
                    // selecting this row sets `selection` to this `Note`. It works
                    // because `@Model` types are `Hashable`/`Identifiable`.
                    NoteRow(note: note)
                        .tag(note)
                }
                .onDelete(perform: deleteNotes)
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem {
                    Button(action: addNote) {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
            .overlay {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "note.text",
                        description: Text("Tap the compose button to create your first note.")
                    )
                }
            }
        } detail: {
            // DETAIL
            if let selection {
                // `id:` forces SwiftUI to build a fresh editor when the selected
                // note changes, instead of reusing the previous one's state.
                NoteDetailView(note: selection)
                    .id(selection.id)
            } else {
                ContentUnavailableView(
                    "No Note Selected",
                    systemImage: "sidebar.left",
                    description: Text("Select a note from the list, or create a new one.")
                )
            }
        }
    }

    /// Insert a new empty note and immediately select it so the user can type.
    private func addNote() {
        let note = Note()
        context.insert(note)
        selection = note
    }

    /// `onDelete` hands us the offsets of the swiped/edited rows; map them back
    /// to model objects and delete. SwiftData persists the change automatically.
    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = notes[index]
            if note == selection { selection = nil }
            context.delete(note)
        }
    }
}

/// A single sidebar row. Pulled out into its own small view for readability.
private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title.isEmpty ? "New Note" : note.title)
                .font(.headline)
                .lineLimit(1)
            Text(note.createdAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NoteListView()
        // Previews need their own container. `inMemory: true` keeps the sample
        // data out of the real on-disk store.
        .modelContainer(for: Note.self, inMemory: true)
}
