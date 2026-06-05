import SwiftUI

/// Lists today's calendar meetings; tapping one creates (or reopens) a note.
/// A "dumb" view — the owner loads the meetings and handles the tap.
struct TodayMeetingsSheet: View {
    let theme: Theme
    let meetings: [Meeting]
    let access: EventKitService.Access
    let isLoading: Bool
    let onPick: (Meeting) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .background(theme.paperSunk)
                .navigationTitle("Today")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            centered { ProgressView() }
        } else if access == .denied {
            message("Calendar access is off", "Enable it in Settings to pull in today's meetings.", "calendar.badge.exclamationmark")
        } else if meetings.isEmpty {
            message("No meetings today", "Nothing on the calendar for the rest of today.", "calendar")
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(meetings) { meeting in
                        Button { onPick(meeting); dismiss() } label: {
                            MeetingRow(theme: theme, meeting: meeting)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }

    private func centered<V: View>(@ViewBuilder _ inner: () -> V) -> some View {
        inner().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ title: String, _ detail: String, _ icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 32)).foregroundStyle(theme.inkFaint)
            Text(title).font(theme.titleFont(18, relativeTo: .headline)).foregroundStyle(theme.ink)
            Text(detail).font(theme.bodyFont(13)).foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center).frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct MeetingRow: View {
    let theme: Theme
    let meeting: Meeting

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(meeting.start, format: .dateTime.hour().minute())
                    .font(theme.monoFont(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.accentInk)
                Text(meeting.end, format: .dateTime.hour().minute())
                    .font(theme.monoFont(11, relativeTo: .caption))
                    .foregroundStyle(theme.inkFaint)
            }
            .frame(width: 56, alignment: .trailing)

            Rectangle().fill(theme.accent).frame(width: 3).clipShape(Capsule())

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(theme.titleFont(16, relativeTo: .headline))
                    .tracking(theme.titleTracking)
                    .textCase(theme.titleUppercase ? .uppercase : nil)
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                if !meeting.attendees.isEmpty {
                    Label(meeting.attendees.joined(separator: ", "),
                          systemImage: "person.2")
                        .font(theme.bodyFont(12))
                        .foregroundStyle(theme.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard(theme)
    }
}
