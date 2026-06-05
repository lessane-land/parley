import SwiftUI

/// Appearance settings: pick a mood and a text density. Used as a sheet on
/// iOS/iPadOS and inside the macOS `Settings` window (Cmd-,).
struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        // SwiftUI gotcha: to get two-way `$bindings` ($themeManager.density) out
        // of an `@Observable` object that arrived via `@Environment`, you re-wrap
        // it locally with `@Bindable`. This line is the documented idiom.
        @Bindable var themeManager = themeManager

        Form {
            Section {
                ForEach(Mood.allCases) { mood in
                    Button {
                        withAnimation(.snappy) { themeManager.mood = mood }
                    } label: {
                        MoodRow(mood: mood, isSelected: mood == themeManager.mood)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Mood")
            } footer: {
                Text("Moods restyle the whole app — color, type, and shape.")
            }

            Section("Text size") {
                Picker("Text size", selection: $themeManager.density) {
                    ForEach(Density.allCases) { density in
                        Text(density.name).tag(density)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Preview") {
                ThemePreviewCard(theme: themeManager.theme, density: themeManager.density)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
    }
}

/// One selectable mood: a mini swatch, the name + blurb, and a selection mark.
private struct MoodRow: View {
    let mood: Mood
    let isSelected: Bool

    var body: some View {
        let theme = mood.theme
        HStack(spacing: 14) {
            MoodSwatch(theme: theme)

            VStack(alignment: .leading, spacing: 2) {
                Text(mood.name).font(.headline)
                Text(mood.blurb).font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                .symbolRenderingMode(.hierarchical)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

/// A tiny rectangle that previews a mood's paper, accent, ink, border, and radius.
private struct MoodSwatch: View {
    let theme: Theme

    var body: some View {
        let radius: CGFloat = theme.cornerRadius == 0 ? 0 : 7
        RoundedRectangle(cornerRadius: radius)
            .fill(theme.paper)
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    Circle().fill(theme.accent).frame(width: 9, height: 9)
                    Capsule().fill(theme.ink).frame(width: 18, height: 4)
                }
                .padding(7)
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.edge, lineWidth: theme.borderWidth)
            )
            .frame(width: 56, height: 42)
    }
}

/// Live preview of how a note reads under the selected mood + density.
struct ThemePreviewCard: View {
    let theme: Theme
    let density: Density

    var body: some View {
        let radius = theme.cornerRadius

        VStack(alignment: .leading, spacing: 8) {
            Text("Design review")
                .font(.system(.title3, design: theme.titleDesign).weight(theme.titleWeight))
                .foregroundStyle(theme.ink)

            Text("Shipped the new onboarding. Decision: defer CloudKit until enrolled — owner follows up Friday.")
                .font(.system(size: density.bodySize, design: theme.noteDesign))
                .foregroundStyle(theme.ink2)
                .lineSpacing(density.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Circle().fill(theme.rec).frame(width: 7, height: 7)
                Text("REC 12:04")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.inkSoft)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paperRaised, in: RoundedRectangle(cornerRadius: radius))
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(theme.edge, lineWidth: theme.borderWidth)
        )
        .themeShadow(theme.shadow)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
    }
    .environment(ThemeManager())
}
