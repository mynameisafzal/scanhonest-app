import Foundation
import UserNotifications

// MARK: - NotificationManager
// Central place for all local notification scheduling.
// Respects the user's in-app preference key "notificationsEnabled".
// iOS permission status is the true gate — we never fire if not authorized.

struct NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    // MARK: - UserDefaults Keys
    enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let autoEnhanceEnabled   = "autoEnhanceEnabled"
        static let autoCaptureEnabled   = "autoCaptureEnabled"
        static let iCloudSyncEnabled    = "iCloudSyncEnabled"
    }

    // MARK: - Permission check

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
    }

    func checkAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }

    // MARK: - Scan complete notification
    // Called after OCR finishes in OCRPanel.runOCR()

    func sendScanCompleteNotification(documentName: String) {
        guard isEnabled else { return }

        let content      = UNMutableNotificationContent()
        content.title    = "Scan Complete"
        content.body     = "\"\(documentName)\" is ready."
        content.sound    = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content:    content,
            trigger:    nil         // nil = deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Notification error: \(error.localizedDescription)") }
        }
    }

    // MARK: - iCloud sync notification

    func sendSyncCompleteNotification(documentCount: Int) {
        guard isEnabled else { return }

        let content      = UNMutableNotificationContent()
        content.title    = "iCloud Sync Complete"
        content.body     = "\(documentCount) document\(documentCount == 1 ? "" : "s") synced."
        content.sound    = .default

        let request = UNNotificationRequest(
            identifier: "icloud-sync-\(UUID().uuidString)",
            content:    content,
            trigger:    nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Request permission (called from PermissionsSlide or Settings toggle)

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    UserDefaults.standard.set(granted, forKey: Keys.notificationsEnabled)
                    completion(granted)
                }
            }
    }
}
