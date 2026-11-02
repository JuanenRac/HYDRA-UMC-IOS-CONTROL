import Flutter
import Foundation

/// The pairing link of the admin page of the server (hydra-umc://pair?host=..&port=..&fp=..&name=..): the camera of the phone
/// opens it with this app (the URL scheme is declared in Info.plist). The Dart side is lib/network/native_bridges.dart
/// (PairingBridge). This half only hands the text over: whether the link is read at all (a switch in the settings, off at
/// first), what it says and the question to the person before anything is kept are all decided in Dart.
final class PairingChannel {
  static let shared = PairingChannel()
  private var channel: FlutterMethodChannel?
  private var pending: String?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "hydra_umc/pairing", binaryMessenger: messenger)
    shared.channel = channel
    channel.setMethodCallHandler { call, result in
      if call.method == "takePending" {
        let link = shared.pending
        shared.pending = nil
        result(link)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// A link arrived (at launch or while the app is open). Only the pairing links of this app are kept.
  func receive(_ url: URL) {
    guard url.scheme?.lowercased() == "hydra-umc", url.host?.lowercased() == "pair" else { return }
    // Kept until the Dart side asks for it (takePending) and also told to it at once when it listens.
    pending = url.absoluteString
    // Forgotten once the Dart side took it (a handler answers nil); a Dart side that does not listen yet leaves it pending.
    channel?.invokeMethod("pairingLink", arguments: url.absoluteString) { [weak self] answer in
      if answer == nil { self?.pending = nil }
    }
  }
}
