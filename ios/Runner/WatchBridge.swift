import Flutter
import Foundation
import WatchConnectivity

/// The link to the Apple Watch app (ios/HydraWatch). The Dart side is lib/network/native_bridges.dart (WatchBridge).
///   - the phone hands the watch the status of the running job (`updateApplicationContext`, so the watch has the latest one
///     when it wakes up);
///   - the watch can ask for the global stop with a message; the phone does not stop anything here: it passes the request to
///     the Dart side, which answers whether it accepted it (the option is on and the request is fresh) and, if so, makes the
///     same global stop as the STOP button with the session of the person. The answer goes back to the watch, so it shows
///     whether the request was accepted; the real result is the status that follows;
///   - the phone pushes an alert (`sendAlert`) as a message, only while the watch is reachable: a message is not stored, and an
///     old alert on the wrist is worse than none;
///   - the watch may pass the presence of the operator (`presence`) and the second tap of a spoken order (`voiceConfirm`) to the
///     phone; the Dart side passes them on to the server only behind their own switches (both off), and the answer to the
///     confirmation goes back to the watch.
final class WatchChannel: NSObject, WCSessionDelegate {
  static let shared = WatchChannel()
  private var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "hydra_umc/watch", binaryMessenger: messenger)
    shared.channel = channel
    channel.setMethodCallHandler { call, result in
      guard WCSession.isSupported() else {
        result(call.method == "isReachable" ? false : nil)
        return
      }
      let session = WCSession.default
      if session.delegate == nil {
        session.delegate = shared
        session.activate()
      }
      switch call.method {
      case "isReachable":
        result(session.activationState == .activated && session.isPaired && session.isWatchAppInstalled && session.isReachable)
      case "sendStatus":
        if session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
           var status = call.arguments as? [String: Any] {
          status["sentAt"] = Int(Date().timeIntervalSince1970 * 1000)
          try? session.updateApplicationContext(status)
        }
        result(nil)
      case "sendAlert":
        // Not queued: when the watch cannot be reached now the alert is dropped and the answer says so.
        if session.activationState == .activated, session.isPaired, session.isWatchAppInstalled, session.isReachable,
           let alert = call.arguments as? [String: Any] {
          session.sendMessage(["alert": alert], replyHandler: nil, errorHandler: nil)
          result(true)
        } else {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }

  /// The watch asks for the global stop: {"stopRequestedAt": <milliseconds since 1970>}; or it passes the presence of the
  /// operator ({"presence": {...}}) or the second tap of a spoken order ({"voiceConfirm": {...}}).
  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    if let heartbeat = message["presence"] as? [String: Any] {
      DispatchQueue.main.async { self.channel?.invokeMethod("presence", arguments: heartbeat) }
      replyHandler(["accepted": true])
      return
    }
    if let confirm = message["voiceConfirm"] as? [String: Any] {
      DispatchQueue.main.async {
        guard let channel = self.channel else {
          replyHandler(["accepted": false])
          return
        }
        channel.invokeMethod("voiceConfirm", arguments: confirm) { answer in
          replyHandler(["reply": (answer as? [String: Any]) ?? [:]])
        }
      }
      return
    }
    guard let at = message["stopRequestedAt"] as? Int else {
      replyHandler(["accepted": false])
      return
    }
    DispatchQueue.main.async {
      guard let channel = self.channel else {
        replyHandler(["accepted": false])
        return
      }
      channel.invokeMethod("stopRequested", arguments: at) { answer in
        replyHandler(["accepted": (answer as? Bool) ?? false])
      }
    }
  }
}
