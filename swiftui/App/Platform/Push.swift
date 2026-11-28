// HYDRA-UMC-IOS-CONTROL - the push notifications of a server (Firebase Cloud Messaging over APNs). They only inform: no category and no
// action is registered, so nothing can be commanded from one. A build without GoogleService-Info.plist never starts Firebase.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import FirebaseCore
import FirebaseMessaging
import HydraCore
import UIKit
import UserNotifications

@MainActor
final class FirebasePush: PushPlatform {
    static let shared = FirebasePush()

    private(set) var available = false

    /// Starts Firebase when the app was built with the configuration of this app. Nothing of the file is logged.
    func configure() {
        guard !available,
              let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              options.bundleID == Bundle.main.bundleIdentifier
        else { return }
        FirebaseApp.configure(options: options)
        available = true
    }

    func token() async -> PushTokenAnswer {
        guard available else { return .none }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return .denied }
        UIApplication.shared.registerForRemoteNotifications()
        // the token of the server is made from the one Apple gives, which arrives on its own
        for _ in 0..<50 where Messaging.messaging().apnsToken == nil {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard Messaging.messaging().apnsToken != nil, let token = try? await Messaging.messaging().token() else { return .none }
        return .token(token)
    }

    func forget() {
        guard available else { return }
        UIApplication.shared.unregisterForRemoteNotifications()
        Messaging.messaging().deleteToken { _ in }
    }
}

/// Where a message goes. What arrives before the app is ready waits here.
@MainActor
enum PushInbox {
    private static var waiting: [(title: String, body: String, once: Bool)] = []
    private static var handler: ((String, String, Bool) -> Void)?

    static func connect(_ receive: @escaping (String, String, Bool) -> Void) {
        handler = receive
        waiting.forEach { receive($0.title, $0.body, $0.once) }
        waiting = []
    }

    static func receive(title: String, body: String, once: Bool) {
        if let handler { handler(title, body, once) } else { waiting.append((title, body, once)) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        FirebasePush.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // the swizzling of Firebase is off (Info.plist), so the Apple token is handed to it here
        if FirebasePush.shared.available { Messaging.messaging().apnsToken = deviceToken }
    }

    // A notification that arrives while the app is open is still shown: a global stop must not go unnoticed.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let title = notification.request.content.title
        let body = notification.request.content.body
        Task { @MainActor in PushInbox.receive(title: title, body: body, once: false) }
        completionHandler([.banner, .sound])
    }

    /// A tap opens the app and nothing else.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let title = response.notification.request.content.title
        let body = response.notification.request.content.body
        Task { @MainActor in PushInbox.receive(title: title, body: body, once: true) }
        completionHandler()
    }
}
