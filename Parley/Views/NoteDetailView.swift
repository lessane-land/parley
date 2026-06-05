import SwiftUI
import SwiftData

/// The editor pane: title + typed notes everywhere, plus a handwriting canvas
/// on iPad. iPhone and Mac gracefully stay typed-only.
struct NoteDetailView: View {
    /// `@Bindable` lets us make two-way bindings (`$note.title`) to the
    /// properties of a reference type — our `@Model` `Note`. Because the note is
    /// a tracked SwiftData object, typing/drawing mutates the stored object
    /// directly and SwiftData autosaves it. No "Save" button needed.
    @Bindable var note: Note

    @Environment(ThemeManager.self) private var themeManager

    private var theme: Theme { themeManager.theme }
    private var density: Density { themeManager.density }

    /// Recreating the canvas (via `.id`) is how we force it to reload — used by
    /// "Clear" to wipe the strokes.
    @State private var canvasID = UUID()
    @State private var showClearDrawing = false

    /// Handwriting is an iPad feature. PencilKit also runs on iPhone, but per the
    /// product plan the phone stays typed-only for now.
    private var showsHandwriting: Bool {
        guard themeManager.handwriting else { return false }   // Settings toggle
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("Title", text: $note.title)
                    .font(theme.titleFont(26, relativeTo: .title))
                    .tracking(theme.titleTracking)
                    .foregroundStyle(theme.ink)
                    .textFieldStyle(.plain)

                Text(note.createdAt, format: .dateTime.weekday().month().day().hour().minute())
                    .font(theme.monoFont(11))
                    .foregroundStyle(theme.inkFaint)
            }

            // A hairline that takes the mood's line color and thickness.
            Rectangle()
                .fill(theme.line)
                .frame(height: theme.borderWidth)

            typedNotes
                .padding(.leading, 16)
                .overlay(alignment: .leading) {
                    // Notebook margin rule (the design's .pk-notes::before).
                    Rectangle().fill(theme.accentLine).frame(width: 1)
                }
                // On iPad the typed notes share the screen with the canvas, so
                // cap their height; elsewhere they fill the pane.
                .frame(maxHeight: showsHandwriting ? 220 : .infinity)

            #if os(iOS)
            if showsHandwriting {
                handwriting
            }
            #endif
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper)
        .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("Clear handwriting?", isPresented: $showClearDrawing, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                note.drawing = nil
                canvasID = UUID()   // rebuild the canvas empty
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Pencil strokes on this note. Your typed text is kept.")
        }
    }

    private var typedNotes: some View {
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

    #if os(iOS)
    private var handwriting: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HANDWRITING")
                    .font(theme.monoFont(11))
                    .tracking(1.2)
                    .foregroundStyle(theme.inkFaint)
                Spacer()
                Button {
                    showClearDrawing = true
                } label: {
                    Label("Clear", systemImage: "eraser")
                        .font(.caption)
                }
                .tint(theme.accent)
                .disabled(note.drawing == nil)
            }

            DrawingCanvas(data: $note.drawing, inkColor: theme.ink)
                .id(canvasID)
                .background(theme.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .strokeBorder(theme.edge, lineWidth: theme.borderWidth)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    #endif
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
