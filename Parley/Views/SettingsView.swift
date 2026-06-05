import SwiftUI

/// Appearance settings — mirrors the design's Tweaks panel: a base mood plus
/// accent, highlight, paper warmth, type face, density, and a handwriting
/// toggle. Used as a sheet on iOS/iPadOS and the macOS `Settings` window (Cmd-,).
struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager

    private var cfg: MoodConfig { themeManager.mood.config }

    var body: some View {
        // SwiftUI gotcha: to get two-way `$bindings` out of an `@Observable`
        // object that arrived via `@Environment`, re-wrap it with `@Bindable`.
        @Bindable var manager = themeManager

        Form {
            Section {
                ForEach(Mood.allCases) { mood in
                    Button {
                        withAnimation(.snappy) { manager.mood = mood }
                    } label: {
                        MoodRow(mood: mood, isSelected: mood == manager.mood)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Mood")
            } footer: {
                Text("Moods restyle the whole app — color, type, and shape.")
            }

            Section("Accent") {
                SwatchRow(
                    options: cfg.accents,
                    selected: manager.accentHex ?? cfg.accentDefault
                ) { manager.accentHex = $0 }
            }

            if let highlights = cfg.highlights {
                Section("Highlight") {
                    SwatchRow(
                        options: highlights,
                        selected: manager.highlightHex ?? (cfg.highlightDefault ?? "")
                    ) { manager.highlightHex = $0 }
                }
            }

            if cfg.hasWarmth {
                Section("Paper warmth") {
                    Slider(value: $manager.warmth, in: 0...100) {
                        Text("Warmth")
                    } minimumValueLabel: {
                        Image(systemName: "snowflake").foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Image(systemName: "sun.max").foregroundStyle(.secondary)
                    }
                }
            }

            if cfg.faceOptions.count > 1 {
                Section(cfg.faceLabel) {
                    Picker(cfg.faceLabel, selection: Binding(
                        get: { manager.faceName ?? cfg.faceDefault },
                        set: { manager.faceName = $0 }
                    )) {
                        ForEach(cfg.faceOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Text size") {
                Picker("Text size", selection: $manager.density) {
                    ForEach(Density.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                Toggle("Handwriting strokes", isOn: $manager.handwriting)
            } footer: {
                Text("Shows the Apple Pencil canvas on iPad notes.")
            }

            Section("Preview") {
                ThemePreviewCard(theme: manager.theme, density: manager.density)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
    }
}

/// A horizontal row of selectable color swatches (accent / highlight).
private struct SwatchRow: View {
    let options: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options, id: \.self) { hex in
                let isOn = hex.caseInsensitiveCompare(selected) == .orderedSame
                Button {
                    onSelect(hex)
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: hex))
                        .frame(height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
                        )
                        .overlay {
                            if isOn {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(PK.isLight(hex) ? .black : .white)
                            }
                        }
                        .overlay {
                            if isOn {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.primary, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Design review")
                .font(theme.titleFont(20, relativeTo: .title3))
                .tracking(theme.titleTracking)
                .textCase(theme.titleUppercase ? .uppercase : nil)
                .foregroundStyle(theme.ink)

            Text("Shipped the new onboarding. Decision: defer CloudKit until enrolled — owner follows up Friday.")
                .font(theme.bodyFont(density.bodySize))
                .foregroundStyle(theme.ink2)
                .lineSpacing(density.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Circle().fill(theme.rec).frame(width: 7, height: 7)
                Text("REC 12:04")
                    .font(theme.monoFont(11, relativeTo: .caption2))
                    .foregroundStyle(theme.inkSoft)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard(theme)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
    }
    .environment(ThemeManager())
}
