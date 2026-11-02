import Flutter
import Foundation
import WatchConnectivity

/// The link to the Apple Watch app (ios/HydraWatch). The Dart side is lib/network/native_bridges.dart (WatchBridge).
///   - the phone hands the watch the status of the running job (`updateApplicationContext`, so the watch has the latest one
///     when it wakes up);
///   - the watch can ask for the global stop with a message; the phone does not stop anything here: it passes the request to
///     the Dart side, which answers whether it accepted it (the option is on and the request is fresh) and, if so, makes the
///     same global stop as the STOP button with the session of the person. The answer goes back to the watch, so it shows
///     whether the request was accepted; the real result is the status that follows.
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }

  /// The watch asks for the global stop: {"stopRequestedAt": <milliseconds since 1970>}.
  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
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
