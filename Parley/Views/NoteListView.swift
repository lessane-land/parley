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
                    NoteRow(note: note, theme: theme, selected: note == selection)
                        .tag(note)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                }
                .onDelete(perform: deleteNotes)
            }
            .listStyle(.plain)
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
                    ThemedEmptyState(
                        theme: theme,
                        icon: "note.text",
                        title: "No Notes",
                        message: "Tap the compose button to create your first note."
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
                ThemedEmptyState(
                    theme: theme,
                    icon: "sidebar.left",
                    title: "No Note Selected",
                    message: "Select a note from the list, or create a new one."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.paper)
            }
        }
        // Accent (selection, toolbar buttons) follows the mood, in addition to
        // the app-level tint — belt and suspenders so the navigation chrome
        // picks it up reliably.
        .tint(theme.accent)
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

/// A single note card in the sidebar — the design's `.pk-card`: title, a short
/// snippet, and a date, wrapped in the mood's card shape.
private struct NoteRow: View {
    let note: Note
    let theme: Theme
    let selected: Bool

    /// First non-empty line of the body, for the card snippet.
    private var snippet: String {
        note.body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.title.isEmpty ? "New Note" : note.title)
                .font(theme.titleFont(16, relativeTo: .headline))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(theme.ink)
                .lineLimit(1)

            if !snippet.isEmpty {
                Text(snippet)
                    .font(theme.bodyFont(12.5))
                    .foregroundStyle(theme.inkSoft)
                    .lineLimit(2)
            }

            Text(note.createdAt, format: .dateTime.month().day().hour().minute())
                .font(theme.monoFont(10.5, relativeTo: .caption2))
                .foregroundStyle(theme.inkFaint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard(theme, fill: selected ? theme.accentTint : theme.paperRaised, selected: selected)
    }
}

/// A mood-styled empty state. We render our own (instead of
/// `ContentUnavailableView`) so the mood's fonts and colors are visible even
/// when there are no notes — otherwise an empty screen looks unthemed.
private struct ThemedEmptyState: View {
    let theme: Theme
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(theme.accent)
            Text(title)
                .font(theme.titleFont(22, relativeTo: .title2))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(theme.ink)
            Text(message)
                .font(theme.bodyFont(14))
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(24)
    }
}

#Preview {
    NoteListView()
        // Previews need their own container and theme manager.
        .modelContainer(for: Note.self, inMemory: true)
        .environment(ThemeManager())
}
