import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

/// Push via Firebase Cloud Messaging, same backend path as Android
/// (POST /api/push/fcm with platform "ios"). Inactive until the build includes
/// GoogleService-Info.plist and the app is signed with a push entitlement.
@MainActor
final class PushManager: NSObject {
    nonisolated static let alertCategory = "PROBE_ALERT"
    nonisolated static let acknowledgeAction = "ACKNOWLEDGE"

    private nonisolated let api: ProbeHarborAPI
    private(set) var lastError: String?
    private var currentToken: String?

    /// Called with the alert event id when a notification is opened.
    var onOpenAlert: ((Int64?) -> Void)?

    init(api: ProbeHarborAPI) {
        self.api = api
        super.init()
    }

    /// True when Firebase is configured in this build.
    var isAvailable: Bool { FirebaseApp.app() != nil }

    func configure() {
        guard FirebaseApp.app() == nil,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
        else { return }
        FirebaseApp.configure()
        Messaging.messaging().delegate = self

        let acknowledge = UNNotificationAction(identifier: Self.acknowledgeAction, title: "Acknowledge")
        let category = UNNotificationCategory(
            identifier: Self.alertCategory, actions: [acknowledge], intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks for notification permission, then registers the FCM token.
    func enable() async throws {
        guard isAvailable else {
            throw APIError.message("Push isn't set up in this build yet (needs Apple push + Firebase config).")
        }
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { throw APIError.message("Notifications are turned off for ProbeHarbor in Settings.") }
        UIApplication.shared.registerForRemoteNotifications()
        let token = try await Messaging.messaging().token()
        try await api.registerPushToken(token)
        currentToken = token
    }

    /// Re-sends the token after sign-in when permission was granted before.
    func registerIfAuthorized() {
        guard isAvailable else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            UIApplication.shared.registerForRemoteNotifications()
            if let token = try? await Messaging.messaging().token() {
                currentToken = token
                do { try await api.registerPushToken(token) } catch { lastError = error.localizedDescription }
            }
        }
    }

    func unregister() async {
        guard isAvailable else { return }
        var token = currentToken
        if token == nil { token = try? await Messaging.messaging().token() }
        guard let token else { return }
        await api.unregisterPushToken(token)
        currentToken = nil
    }

    func didRegister(deviceToken: Data) {
        guard isAvailable else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    nonisolated static func eventId(from userInfo: [AnyHashable: Any]) -> Int64? {
        if let string = userInfo["event_id"] as? String { return Int64(string) }
        return (userInfo["event_id"] as? NSNumber)?.int64Value
    }
}

extension PushManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            currentToken = fcmToken
            try? await api.registerPushToken(fcmToken)
        }
    }
}

extension PushManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let eventId = PushManager.eventId(from: userInfo)
        if response.actionIdentifier == PushManager.acknowledgeAction, let eventId {
            try? await api.acknowledge(eventId: eventId)
            return
        }
        await MainActor.run { onOpenAlert?(eventId) }
    }
}
