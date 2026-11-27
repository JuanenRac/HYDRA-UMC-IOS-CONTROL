import FirebaseCore
import FirebaseMessaging
import Flutter
import UIKit
import UserNotifications

/// The Firebase side of the push notifications. The configuration file (GoogleService-Info.plist) is not kept in the
/// repository: a build without it never starts Firebase and the app says that push is off (see docs/PUSH_NOTIFICATIONS.md).
enum PushFirebase {
  private(set) static var configured = false

  /// Starts Firebase when the app was built with the configuration of this app. Nothing of the file is logged.
  static func configureIfPresent() {
    guard !configured,
      let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
      let options = FirebaseOptions(contentsOfFile: path),
      options.bundleID == Bundle.main.bundleIdentifier
    else { return }
    FirebaseApp.configure(options: options)
    configured = true
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // The push notifications of the server (Firebase Cloud Messaging over APNs): the Dart side is lib/network/push_bridge.dart.
  // They only inform: no category and no action is registered, so nothing can be commanded from a notification.
  private var pushChannel: FlutterMethodChannel?
  private var pushToken: String?
  private var shortcutChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    PushFirebase.configureIfPresent()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "HydraPush")?.messenger() {
      let channel = FlutterMethodChannel(name: "hydra_umc/push", binaryMessenger: messenger)
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "available":
          result(PushFirebase.configured)
        case "requestPermission":
          // Asks the person once; the system remembers the answer. Only a granted permission registers the app.
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
              if granted { UIApplication.shared.registerForRemoteNotifications() }
              result(granted)
            }
          }
        case "currentToken":
          result(self?.pushToken)
        case "unregister":
          self?.pushToken = nil
          UIApplication.shared.unregisterForRemoteNotifications()
          if PushFirebase.configured {
            Messaging.messaging().deleteToken { _ in }
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      pushChannel = channel
    }
    // The system shortcuts of the global stop (GlobalStopShortcut.swift): the Dart side asks whether a request is waiting.
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "HydraShortcuts")?.messenger() {
      let channel = FlutterMethodChannel(name: "hydra_umc/shortcuts", binaryMessenger: messenger)
      channel.setMethodCallHandler { call, result in
        if call.method == "takeGlobalStop" {
          result(GlobalStopRequests.shared.take())
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      shortcutChannel = channel
      GlobalStopRequests.shared.onRequest = { [weak channel] in
        DispatchQueue.main.async { channel?.invokeMethod("globalStopRequested", arguments: nil) }
      }
    }
    // What reaches out of the app, each behind its own switch in the settings (all off at first): local notifications of a
    // job, dictation for the assistant, the Live Activity and the Apple Watch. The Dart side is lib/network/native_bridges.dart.
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "HydraAlerts")?.messenger() {
      AlertsChannel.register(messenger: messenger)
    }
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "HydraSpeech")?.messenger() {
      SpeechChannel.register(messenger: messenger)
    }
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "HydraLiveActivity")?.messenger() {
      LiveActivityChannel.register(messenger: messenger)
    }
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "HydraWatch")?.messenger() {
      WatchChannel.register(messenger: messenger)
    }
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "HydraPairing")?.messenger() {
      PairingChannel.register(messenger: messenger)
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // The token the server is told is the one of Firebase, which is made from the Apple one. The swizzling of Firebase is
    // off (Info.plist), so the Apple token is handed to it here.
    if PushFirebase.configured {
      Messaging.messaging().apnsToken = deviceToken
      Messaging.messaging().token { [weak self] token, _ in
        guard let token = token else { return }
        DispatchQueue.main.async {
          self?.pushToken = token
          self?.pushChannel?.invokeMethod("token", arguments: token)
        }
      }
    }
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // A notification that arrives while the app is open is still shown: a global stop must not go unnoticed.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}
