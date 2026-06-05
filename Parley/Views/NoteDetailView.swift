import SwiftUI
import SwiftData

/// The editor pane: edit a note's title and body in place, styled by the mood.
struct NoteDetailView: View {
    /// `@Bindable` lets us make two-way bindings (`$note.title`) to the
    /// properties of a reference type — our `@Model` `Note`. Because the note is
    /// a tracked SwiftData object, typing into these fields mutates the stored
    /// object directly and SwiftData autosaves it. No "Save" button needed.
    @Bindable var note: Note

    @Environment(ThemeManager.self) private var themeManager

    private var theme: Theme { themeManager.theme }
    private var density: Density { themeManager.density }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $note.title)
                .font(theme.titleFont(26, relativeTo: .title))
                .tracking(theme.titleTracking)
                .foregroundStyle(theme.ink)
                .textFieldStyle(.plain)

            // A hairline that takes the mood's line color and thickness.
            Rectangle()
                .fill(theme.line)
                .frame(height: theme.borderWidth)

            TextEditor(text: $note.body)
                .font(theme.bodyFont(density.bodySize))
                .foregroundStyle(theme.ink2)
                .lineSpacing(density.lineSpacing)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    // SwiftUI's TextEditor has no placeholder, so we fake one.
                    if note.body.isEmpty {
                        Text("Start typing your notes…")
                            .font(theme.bodyFont(density.bodySize))
                            .foregroundStyle(theme.inkFaint)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper)
        .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
        // Title display mode is iOS/iPadOS-only; the `#if` is the canonical way
        // to handle the few genuinely platform-specific bits in shared SwiftUI.
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
    .environment(ThemeManager())
}
