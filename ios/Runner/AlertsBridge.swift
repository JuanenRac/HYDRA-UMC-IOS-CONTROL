import Flutter
import Foundation
import UserNotifications

/// The local notifications of the app (a finished job, a robot offline or in safe mode, a lost connection). The Dart side is
/// lib/network/native_bridges.dart (AlertsBridge): it decides what to say and when, in the language of the app; this only
/// asks the system for permission and shows what it is given. A notification carries no command and no action that moves a robot.
final class AlertsChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "hydra_umc/alerts", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }
      case "show":
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String,
              let title = args["title"] as? String,
              let body = args["body"] as? String else {
          result(FlutterError(code: "bad-arguments", message: "id, title and body are needed", details: nil))
          return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // The same id replaces the notification still on the screen instead of piling up a second one.
        let request = UNNotificationRequest(identifier: "hydra_umc.alert.\(id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in
          DispatchQueue.main.async { result(nil) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
