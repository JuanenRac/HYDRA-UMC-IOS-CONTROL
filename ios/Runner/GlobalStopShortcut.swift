import AppIntents
import Foundation

/// The "global stop" requests of the system shortcuts (the Shortcuts app, Siri, Spotlight, the Action button and the quick action
/// of the home screen icon). They all end in the same place: the Dart side calls the global stop the app already has
/// (POST /api/stop-all with the session of the person), so the contract and the token handling are the ones of the STOP button.
/// A request waits for the app for one minute at most: a stop asked for hours ago must never fire when the app is opened later.
final class GlobalStopRequests {
  static let shared = GlobalStopRequests()
  static let quickActionType = "com.hydraumc.hydraUmcControl.globalStop"
  static let maxAge: TimeInterval = 60

  private let key = "hydra_umc_pending_global_stop_at"
  /// Set by AppDelegate once the Dart side is listening.
  var onRequest: (() -> Void)?

  func request() {
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
    onRequest?()
  }

  /// True once when a request younger than `maxAge` is waiting.
  func take() -> Bool {
    let at = UserDefaults.standard.double(forKey: key)
    UserDefaults.standard.removeObject(forKey: key)
    return at > 0 && Date().timeIntervalSince1970 - at <= GlobalStopRequests.maxAge
  }
}

@available(iOS 16.0, *)
struct GlobalStopIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("ShortcutGlobalStopTitle", table: "InfoPlist")
  static var description = IntentDescription(LocalizedStringResource("ShortcutGlobalStopDescription", table: "InfoPlist"))
  // The app opens so the stop goes out through its own session and shows its answer (stopped, or not confirmed).
  static var openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    GlobalStopRequests.shared.request()
    return .result()
  }
}

@available(iOS 16.0, *)
struct HydraAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: GlobalStopIntent(),
      phrases: [
        "Global stop in \(.applicationName)",
        "Stop all robots in \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("ShortcutGlobalStopTitle", table: "InfoPlist"),
      systemImageName: "stop.circle"
    )
  }
}
