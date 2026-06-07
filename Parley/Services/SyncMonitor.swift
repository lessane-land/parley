import SwiftUI
import CoreData
import CloudKit

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

    /// Matches the iCloud container declared in `Parley.entitlements`.
    private static let containerID = "iCloud.com.lessane.Parley"

    init(cloudEnabled: Bool, fallbackReason: String? = nil) {
        if cloudEnabled {
            status = .idle
        } else if let fallbackReason {
            status = .error("Sync off — \(fallbackReason)")
        } else {
            status = .localOnly
        }

        // Whether or not the CloudKit store started, check the iCloud account —
        // a "not signed in / restricted" reason is far more useful than a silent
        // "On this device".
        Task { [weak self] in await self?.checkAccount(cloudEnabled: cloudEnabled) }

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

    /// Surface the iCloud account state so a misconfiguration reads as a concrete
    /// reason rather than a quiet local-only fallback. Only downgrades the status
    /// to an error for genuinely unavailable accounts; an available account leaves
    /// the sync-event status untouched.
    private func checkAccount(cloudEnabled: Bool) async {
        let accountStatus: CKAccountStatus
        do {
            accountStatus = try await CKContainer(identifier: Self.containerID).accountStatus()
        } catch {
            if cloudEnabled, status == .idle {
                status = .error("Couldn't check iCloud: \(error.localizedDescription)")
            }
            return
        }

        switch accountStatus {
        case .available:
            break // good — keep idle/syncing/synced
        case .noAccount:
            status = .error("Not signed in to iCloud. Sign in (Settings ▸ Apple Account) and turn on iCloud Drive.")
        case .restricted:
            status = .error("iCloud is restricted on this device (parental or MDM controls).")
        case .temporarilyUnavailable:
            status = .error("iCloud is temporarily unavailable — try again shortly.")
        case .couldNotDetermine:
            if status == .idle { status = .error("Couldn't determine the iCloud account state.") }
        @unknown default:
            break
        }
    }
}
