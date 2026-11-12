import Flutter
import UIKit
import WatchConnectivity
import XCTest

@testable import Runner

/// A binary messenger that answers by itself: a message sent on a channel goes straight to the handler registered on that channel, as the engine would
/// do for a call that comes from Dart. It lets the tests call the real method channels of the app without starting an engine.
final class LoopbackMessenger: NSObject, FlutterBinaryMessenger {
  private var handlers: [String: FlutterBinaryMessageHandler] = [:]
  private(set) var sent: [(channel: String, message: Data?)] = []

  /// What the Dart side answers when the NATIVE side calls it ("channel/method" -> answer). A call to a method listed here never reaches the native handler.
  var dartSide: [String: Any?] = [:]
  /// The calls the native side made to Dart: "channel/method" and its arguments.
  private(set) var calledDart: [(name: String, arguments: Any?)] = []

  func send(onChannel channel: String, message: Data?) {
    sent.append((channel, message))
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply? = nil) {
    sent.append((channel, message))
    let codec = FlutterStandardMethodCodec.sharedInstance()
    var dartAnswer: Any??
    if let message = message {
      let call = codec.decodeMethodCall(message)
      if let answer = dartSide["\(channel)/\(call.method)"] {
        calledDart.append(("\(channel)/\(call.method)", call.arguments))
        dartAnswer = .some(answer)
      }
    }
    if let answer = dartAnswer {
      callback?(codec.encodeSuccessEnvelope(answer))
    } else if let handler = handlers[channel] {
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

  // MARK: the push token of the Live Activity

  func testThePushTokenIsLowercaseHexadecimalWithTwoDigitsPerByte() {
    XCTAssertEqual(LiveActivityPush.hex(Data([0x00, 0x0a, 0xff, 0x10, 0xAB])), "000aff10ab")
  }

  func testAnEmptyPushTokenIsAnEmptyString() {
    XCTAssertEqual(LiveActivityPush.hex(Data()), "")
  }

  func testAThirtyTwoByteTokenGivesSixtyFourDigits() {
    let token = Data((0..<32).map { UInt8($0 * 8 & 0xff) })
    let text = LiveActivityPush.hex(token)
    XCTAssertEqual(text.count, 64)
    XCTAssertEqual(text, text.lowercased())
  }

  // MARK: the watch link

  private func watchChannel() -> LoopbackMessenger {
    let messenger = LoopbackMessenger()
    WatchChannel.register(messenger: messenger)
    return messenger
  }

  /// Hands a message of the watch to the real delegate method and waits for its reply (it answers from the main queue).
  private func fromWatch(_ message: [String: Any]) -> [String: Any] {
    let done = expectation(description: "the reply to the watch")
    var reply: [String: Any] = [:]
    WatchChannel.shared.session(WCSession.default, didReceiveMessage: message) { answer in
      reply = answer
      done.fulfill()
    }
    wait(for: [done], timeout: 20)
    return reply
  }

  func testTheWatchChannelRefusesWhatItDoesNotKnow() {
    let messenger = watchChannel()
    if WCSession.isSupported() {
      XCTAssertTrue((messenger.call("hydra_umc/watch", "somethingElse") as AnyObject) === FlutterMethodNotImplemented)
    } else {
      XCTAssertNil(messenger.call("hydra_umc/watch", "somethingElse"))
    }
  }

  func testNoAlertIsQueuedWhenTheWatchCannotBeReached() {
    let messenger = watchChannel()
    // On a simulator no watch is paired: the alert is dropped and the answer says so (an old alert on the wrist is worse than none).
    XCTAssertEqual(messenger.call("hydra_umc/watch", "sendAlert", arguments: ["title": "t", "body": "b"]) as? Bool, false)
    XCTAssertEqual(messenger.call("hydra_umc/watch", "isReachable") as? Bool, false)
  }

  func testSendingTheStatusWithoutAWatchDoesNothingAndDoesNotFail() {
    let messenger = watchChannel()
    XCTAssertNil(messenger.call("hydra_umc/watch", "sendStatus", arguments: ["status": "running"]))
  }

  func testAMessageOfTheWatchWithoutAKnownKeyIsNotAccepted() {
    _ = watchChannel()
    for message in [[:], ["stopRequestedAt": "now"], ["stopRequestedAt": 1.5], ["other": 1]] as [[String: Any]] {
      XCTAssertEqual(fromWatch(message)["accepted"] as? Bool, false, "\(message)")
    }
  }

  func testAStopRequestOfTheWatchGoesToDartAndTheAnswerComesBack() {
    for decision in [true, false] {
      let messenger = watchChannel()
      messenger.dartSide["hydra_umc/watch/stopRequested"] = decision
      let reply = fromWatch(["stopRequestedAt": 1_700_000_000_000])
      XCTAssertEqual(reply["accepted"] as? Bool, decision)
      XCTAssertEqual(messenger.calledDart.count, 1)
      XCTAssertEqual(messenger.calledDart.first?.name, "hydra_umc/watch/stopRequested")
      XCTAssertEqual(messenger.calledDart.first?.arguments as? Int, 1_700_000_000_000)
    }
  }

  func testTheWatchStopIsNotAcceptedWhenDartGivesAnythingButTrue() {
    let messenger = watchChannel()
    messenger.dartSide["hydra_umc/watch/stopRequested"] = "yes"
    XCTAssertEqual(fromWatch(["stopRequestedAt": 1])["accepted"] as? Bool, false)
  }

  func testThePresenceOfTheOperatorIsPassedOnAndAcceptedAtOnce() {
    let messenger = watchChannel()
    let reply = fromWatch(["presence": ["at": 5]])
    XCTAssertEqual(reply["accepted"] as? Bool, true)
    let passed = expectation(description: "presence reaches Dart")
    DispatchQueue.main.async { passed.fulfill() }
    wait(for: [passed], timeout: 5)
    XCTAssertTrue(messenger.sent.contains { $0.channel == "hydra_umc/watch" })
  }

  func testTheSecondTapOfASpokenOrderGetsTheAnswerOfDart() {
    let messenger = watchChannel()
    messenger.dartSide["hydra_umc/watch/voiceConfirm"] = ["ok": true]
    let reply = fromWatch(["voiceConfirm": ["id": "abc"]])
    XCTAssertEqual((reply["reply"] as? [String: Any])?["ok"] as? Bool, true)
    XCTAssertEqual((messenger.calledDart.first?.arguments as? [String: Any])?["id"] as? String, "abc")
  }

  // MARK: the dictation

  func testTheDictationRefusesACallWithoutArguments() {
    let messenger = LoopbackMessenger()
    SpeechChannel.register(messenger: messenger)
    let answer = messenger.call("hydra_umc/speech", "listen", arguments: "text") as? [String: String]
    XCTAssertEqual(answer?["status"], "failed")
    XCTAssertEqual(answer?["text"], "")
  }

  func testCancellingWhenNothingListensIsHarmless() {
    let messenger = LoopbackMessenger()
    SpeechChannel.register(messenger: messenger)
    XCTAssertNil(messenger.call("hydra_umc/speech", "cancel"))
    XCTAssertNil(messenger.call("hydra_umc/speech", "cancel"))
  }

  func testTheDictationRefusesAnUnknownMethod() {
    let messenger = LoopbackMessenger()
    SpeechChannel.register(messenger: messenger)
    XCTAssertTrue((messenger.call("hydra_umc/speech", "record") as AnyObject) === FlutterMethodNotImplemented)
  }

  // MARK: life cycle

  func testTheAppIsHostingTheTests() {
    XCTAssertNotNil(UIApplication.shared.delegate, "the tests run inside the app, so its delegate is the real one")
    XCTAssertEqual(Bundle.main.bundleIdentifier?.isEmpty, false)
  }
}
