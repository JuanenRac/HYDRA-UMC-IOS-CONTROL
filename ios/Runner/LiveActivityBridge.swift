import Flutter
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts, updates and ends the Live Activity of the running trajectory. The Dart side is lib/network/native_bridges.dart
/// (LiveActivityBridge); the planner there decides when, so the system is not flooded. The activity only shows a status:
/// it has no button and no action that moves a robot. It is drawn by the widget extension (ios/HydraLiveActivity), which
/// has to exist as a target of the Xcode project for anything to appear; without it `start` still answers true but the
/// system draws nothing.
final class LiveActivityChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "hydra_umc/live_activity", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      #if canImport(ActivityKit)
      if #available(iOS 16.2, *) {
        LiveActivityController.shared.handle(call, result)
        return
      }
      #endif
      // An iPhone or an iOS without Live Activities.
      result(call.method == "isAvailable" || call.method == "start" ? false : nil)
    }
  }
}

#if canImport(ActivityKit)
@available(iOS 16.2, *)
final class LiveActivityController {
  static let shared = LiveActivityController()
  private var current: Activity<HydraJobAttributes>?

  private func state(_ args: [String: Any]) -> HydraJobAttributes.ContentState {
    HydraJobAttributes.ContentState(
      robotName: args["robotName"] as? String ?? "",
      status: args["status"] as? String ?? "idle",
      step: args["step"] as? Int ?? 0,
      total: args["total"] as? Int ?? 0
    )
  }

  private func content(_ args: [String: Any]) -> ActivityContent<HydraJobAttributes.ContentState> {
    // The system marks the content as out of date when nothing refreshed it for this long (the app was suspended).
    let stale = (args["staleAfterSeconds"] as? Int).map { Date().addingTimeInterval(TimeInterval($0)) }
    return ActivityContent(state: state(args), staleDate: stale)
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "isAvailable":
      result(ActivityAuthorizationInfo().areActivitiesEnabled)
    case "start":
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        result(false)
        return
      }
      // Only one: a second start replaces the first.
      Task { @MainActor in
        if let old = self.current { await old.end(nil, dismissalPolicy: .immediate) }
        do {
          self.current = try Activity.request(attributes: HydraJobAttributes(), content: self.content(args), pushType: nil)
          result(true)
        } catch {
          result(false)
        }
      }
    case "update":
      Task { @MainActor in
        await self.current?.update(self.content(args))
        result(nil)
      }
    case "end":
      let seconds = args["dismissAfterSeconds"] as? Int ?? 0
      Task { @MainActor in
        let policy: ActivityUIDismissalPolicy = seconds > 0 ? .after(Date().addingTimeInterval(TimeInterval(seconds))) : .immediate
        await self.current?.end(self.content(args), dismissalPolicy: policy)
        self.current = nil
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
#endif
