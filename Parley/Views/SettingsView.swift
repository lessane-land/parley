import SwiftUI
import SwiftData

/// Settings — the design's slide-over: **Appearance** (mood, accent, type, size),
/// **Editor**, **AI & Summarize**, and **Transcription**. Styled with the mood
/// tokens like the rest of the app (not a native Form). Presented as a sheet on
/// iOS/iPadOS and the macOS `Settings` window (⌘,); the container supplies the
/// title bar, so this view is just the scrolling body.
struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.modelContext) private var context
    @Query(sort: \SpeakerProfile.name) private var speakerProfiles: [SpeakerProfile]

    private var theme: Theme { themeManager.theme }
    private var cfg: MoodConfig { themeManager.mood.config }

    var body: some View {
        ScrollView {
            // Split into sections so each stays within the ViewBuilder's 10-child
            // limit (and each re-wraps the manager as @Bindable for $bindings).
            VStack(alignment: .leading, spacing: 0) {
                appearanceSection(themeManager)
                editorSection(themeManager)
                aiSection(themeManager)
                transcriptionSection(themeManager)
                voicesSection(themeManager)
            }
            .padding(20)
        }
        .background(theme.paperSunk)
        .tint(theme.accent)
    }

    // MARK: Sections

    @ViewBuilder
    private func appearanceSection(_ manager: ThemeManager) -> some View {
        @Bindable var manager = manager
        sectionHeader("Appearance", first: true)
        fieldLabel("Mood")
        moodGrid(manager)
        fieldLabel("Accent")
        swatches(cfg.accents, selected: manager.accentHex ?? cfg.accentDefault) { manager.accentHex = $0 }

        Group {
            if let highlights = cfg.highlights {
                fieldLabel("Highlight")
                swatches(highlights, selected: manager.highlightHex ?? (cfg.highlightDefault ?? "")) {
                    manager.highlightHex = $0
                }
            }
            if cfg.hasWarmth {
                fieldLabel("Paper warmth")
                Slider(value: $manager.warmth, in: 0...100) {
                    Text("Warmth")
                } minimumValueLabel: {
                    Image(systemName: "snowflake")
                } maximumValueLabel: {
                    Image(systemName: "sun.max")
                }
                .tint(theme.accent)
                .foregroundStyle(theme.inkFaint)
                .padding(.bottom, 8)
            }
            if cfg.faceOptions.count > 1 {
                valueRow(cfg.faceLabel) {
                    Picker(cfg.faceLabel, selection: Binding(
                        // Clamp to a valid option — during a mood switch the stored
                        // face can momentarily not belong to the new mood's list.
                        get: {
                            let current = manager.faceName ?? cfg.faceDefault
                            return cfg.faceOptions.contains(current) ? current : cfg.faceDefault
                        },
                        set: { manager.faceName = $0 }
                    )) {
                        ForEach(cfg.faceOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .tint(theme.accentInk)
                }
            }
        }

        fieldLabel("Text size")
        Picker("Text size", selection: $manager.density) {
            ForEach(Density.allCases) { Text($0.name).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func editorSection(_ manager: ThemeManager) -> some View {
        @Bindable var manager = manager
        sectionHeader("Editor")
        toggleRow("Handwriting strokes",
                  desc: "Shows the Apple Pencil canvas on iPad notes.",
                  isOn: $manager.handwriting)
    }

    @ViewBuilder
    private func aiSection(_ manager: ThemeManager) -> some View {
        @Bindable var manager = manager
        sectionHeader("AI & Summarize")
        toggleRow("Auto-summarize when I end a meeting",
                  desc: "Draft is ready the moment you stop recording.",
                  isOn: $manager.autoSummarize)

        fieldLabel("Summary tone")
        Picker("Summary tone", selection: $manager.summaryTone) {
            ForEach(SummaryTone.allCases) { Text($0.name).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.bottom, 12)

        fieldLabel("Always extract")
        VStack(alignment: .leading, spacing: 0) {
            checkRow("Decisions", isOn: $manager.extractDecisions)
            checkRow("Action items", isOn: $manager.extractActionItems)
            checkRow("Open questions", isOn: $manager.extractOpenQuestions)
            checkRow("Key quotes", isOn: $manager.extractKeyQuotes)
        }

        lockedRow
    }

    @ViewBuilder
    private func transcriptionSection(_ manager: ThemeManager) -> some View {
        sectionHeader("Transcription")
        valueRow("Language") {
            Picker("Language", selection: Binding(
                get: { manager.transcriptionLanguage ?? "auto" },
                set: { manager.transcriptionLanguage = ($0 == "auto") ? nil : $0 }
            )) {
                Text("Automatic").tag("auto")
                ForEach(TranscriptionLanguages.options, id: \.code) { Text($0.name).tag($0.code) }
            }
            .labelsHidden()
            .tint(theme.accentInk)
        }
        Text("Automatic follows your device's preferred languages. Each recording is transcribed in a single language.")
            .font(theme.bodyFont(11.5))
            .foregroundStyle(theme.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    @ViewBuilder
    private func voicesSection(_ manager: ThemeManager) -> some View {
        @Bindable var manager = manager
        sectionHeader("Voices")
        toggleRow("Recognize known speakers",
                  desc: "Auto-labels enrolled voices in new meetings. Name a speaker in a transcript to enroll their voice.",
                  isOn: $manager.recognizeSpeakers)
        if speakerProfiles.isEmpty {
            Text("No enrolled voices yet. In a meeting transcript, tap a speaker and give them a name — Parley remembers that voice on this device (and your iCloud).")
                .font(theme.bodyFont(11.5))
                .foregroundStyle(theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        } else {
            VStack(spacing: 8) {
                ForEach(speakerProfiles) { voiceRow($0) }
            }
            .padding(.top, 4)
        }
    }

    private func voiceRow(_ profile: SpeakerProfile) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(theme.bodyFont(13).weight(.semibold)).foregroundStyle(theme.ink)
                Text("Enrolled · \(profile.sampleCount) sample\(profile.sampleCount == 1 ? "" : "s")")
                    .font(theme.monoFont(10, relativeTo: .caption2)).foregroundStyle(theme.inkFaint)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { context.delete(profile) } label: {
                Image(systemName: "trash").foregroundStyle(theme.rec)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(profile.name)")
        }
        .padding(11)
        .background(theme.paper, in: cardShape)
        .overlay(cardShape.strokeBorder(theme.edge, lineWidth: theme.borderWidth))
    }

    // MARK: Sections / labels

    private func sectionHeader(_ title: String, first: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first {
                Rectangle().fill(theme.line).frame(height: theme.borderWidth)
                    .padding(.top, 24).padding(.bottom, 18)
            }
            Text(title.uppercased())
                .font(theme.monoFont(11))
                .tracking(1.6)
                .foregroundStyle(theme.inkFaint)
                .padding(.bottom, 14)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(theme.bodyFont(12).weight(.semibold))
            .foregroundStyle(theme.inkSoft)
            .padding(.bottom, 9)
    }

    // MARK: Mood grid

    private func moodGrid(_ manager: ThemeManager) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
            ForEach(Mood.allCases) { mood in
                let selected = mood == manager.mood
                Button { withAnimation(.snappy) { manager.mood = mood } } label: {
                    HStack(spacing: 10) {
                        AppIconView(mood: mood, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mood.name).font(theme.bodyFont(13).weight(.semibold)).foregroundStyle(theme.ink)
                            Text(mood.blurb).font(theme.bodyFont(10.5)).foregroundStyle(theme.inkFaint).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.paper, in: cardShape)
                    .overlay(cardShape.strokeBorder(selected ? theme.accent : theme.edge,
                                                    lineWidth: selected ? 1.5 : theme.borderWidth))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(theme.accent, in: Circle())
                                .padding(6)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 18)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
    }

    // MARK: Swatches

    private func swatches(_ options: [String], selected: String, onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.self) { hex in
                let on = hex.caseInsensitiveCompare(selected) == .orderedSame
                Button { onSelect(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(theme.edge, lineWidth: 1))
                        .overlay { if on { Circle().strokeBorder(theme.ink, lineWidth: 2).padding(-3) } }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 18)
    }

    // MARK: Rows

    /// A row with a name (+ optional description) on the left and a trailing control.
    private func toggleRow(_ name: String, desc: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(theme.bodyFont(13.5).weight(.semibold)).foregroundStyle(theme.ink)
                if let desc {
                    Text(desc).font(theme.bodyFont(11.5)).foregroundStyle(theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden().tint(theme.accent)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: theme.borderWidth) }
    }

    private func valueRow<Trailing: View>(_ name: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Text(name).font(theme.bodyFont(13.5).weight(.semibold)).foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: theme.borderWidth) }
    }

    private func checkRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 11) {
                Checkbox(on: isOn.wrappedValue, theme: theme)
                Text(label).font(theme.bodyFont(13.5)).foregroundStyle(theme.ink2)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    /// The privacy guarantee — always on, can't be turned off.
    private var lockedRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Run summaries on device only", systemImage: "bolt.fill")
                    .font(theme.bodyFont(13.5).weight(.semibold))
                    .foregroundStyle(theme.ink)
                Text("Nothing is ever sent to the cloud.")
                    .font(theme.bodyFont(11.5)).foregroundStyle(theme.inkSoft)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: .constant(true)).labelsHidden().tint(theme.accent).disabled(true)
        }
        .padding(14)
        .background(theme.accentTint, in: cardShape)
        .padding(.top, 10)
    }
}

// MARK: - The mood-aware app-icon mark

/// The design's `PkAppIcon` in SwiftUI: a squircle background (per-mood gradient,
/// border, grid) with the "P / speech-turn" glyph. Used in the mood picker.
struct AppIconView: View {
    let mood: Mood
    var size: CGFloat = 96

    var body: some View {
        let p = IconPalette.of(mood)
        ZStack {
            Squircle().fill(LinearGradient(
                colors: [Color(hex: p.bg), Color(hex: p.bg2)], startPoint: .top, endPoint: .bottom))

            if p.grid {
                IconGrid().stroke(Color.white.opacity(0.06), lineWidth: max(0.5, size / 120))
                    .clipShape(Squircle())
            }

            PGlyph().stroke(Color(hex: p.fg),
                            style: StrokeStyle(lineWidth: 9 * size / 100, lineCap: .round, lineJoin: .round))
            TailGlyph().stroke(Color(hex: p.fg),
                               style: StrokeStyle(lineWidth: 7.5 * size / 100, lineCap: .round, lineJoin: .round))

            if p.dotVisible {
                Circle().fill(Color(hex: p.dot))
                    .frame(width: 10 * size / 100, height: 10 * size / 100)
                    .position(x: 0.50 * size, y: 0.68 * size)
            }
            if p.borderWidth > 0 {
                Squircle().strokeBorder(Color(hex: p.border), lineWidth: p.borderWidth * size / 100)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Per-mood icon palette (fixed values from the design's CSS).
private struct IconPalette {
    let bg, bg2, fg, dot, border: String
    let dotVisible, grid: Bool
    let borderWidth: CGFloat   // in 0…100 icon units

    static func of(_ mood: Mood) -> IconPalette {
        switch mood {
        case .paper:        IconPalette(bg: "#FCF8F0", bg2: "#EFE7D6", fg: "#3E5C50", dot: "#3E5C50", border: "#000000", dotVisible: false, grid: false, borderWidth: 0)
        case .terminal:     IconPalette(bg: "#161D28", bg2: "#0B0E14", fg: "#FF9F1C", dot: "#FF9F1C", border: "#000000", dotVisible: false, grid: true,  borderWidth: 0)
        case .swiss:        IconPalette(bg: "#FFFFFF", bg2: "#FFFFFF", fg: "#111111", dot: "#E2231A", border: "#111111", dotVisible: true,  grid: false, borderWidth: 3)
        case .neubrutalist: IconPalette(bg: "#2B4BF2", bg2: "#2B4BF2", fg: "#F5F3EC", dot: "#D8F000", border: "#1A1A1A", dotVisible: true,  grid: false, borderWidth: 5)
        }
    }
}

/// iOS-like superellipse "squircle" (matches the design's `pkSquircle`).
struct Squircle: InsettableShape {
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.5, 0))
        path.addCurve(to: p(0, 0.5),   control1: p(0.09, 0),   control2: p(0, 0.09))
        path.addCurve(to: p(0.5, 1),   control1: p(0, 0.91),   control2: p(0.09, 1))
        path.addCurve(to: p(1, 0.5),   control1: p(0.91, 1),   control2: p(1, 0.91))
        path.addCurve(to: p(0.5, 0),   control1: p(1, 0.09),   control2: p(0.91, 0))
        path.closeSubpath()
        return path
    }
    func inset(by amount: CGFloat) -> some InsettableShape {
        var s = self; s.insetAmount += amount; return s
    }
}

/// The "P" stem + bowl that reads as a speech turn.
private struct PGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 100 * rect.width, y: y / 100 * rect.height) }
        var path = Path()
        path.move(to: p(37, 80))
        path.addLine(to: p(37, 26))
        path.addCurve(to: p(37, 54), control1: p(68, 26), control2: p(68, 54))
        return path
    }
}

/// The little speech-tail flick off the bowl.
private struct TailGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 100 * rect.width, y: y / 100 * rect.height) }
        var path = Path()
        path.move(to: p(55, 52))
        path.addQuadCurve(to: p(48, 65), control: p(60, 61))
        return path
    }
}

/// The hairline grid used by the Terminal mood icon.
private struct IconGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for v in [20.0, 36, 52, 68, 84] {
            let y = v / 100 * rect.height, x = v / 100 * rect.width
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: rect.width, y: y))
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        return path
    }
}

/// A small mood-styled checkbox.
private struct Checkbox: View {
    let on: Bool
    let theme: Theme
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius == 0 ? 0 : 6, style: .continuous)
        shape
            .fill(on ? theme.accent : Color.clear)
            .frame(width: 19, height: 19)
            .overlay(shape.strokeBorder(on ? theme.accent : theme.inkGhost, lineWidth: 1.8))
            .overlay {
                if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
            }
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
    .modelContainer(for: SpeakerProfile.self, inMemory: true)
}
