import Flutter
import UIKit
import XCTest

@testable import Runner

/// A binary messenger that answers by itself: a message sent on a channel goes straight to the handler registered on that channel, as the engine would
/// do for a call that comes from Dart. It lets the tests call the real method channels of the app without starting an engine.
final class LoopbackMessenger: NSObject, FlutterBinaryMessenger {
  private var handlers: [String: FlutterBinaryMessageHandler] = [:]
  private(set) var sent: [(channel: String, message: Data?)] = []

  func send(onChannel channel: String, message: Data?) {
    sent.append((channel, message))
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply? = nil) {
    sent.append((channel, message))
    if let handler = handlers[channel] {
      handler(message) { reply in callback?(reply) }
    } else {
      callback?(nil)
    }
  }

  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler? = nil) -> FlutterBinaryMessengerConnection {
    handlers[channel] = handler
    return FlutterBinaryMessengerConnection(handlers.count)
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}

  /// Calls a method on a channel the way Dart does and returns what the handler answered.
  func call(_ channel: String, _ method: String, arguments: Any? = nil) -> Any? {
    var answer: Any?
    var answered = false
    let caller = FlutterMethodChannel(name: channel, binaryMessenger: self)
    caller.invokeMethod(method, arguments: arguments) { result in
      answer = result
      answered = true
    }
    XCTAssertTrue(answered, "the handler of \(channel) answered at once")
    return answer
  }
}

