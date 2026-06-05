import SwiftUI
import SwiftData

/// The master/detail screen: list of notes on the left, editor on the right.
struct NoteListView: View {
    /// The `ModelContext` SwiftData injected from `.modelContainer`. It's the
    /// handle we use to insert and delete notes; saves are automatic.
    @Environment(\.modelContext) private var context

    /// The shared appearance state (injected in `ParleyApp`).
    @Environment(ThemeManager.self) private var themeManager

    /// `@Query` is SwiftData's live-fetch property wrapper. It runs the fetch,
    /// hands us the results, and re-renders automatically when matching data
    /// changes. We sort newest-first.
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    /// Which note the detail pane is showing. `Note?` because nothing may be
    /// selected. The sidebar `List` binds its selection to this.
    @State private var selection: Note?

    /// iOS/iPadOS: whether the settings sheet is showing. (macOS uses Cmd-,.)
    @State private var showingSettings = false

    private var theme: Theme { themeManager.theme }

    var body: some View {
        NavigationSplitView {
            // SIDEBAR
            List(selection: $selection) {
                ForEach(notes) { note in
                    NoteRow(note: note, theme: theme)
                        .tag(note)
                        .listRowBackground(Color.clear)
                }
                .onDelete(perform: deleteNotes)
            }
            .scrollContentBackground(.hidden)   // let the mood's paper show through
            .background(theme.paperSunk)
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem {
                    Button(action: addNote) {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
                #if !os(macOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
                #endif
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.paper)
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
        #endif
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

/// A single sidebar row, styled with the current mood's tokens.
private struct NoteRow: View {
    let note: Note
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title.isEmpty ? "New Note" : note.title)
                .font(.system(.headline, design: theme.titleDesign).weight(theme.titleWeight))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            Text(note.createdAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(theme.inkFaint)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NoteListView()
        // Previews need their own container and theme manager.
        .modelContainer(for: Note.self, inMemory: true)
        .environment(ThemeManager())
}
