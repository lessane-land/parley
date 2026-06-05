import SwiftUI

/// The live transcript surface — the design's recessed transcript panel with a
/// record control, a status pill, and the streaming text (confirmed text plus
/// the rapidly-updating "volatile" guess in the accent color).
///
/// This view is "dumb" (per the MVVM convention): it shows what it's handed and
/// reports taps. The owning detail view holds the `TranscriptionService` and
/// persists the text.
struct TranscriptPanel: View {
    let theme: Theme
    let density: Density
    let text: String              // persisted / finalized transcript (flat fallback)
    var segments: [TranscriptSegment] = []  // structured transcript (preferred)
    let volatile: String          // in-flight partial (only while recording)
    let state: TranscriptionService.State
    let startedAt: Date?
    var languageLabel: String? = nil   // active transcription locale, e.g. "EN-US"
    var canLabelSpeakers: Bool = false      // tap a node to set a speaker
    var knownSpeakers: [String] = []        // names already used in this note (quick-pick)
    var onAssignSpeaker: ((UUID, String?) -> Void)? = nil   // pick an existing name, or clear (nil)
    var onNewSpeaker: ((UUID) -> Void)? = nil               // ask the owner to prompt for a new name

    private var isRecording: Bool { state == .recording }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(theme.line)
            content
        }
        .moodCard(theme, fill: theme.paperSunk)
    }

    // MARK: Header (label · live status)

    private var header: some View {
        HStack(spacing: 10) {
            Text("TRANSCRIPT")
                .font(theme.monoFont(11))
                .tracking(1.4)
                .foregroundStyle(theme.inkSoft)

            if let languageLabel {
                languageChip(languageLabel)
            }

            Spacer()

            if isRecording {
                livePill
            } else if let label = busyLabel {
                Text(label)
                    .font(theme.monoFont(11))
                    .foregroundStyle(theme.inkFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Shows which single language transcription resolved to (Automatic picks
    /// one), so it's never ambiguous why Spanish-while-set-to-English looks off.
    private func languageChip(_ label: String) -> some View {
        Text(label)
            .font(theme.monoFont(9.5, relativeTo: .caption2))
            .tracking(0.5)
            .foregroundStyle(theme.accentInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.accentTint, in: Capsule())
            .accessibilityLabel("Transcription language \(label)")
    }

    private var livePill: some View {
        HStack(spacing: 6) {
            Circle().fill(theme.rec).frame(width: 7, height: 7)
            if let startedAt {
                // Re-renders ~every second to tick the timer.
                TimelineView(.periodic(from: startedAt, by: 1)) { _ in
                    Text(elapsed(since: startedAt))
                        .font(theme.monoFont(11))
                        .foregroundStyle(theme.rec)
                }
            }
        }
    }

    private var busyLabel: String? {
        switch state {
        case .preparing: "Starting…"
        case .downloadingModel: "Downloading model…"
        case .finishing: "Stopping…"
        case .identifyingSpeakers: "Identifying speakers…"
        default: nil
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .denied:
            message("Microphone access is off", detail: "Enable it in Settings to transcribe meetings.", icon: "mic.slash")
        case .unavailable(let reason):
            message("Transcription unavailable", detail: reason, icon: "exclamationmark.triangle")
        default:
            if text.isEmpty && segments.isEmpty && volatile.isEmpty {
                message("No transcript yet", detail: "Tap Record to capture the conversation, live and on-device.", icon: "waveform")
            } else {
                transcriptTimeline
            }
        }
    }

    /// The design's variant-C transcript: a vertical timeline spine with a node
    /// per line. Prefers structured `segments` (timestamps + speaker nodes) and
    /// falls back to sentence-splitting flat `text` (older notes). The live line
    /// is the active (accent) node at the bottom.
    private var transcriptTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if segments.isEmpty { fallbackRows } else { segmentRows }
                    if !volatile.isEmpty {
                        timelineRow(text: volatile, time: nil, speaker: nil, active: true, isLast: true, id: nil)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: text) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: volatile) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    @ViewBuilder private var segmentRows: some View {
        ForEach(Array(segments.enumerated()), id: \.element.id) { index, seg in
            timelineRow(text: seg.text, time: seg.at, speaker: seg.speaker, active: false,
                        isLast: index == segments.count - 1 && volatile.isEmpty, id: seg.id)
        }
    }

    @ViewBuilder private var fallbackRows: some View {
        let confirmed = sentences(text)
        ForEach(Array(confirmed.enumerated()), id: \.offset) { index, sentence in
            timelineRow(text: sentence, time: nil, speaker: nil, active: false,
                        isLast: index == confirmed.count - 1 && volatile.isEmpty, id: nil)
        }
    }

    private func timelineRow(text: String, time: Date?, speaker: String?, active: Bool, isLast: Bool, id: UUID?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            nodeColumn(active: active, speaker: speaker, isLast: isLast, id: id)

            VStack(alignment: .leading, spacing: 3) {
                if time != nil || speaker != nil {
                    HStack(spacing: 5) {
                        if let time {
                            Text(time, format: .dateTime.hour().minute())
                                .foregroundStyle(theme.inkFaint)
                        }
                        if let speaker {
                            if time != nil { Text("·").foregroundStyle(theme.inkFaint) }
                            Text(speaker).foregroundStyle(theme.accentInk)
                        }
                    }
                    .font(theme.monoFont(9.5, relativeTo: .caption2))
                }
                Text(text)
                    .font(theme.bodyFont(density.bodySize, relativeTo: .body))
                    .foregroundStyle(active ? theme.ink : theme.ink2)
                    .lineSpacing(density.lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 14)
        }
    }

    /// The spine + node. A segment with a speaker shows its initials; when
    /// `canLabelSpeakers`, the node is a menu to pick an existing name, add a new
    /// one, or clear it.
    private func nodeColumn(active: Bool, speaker: String?, isLast: Bool, id: UUID?) -> some View {
        let labelable = canLabelSpeakers && id != nil && !active
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(theme.line)
                .frame(width: 1.5)
                .frame(maxHeight: isLast ? 9 : .infinity, alignment: .top)

            if labelable, let id {
                Menu {
                    speakerMenu(id: id, current: speaker)
                } label: {
                    nodeBadge(active: active, speaker: speaker)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Set speaker")
            } else {
                nodeBadge(active: active, speaker: speaker)
            }
        }
        .frame(width: 18)
    }

    @ViewBuilder
    private func speakerMenu(id: UUID, current: String?) -> some View {
        ForEach(knownSpeakers, id: \.self) { name in
            Button { onAssignSpeaker?(id, name) } label: {
                if name == current { Label(name, systemImage: "checkmark") } else { Text(name) }
            }
        }
        if !knownSpeakers.isEmpty { Divider() }
        Button { onNewSpeaker?(id) } label: { Label("New name…", systemImage: "person.badge.plus") }
        if current != nil {
            Button(role: .destructive) { onAssignSpeaker?(id, nil) } label: { Label("Clear", systemImage: "xmark") }
        }
    }

    private func nodeBadge(active: Bool, speaker: String?) -> some View {
        Group {
            if let speaker, !active {
                Circle()
                    .fill(theme.accentTint)
                    .overlay(Circle().strokeBorder(theme.accent, lineWidth: 1.5))
                    .overlay(Text(Self.initials(speaker)).font(theme.monoFont(8, relativeTo: .caption2)).foregroundStyle(theme.accentInk))
                    .frame(width: 18, height: 18)
            } else {
                Circle()
                    .fill(active ? theme.accent : theme.paperSunk)
                    .overlay(Circle().strokeBorder(active ? theme.accent : theme.inkGhost, lineWidth: 2))
                    .frame(width: 11, height: 11)
                    .padding(.top, 2)
            }
        }
    }

    /// Up to two initials from a speaker name ("Vanesa Lessane" → "VL").
    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return (letters.isEmpty ? String(name.prefix(1)) : letters).uppercased()
    }

    /// Locale-aware sentence segmentation for the timeline nodes.
    private func sentences(_ string: String) -> [String] {
        guard !string.isEmpty else { return [] }
        var result: [String] = []
        string.enumerateSubstrings(in: string.startIndex..., options: .bySentences) { sub, _, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                result.append(s)
            }
        }
        return result.isEmpty ? [string] : result
    }

    private func message(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(theme.inkFaint)
            Text(title)
                .font(theme.titleFont(16, relativeTo: .headline))
                .foregroundStyle(theme.ink)
            Text(detail)
                .font(theme.bodyFont(13))
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func elapsed(since start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
