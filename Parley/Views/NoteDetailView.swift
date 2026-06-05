import SwiftUI
import SwiftData

/// The editor pane: edit a note's title and body in place.
struct NoteDetailView: View {
    /// `@Bindable` lets us make two-way bindings (`$note.title`) to the
    /// properties of a reference type — here our `@Model` `Note`. Because the
    /// note is a tracked SwiftData object, typing into these fields mutates the
    /// stored object directly and SwiftData autosaves it. No "Save" button needed.
    @Bindable var note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $note.title)
                .font(.title.bold())
                .textFieldStyle(.plain)

            Divider()

            TextEditor(text: $note.body)
                .font(.body)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    // SwiftUI's TextEditor has no placeholder, so we fake one.
                    if note.body.isEmpty {
                        Text("Start typing your notes…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding()
        .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
        // Title display mode is an iOS/iPadOS-only modifier; PencilKit aside,
        // this `#if` is the canonical way to handle the few genuinely
        // platform-specific bits in a multiplatform SwiftUI codebase.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    // Build a throwaway in-memory note to preview the editor in isolation.
    let container = try! ModelContainer(
        for: Note.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let note = Note(title: "Kickoff sync", body: "Discussed Phase 0 scope.")
    container.mainContext.insert(note)
    return NavigationStack {
        NoteDetailView(note: note)
    }
    .modelContainer(container)
}
