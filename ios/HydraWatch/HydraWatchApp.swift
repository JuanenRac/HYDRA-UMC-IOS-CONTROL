import SwiftUI
import WatchConnectivity

// The Apple Watch companion: the status of the running job that the phone sends, and a STOP button that asks the PHONE to
// make the global stop with its own session (the watch holds no password and no token and never talks to the server).
// The button says so plainly when the phone cannot be reached or did not accept the request; the real result is the status
// that follows. This is the source of the watchOS app target "HydraWatch"; it is not part of the Xcode project yet (the
// target has to be created in Xcode, with the strings of ios/HydraExtensions). The phone half is ios/Runner/WatchBridge.swift.

@main
struct HydraWatchApp: App {
  @StateObject private var link = PhoneLink()

  var body: some Scene {
    WindowGroup {
      ContentView().environmentObject(link)
    }
  }
}

final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
  @Published var connected = false
  @Published var robotName = ""
  @Published var status = "idle"
  @Published var step = 0
  @Published var total = 0
  /// What the last press of STOP came to: "", "sent", "refused" or "unreachable".
  @Published var stopResult = ""

  override init() {
    super.init()
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  private func apply(_ context: [String: Any]) {
    // A status older than a minute is not shown as current.
    let sentAt = (context["sentAt"] as? Int) ?? 0
    let fresh = sentAt > 0 && Date().timeIntervalSince1970 * 1000 - Double(sentAt) < 60_000
    DispatchQueue.main.async {
      self.connected = (context["connected"] as? Bool ?? false) && fresh
      self.robotName = context["robotName"] as? String ?? ""
      self.status = context["status"] as? String ?? "idle"
      self.step = context["step"] as? Int ?? 0
      self.total = context["total"] as? Int ?? 0
    }
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    apply(session.receivedApplicationContext)
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    apply(applicationContext)
  }

  func requestStop() {
    let session = WCSession.default
    guard session.activationState == .activated, session.isReachable else {
      stopResult = "unreachable"
      return
    }
    let now = Int(Date().timeIntervalSince1970 * 1000)
    session.sendMessage(["stopRequestedAt": now], replyHandler: { reply in
      DispatchQueue.main.async { self.stopResult = (reply["accepted"] as? Bool ?? false) ? "sent" : "refused" }
    }, errorHandler: { _ in
      DispatchQueue.main.async { self.stopResult = "unreachable" }
    })
  }
}
