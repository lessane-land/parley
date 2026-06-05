import SwiftUI
import CoreData

/// Watches CloudKit sync activity and exposes a simple status for the UI.
///
/// SwiftData syncs via `NSPersistentCloudKitContainer`, which posts
/// `eventChangedNotification` for setup/import/export work. We translate those
/// into a small status enum the sidebar chip reads. `@MainActor @Observable` so
/// the chip updates live.
@MainActor
@Observable
final class SyncMonitor {
    enum Status: Equatable {
        case localOnly      // CloudKit not active (no account/entitlement/Simulator)
        case idle           // CloudKit on, nothing happening yet
        case syncing
        case synced
        case error(String)
    }

    private(set) var status: Status

    init(cloudEnabled: Bool) {
        status = cloudEnabled ? .idle : .localOnly
        guard cloudEnabled else { return }

        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
            else { return }

            // The observer runs on the main queue, so we're already on the main
            // actor — assert that to mutate the @MainActor `status` safely.
            MainActor.assumeIsolated {
                guard let self else { return }
                // `endDate == nil` means the work is still in progress.
                if event.endDate == nil {
                    self.status = .syncing
                } else if let error = event.error {
                    self.status = .error(error.localizedDescription)
                } else {
                    self.status = .synced
                }
            }
        }
    }
}