class RunnerTests: XCTestCase {
  private let stopKey = "hydra_umc_pending_global_stop_at"

  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: stopKey)
    GlobalStopRequests.shared.onRequest = nil
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: stopKey)
    GlobalStopRequests.shared.onRequest = nil
    super.tearDown()
  }

  // MARK: global stop (the shortcut, the quick action and the Siri phrase all end here)

  func testAGlobalStopRequestIsTakenOnceAndOnlyOnce() {
    XCTAssertFalse(GlobalStopRequests.shared.take(), "nothing was asked yet")
    GlobalStopRequests.shared.request()
    XCTAssertTrue(GlobalStopRequests.shared.take())
    XCTAssertFalse(GlobalStopRequests.shared.take(), "a second take finds nothing")
  }

  func testAGlobalStopRequestOlderThanTheLimitIsForgottenNotExecuted() {
    let tooOld = Date().timeIntervalSince1970 - GlobalStopRequests.maxAge - 5
    UserDefaults.standard.set(tooOld, forKey: stopKey)
    XCTAssertFalse(GlobalStopRequests.shared.take(), "a stop asked a minute ago must not fire when the app finally opens")
    XCTAssertNil(UserDefaults.standard.object(forKey: stopKey), "the old request is removed as well")
  }

  func testAGlobalStopRequestJustInsideTheLimitIsStillTaken() {
    let almost = Date().timeIntervalSince1970 - GlobalStopRequests.maxAge + 10
    UserDefaults.standard.set(almost, forKey: stopKey)
    XCTAssertTrue(GlobalStopRequests.shared.take())
  }

  func testAFutureOrZeroTimestampIsNotAStopRequest() {
    UserDefaults.standard.set(0.0, forKey: stopKey)
    XCTAssertFalse(GlobalStopRequests.shared.take())
  }

  func testTheListenerIsToldAtOnceWhenARequestArrives() {
    var told = 0
    GlobalStopRequests.shared.onRequest = { told += 1 }
    GlobalStopRequests.shared.request()
    GlobalStopRequests.shared.request()
    XCTAssertEqual(told, 2)
    XCTAssertTrue(GlobalStopRequests.shared.take())
  }

  func testTheQuickActionTypeIsTheOneOfTheBundle() {
    XCTAssertEqual(GlobalStopRequests.quickActionType, "com.hydraumc.hydraUmcControl.globalStop")
    XCTAssertEqual(GlobalStopRequests.maxAge, 60)
  }

  // MARK: pairing links

  private func pairingChannel() -> LoopbackMessenger {
    let messenger = LoopbackMessenger()
    PairingChannel.register(messenger: messenger)
    _ = messenger.call("hydra_umc/pairing", "takePending")  // starts from nothing whatever an earlier test left
    return messenger
  }

  func testAPairingLinkOfThisAppIsKeptUntilDartTakesIt() {
    let messenger = pairingChannel()
    let link = "hydra-umc://pair?address=192.168.0.180&code=123456"
    PairingChannel.shared.receive(URL(string: link)!)
    XCTAssertEqual(messenger.call("hydra_umc/pairing", "takePending") as? String, link)
    XCTAssertNil(messenger.call("hydra_umc/pairing", "takePending"), "it is handed over once")
  }

  func testTheSchemeAndTheHostOfAPairingLinkAreComparedWithoutCase() {
    let messenger = pairingChannel()
    PairingChannel.shared.receive(URL(string: "HYDRA-UMC://PAIR?code=1")!)
    XCTAssertEqual(messenger.call("hydra_umc/pairing", "takePending") as? String, "HYDRA-UMC://PAIR?code=1")
  }

  func testLinksThatAreNotPairingLinksOfThisAppAreIgnored() {
    let messenger = pairingChannel()
    for text in ["https://pair?code=1", "hydra-umc://other?code=1", "hydra://pair?code=1", "hydra-umc:///pair", "file:///tmp/x", "mailto:someone@example.invalid"] {
      PairingChannel.shared.receive(URL(string: text)!)
      XCTAssertNil(messenger.call("hydra_umc/pairing", "takePending"), "\(text) must not become a pending pairing")
    }
  }

  func testTheLastPairingLinkWins() {
    let messenger = pairingChannel()
    PairingChannel.shared.receive(URL(string: "hydra-umc://pair?code=1")!)
    PairingChannel.shared.receive(URL(string: "hydra-umc://pair?code=2")!)
    XCTAssertEqual(messenger.call("hydra_umc/pairing", "takePending") as? String, "hydra-umc://pair?code=2")
  }

  func testThePairingChannelRefusesWhatItDoesNotKnow() {
    let messenger = pairingChannel()
    XCTAssertTrue((messenger.call("hydra_umc/pairing", "somethingElse") as AnyObject) === FlutterMethodNotImplemented)
  }

  // MARK: alerts

  func testTheAlertsChannelRefusesAShowWithoutItsArguments() {
    let messenger = LoopbackMessenger()
    AlertsChannel.register(messenger: messenger)
    let refused: [Any?] = [nil, ["id": "a"], ["id": "a", "title": "t"], ["id": 5, "title": "t", "body": "b"], "text"]
    for arguments in refused {
      let answer = messenger.call("hydra_umc/alerts", "show", arguments: arguments)
      let error = answer as? FlutterError
      XCTAssertEqual(error?.code, "bad-arguments", "arguments \(String(describing: arguments)) must be refused")
    }
  }

  func testTheAlertsChannelRefusesAnUnknownMethod() {
    let messenger = LoopbackMessenger()
    AlertsChannel.register(messenger: messenger)
    XCTAssertTrue((messenger.call("hydra_umc/alerts", "cancelAll") as AnyObject) === FlutterMethodNotImplemented)
  }

  // MARK: the Live Activity state

  @available(iOS 16.1, *)
  func testTheLiveActivityStateSurvivesAnEncodeAndDecode() throws {
    let state = HydraJobAttributes.ContentState(robotName: "Arm 1", status: "running", step: 3, total: 12)
    let data = try JSONEncoder().encode(state)
    let back = try JSONDecoder().decode(HydraJobAttributes.ContentState.self, from: data)
    XCTAssertEqual(back, state)
    XCTAssertEqual(back.hashValue, state.hashValue)
    XCTAssertEqual(HydraJobAttributes().title, "HYDRA-UMC")
  }

  @available(iOS 16.1, *)
  func testTheLiveActivityStatesWithDifferentStepsAreDifferent() {
    let one = HydraJobAttributes.ContentState(robotName: "Arm 1", status: "running", step: 1, total: 12)
    let two = HydraJobAttributes.ContentState(robotName: "Arm 1", status: "running", step: 2, total: 12)
    XCTAssertNotEqual(one, two)
  }

  @available(iOS 16.1, *)
  func testTheLiveActivityStateRefusesAnIncompleteDocument() {
    let incomplete = Data("{\"robotName\":\"Arm 1\",\"status\":\"running\"}".utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(HydraJobAttributes.ContentState.self, from: incomplete))
  }

  // MARK: life cycle

  func testTheAppIsHostingTheTests() {
    XCTAssertNotNil(UIApplication.shared.delegate, "the tests run inside the app, so its delegate is the real one")
    XCTAssertEqual(Bundle.main.bundleIdentifier?.isEmpty, false)
  }
}
