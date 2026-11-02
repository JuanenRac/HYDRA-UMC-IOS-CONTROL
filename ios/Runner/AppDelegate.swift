import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // The push notifications of the server (APNs): the Dart side is lib/network/push_bridge.dart.
  private var pushChannel: FlutterMethodChannel?
  private var pushToken: String?
  private var shortcutChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "HydraPush")?.messenger() {
      let channel = FlutterMethodChannel(name: "hydra_umc/push", binaryMessenger: messenger)
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
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
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    pushToken = hex
    pushChannel?.invokeMethod("token", arguments: hex)
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
