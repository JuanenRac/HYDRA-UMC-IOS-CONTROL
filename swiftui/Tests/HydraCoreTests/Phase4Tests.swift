// HYDRA-UMC-IOS-CONTROL - cameras, the 3D address, the notices, the record of the server and push, with a pretend server and phone.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest
@testable import HydraCore

@MainActor
private final class FakeStreams: CameraStreamTransport {
    struct Opened {
        let url: String
        let headers: [String: String]
        let send: @MainActor (CameraEvent) -> Void
        let connection: Connection
    }
    final class Connection: LiveConnection {
        var closed = false
        func close() { closed = true }
    }
    var opened: [Opened] = []

    func open(url: String, headers: [String: String], onEvent: @escaping @MainActor (CameraEvent) -> Void) -> LiveConnection {
        let connection = Connection()
        opened.append(Opened(url: url, headers: headers, send: onEvent, connection: connection))
        return connection
    }
}

@MainActor
private final class FakePush: PushPlatform {
    var available = true
    var answer = PushTokenAnswer.token("sample-device")
    var forgotten = 0
    func token() async -> PushTokenAnswer { answer }
    func forget() { forgotten += 1 }
}

/// A picture as small as the markers allow.
private func jpeg(_ byte: UInt8) -> Data { Data([0xFF, 0xD8, byte, 0xFF, 0xD9]) }

@Sendable private func withRecord(_ request: HttpRequest) async throws -> HttpResponse {
    switch URL(string: request.url)?.path {
    case "/api/faults":
        return reply(200, #"{"active":[{"source":"safety","robotId":2,"code":"A","severity":"odd","since":2000}],"recent":[{"source":"motion","code":"B","severity":"info","state":"cleared","at":1000},{"code":"no source"}]}"#)
    case "/api/ecosystem/node-health":
        return request.url.hasSuffix("slot=0") ? reply(200, #"{"slot":0,"online":true,"heard":true,"ageMs":3000,"flagNames":["low"],"txErrors":1}"#) : reply(200, #"{"slot":1,"online":false}"#)
    case "/api/push/devices": return reply(200)
    default: return try await healthy(request)
    }
}

@MainActor
final class Phase4Tests: XCTestCase {
    // MARK: - Cameras

    func testTheCameraOfARobotAndWhetherItIsOn() {
        let tree = #"{"controllers":[{"robots":[{"id":1,"visionEnabled":false,"camera":{"connected":true}},{"id":2,"camera":{"connected":true}}],"cameras":[{"id":7,"assignedRobotId":1}]},{"cameras":[{"id":4,"assignedRobotId":1},{"id":9}]}]}"#
        let cell = CellState(HydraClient.object(Data(tree.utf8)) ?? [:])
        XCTAssertEqual(cell.cameraId(forRobot: 1), 4)
        XCTAssertEqual(cell.cameraId(forRobot: 2), 2)
        XCTAssertFalse(cell.cameraOn(1), "visionEnabled decides when the server sends it")
        XCTAssertTrue(cell.cameraOn(2))
        XCTAssertFalse(cell.cameraOn(3))
    }

    func testTheReconnectScheduleIsTheOneOfTheOtherApps() {
        XCTAssertEqual((0...6).map { MjpegReconnectPolicy.delay(failures: $0) }, [1, 2, 4, 8, 15, 15, 15])
        XCTAssertEqual(MjpegReconnectPolicy.failures(after: 3, gotFrame: false), 4)
        XCTAssertEqual(MjpegReconnectPolicy.failures(after: 3, gotFrame: true), 0)
    }

    func testTheParserGivesTheNewestPictureAcrossPieces() {
        var parser = MjpegParser()
        XCTAssertNil(parser.add(Data("--frame\r\n".utf8) + Data([0xFF, 0xD8, 1])))
        XCTAssertEqual(parser.add(Data([0xFF, 0xD9]) + Data([0xFF])), jpeg(1))
        XCTAssertEqual(parser.add(Data([0xD8, 2, 0xFF, 0xD9]) + jpeg(3)), jpeg(3), "the newest of two")
        XCTAssertEqual(parser.pendingCount, 0)
        XCTAssertNil(parser.add(Data([9, 9, 0xFF, 0xD9, 9])), "an end without a start")
        XCTAssertNil(parser.add(Data(count: MjpegParser.maxPending + 1)))
        XCTAssertEqual(parser.pendingCount, 0)
    }

    func testTheFeedReconnectsAndDropsWhatAnOldAttemptSays() async {
        let streams = FakeStreams()
        let timers = ManualTimers()
        let clock = ManualClock()
        let feed = CameraFeed(transport: streams, schedule: { timers.add($0, $1) }, now: { clock.time })
        var renewed = 0
        feed.start(request: { CameraRequest(url: "https://demo/api/camera/1/stream", headers: [:]) }, refused: { renewed += 1 })
        XCTAssertEqual(streams.opened.count, 1)
        streams.opened[0].send(.response(200))
        streams.opened[0].send(.data(jpeg(1)))
        XCTAssertEqual(feed.state, .live)
        streams.opened[0].send(.ended)
        XCTAssertEqual(feed.state, .unavailable(nil))
        XCTAssertEqual(feed.frame, jpeg(1), "the last picture stays while it reconnects")
        timers.fire { $0 == 1 }
        XCTAssertEqual(streams.opened.count, 2)
        streams.opened[0].send(.data(jpeg(9)))
        XCTAssertEqual(feed.frame, jpeg(1))
        streams.opened[1].send(.response(401))
        XCTAssertEqual(feed.state, .unavailable(401))
        XCTAssertTrue(streams.opened[1].connection.closed)
        await until { renewed == 1 }
        XCTAssertEqual(renewed, 1)
        timers.fire { $0 == 2 }
        XCTAssertEqual(streams.opened.count, 3)
        // silent for longer than the limit
        clock.time = clock.time.addingTimeInterval(31)
        timers.fire { $0 == MjpegReconnectPolicy.stallTimeout }
        XCTAssertTrue(streams.opened[2].connection.closed)
        feed.stop()
        XCTAssertNil(feed.frame)
        timers.fire { _ in true }
        XCTAssertEqual(streams.opened.count, 3, "nothing is opened after stop")
    }

    func testTheStreamCarriesTheSessionInHeadersAndTheViewerInTheFragment() async {
        let rig = Rig()
        XCTAssertNil(rig.controller.cameraRequest(robotId: 1))
        await rig.signIn()
        let request = rig.controller.cameraRequest(robotId: 1)
        XCTAssertEqual(request?.url, "https://192.168.1.50:3000/api/camera/1/stream")
        XCTAssertEqual(request?.headers["Authorization"], "Bearer t1")
        XCTAssertEqual(request?.headers["X-Hydra-Client"], "ios/0.0.1")
        XCTAssertEqual(rig.controller.viewerUrl(robotId: 2), "https://192.168.1.50:3000/?hideUI=true&robotId=2#token=t1")
        XCTAssertEqual(ViewerUrl.build(base: "https://a:1", robotId: 1, token: "a+b/c="), "https://a:1/?hideUI=true&robotId=1#token=a%2Bb%2Fc%3D")
        XCTAssertEqual(ViewerUrl.build(base: "https://a:1", robotId: 1, token: nil), "https://a:1/?hideUI=true&robotId=1")
    }

    // MARK: - Notices

    func testTheNumbersOfTheRulesAreTheContract() throws {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { folder.deleteLastPathComponent() }
        let data = try Data(contentsOf: folder.appendingPathComponent("docs/robot_command_contract.json"))
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let block = try XCTUnwrap(all["watchAlerts"] as? [String: Any])
        XCTAssertEqual(block["dedupeWindowMs"] as? Int, Int(AlertRules.dedupeWindow * 1000))
        XCTAssertEqual(block["minGapMs"] as? Int, Int(AlertRules.minGap * 1000))
        XCTAssertEqual(block["maxPerMinute"] as? Int, AlertRules.maxPerMinute)
        XCTAssertEqual(block["connectionLostAfterMs"] as? Int, Int(AlertRules.connectionLostAfter * 1000))
    }

    func testWhatDeservesANotice() {
        func robot(_ online: Bool = true, enabled: Bool = true, playing: Bool = false) -> PlantRobot {
            PlantRobot(id: "c1/1", name: "A1", online: online, enabled: enabled, playing: playing)
        }
        var rules = AlertRules()
        let start = Date(timeIntervalSince1970: 1000)
        func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
        XCTAssertEqual(rules.observe(connected: true, robots: [robot(playing: true)], stop: .none, at: at(0)), [], "the first look only learns")
        XCTAssertEqual(rules.observe(connected: false, robots: [], stop: .none, at: at(1)), [])
        XCTAssertEqual(rules.observe(connected: false, robots: [], stop: .none, at: at(10)), [])
        let lost = rules.observe(connected: false, robots: [], stop: .none, at: at(11))
        XCTAssertEqual(lost.map(\.kind), [.connectionLost])
        XCTAssertEqual(lost.first?.critical, true, "a robot was moving")
        XCTAssertEqual(rules.observe(connected: true, robots: [robot()], stop: .none, at: at(20)).map(\.kind), [.connectionRestored])
        XCTAssertEqual(rules.observe(connected: true, robots: [robot(enabled: false)], stop: .none, at: at(30)).map(\.kind), [.robotSafeMode])
        XCTAssertEqual(rules.observe(connected: true, robots: [robot()], stop: .none, at: at(31)), [])
        XCTAssertEqual(rules.observe(connected: true, robots: [robot(enabled: false)], stop: .none, at: at(35)), [], "the same one is not repeated")
        XCTAssertEqual(rules.observe(connected: true, robots: [robot(false)], stop: .sending, at: at(70)).map(\.kind), [.robotOffline])
        XCTAssertEqual(rules.observe(connected: true, robots: [robot(false)], stop: .notConfirmed, at: at(70.1)).map(\.kind), [.stopNotConfirmed], "a critical one does not wait")
        XCTAssertEqual(rules.observe(connected: true, robots: [robot(false)], stop: .done, at: at(80)).map(\.kind), [.stopConfirmed])
    }

    func testTheListKeepsTheNewestAndDropsWhatCannotBeRead() {
        var list: [Notice] = []
        for index in 0..<(Notices.max + 5) { list = Notices.add(list, Notice(kind: .jobDone, detail: String(index), at: Date(timeIntervalSince1970: 1))) }
        XCTAssertEqual(list.count, Notices.max)
        XCTAssertEqual(list.first?.detail, String(Notices.max + 4))
        XCTAssertEqual(Notices.unseen(list), 0, "a finished job asks for nothing")
        XCTAssertEqual(Notices.decode(Notices.encode(list)), list)
        XCTAssertEqual(Notices.decode(#"[{"kind":"later"},{"kind":"robotOffline","detail":"A1","at":5},7]"#).map(\.kind), [.robotOffline])
        XCTAssertEqual(Notices.decode("damaged"), [])
    }

    func testStopsMessagesAndFinishedJobsAreListedAndKept() async {
        let rig = Rig()
        await rig.signIn()
        await rig.controller.stopAll()
        XCTAssertEqual(rig.controller.notices.map(\.kind), [.stopConfirmed])
        rig.clock.time = rig.clock.time.addingTimeInterval(60)
        rig.controller.dismissStopResult()
        rig.controller.noticesTick()
        await rig.controller.stopAll()
        XCTAssertEqual(rig.controller.notices.map(\.kind), [.stopConfirmed, .stopConfirmed], "again, after the dedupe window")
        rig.sockets.last.say(#"{"type":"delta","schema":2,"controllerId":"c1","robotId":1,"patch":{"playbackState":{"isPlaying":true}}}"#)
        rig.sockets.last.say(#"{"type":"delta","schema":2,"controllerId":"c1","robotId":1,"patch":{"playbackState":{"isPlaying":false,"isFinished":true}}}"#)
        XCTAssertEqual(rig.controller.notices.first?.kind, .jobDone)
        XCTAssertEqual(rig.controller.notices.first?.detail, "A1")
        rig.controller.serverMessage(title: "Global stop", body: "Issued by admin")
        rig.controller.serverMessage(title: "Global stop", body: "Issued by admin", once: true)
        XCTAssertEqual(rig.controller.notices.filter { $0.kind == .serverMessage }.map(\.detail), ["Global stop - Issued by admin"])
        XCTAssertEqual(rig.controller.unseenNotices, 1)
        rig.controller.markNoticesSeen()
        XCTAssertEqual(rig.controller.unseenNotices, 0)
        let again = Rig(prefs: rig.prefs)
        again.controller.serverMessage(title: "Before start", body: "")
        await again.controller.start()
        XCTAssertEqual(again.controller.notices.count, rig.controller.notices.count + 1, "what was kept is not written over")
    }

    // MARK: - The record of the server

    func testTheRecordIsReadOnDemandAndStopsAtASilentController() async {
        let rig = Rig(withRecord)
        await rig.signIn()
        XCTAssertFalse(rig.transport.paths().contains("/api/faults"))
        await rig.controller.readServerRecord()
        let reading = rig.controller.serverReading
        XCTAssertEqual(reading?.server, "192.168.1.50:3000")
        XCTAssertEqual(reading?.faults?.active.map(\.severity), ["error"])
        XCTAssertEqual(reading?.faults?.active.first?.robotId, "2")
        XCTAssertEqual(reading?.faults?.recent.map(\.code), ["B"])
        XCTAssertEqual(reading?.boards.map(\.online), [true, false])
        XCTAssertEqual(rig.transport.paths().filter { $0 == "/api/ecosystem/node-health" }.count, 2)
        rig.controller.logout()
        XCTAssertNil(rig.controller.serverReading)
    }

    func testAServerWithoutTheRecordSaysWhy() async {
        let rig = Rig({ request in
            switch URL(string: request.url)?.path {
            case "/api/faults": return reply(404)
            case "/api/ecosystem/node-health": return reply(403)
            default: return try await healthy(request)
            }
        })
        await rig.signIn()
        await rig.controller.readServerRecord()
        XCTAssertEqual(rig.controller.serverReading?.faultsProblem, .off)
        XCTAssertEqual(rig.controller.serverReading?.boardsProblem, .forbidden)
        XCTAssertEqual(rig.controller.screen, .main)
    }

    // MARK: - Push

    private func pushCalls(_ rig: Rig) -> [HttpRequest] { rig.transport.requests.filter { $0.url.contains("/api/push/") } }

    func testPushStartsOffAndIsToldOnlyWithASession() async {
        let push = FakePush()
        let rig = Rig(withRecord, push: push)
        await rig.signIn()
        XCTAssertFalse(rig.controller.pushEnabled)
        XCTAssertEqual(pushCalls(rig).count, 0)
        await rig.controller.setPush(true)
        XCTAssertEqual(rig.controller.pushState, .registered)
        let sent = pushCalls(rig)
        XCTAssertEqual(sent.map(\.method), ["POST"])
        let body = sent[0].body.flatMap { HydraClient.object($0) }
        XCTAssertEqual(body?["token"] as? String, "sample-device")
        XCTAssertEqual(body?["platform"] as? String, "ios")
        await rig.controller.setPush(false)
        XCTAssertEqual(pushCalls(rig).map(\.method), ["POST", "DELETE"])
        XCTAssertEqual(pushCalls(rig).last?.url, "https://192.168.1.50:3000/api/push/devices/sample-device")
        XCTAssertEqual(push.forgotten, 1)
        XCTAssertEqual(rig.controller.pushState, .off)
    }

    func testSigningOutTakesTheRegistrationBackWithThatSession() async {
        let push = FakePush()
        let rig = Rig(withRecord, push: push)
        await rig.signIn()
        await rig.controller.setPush(true)
        rig.controller.logout()
        await until { push.forgotten == 1 }
        let removed = pushCalls(rig).last
        XCTAssertEqual(removed?.method, "DELETE")
        XCTAssertEqual(removed?.headers["Authorization"], "Bearer t1")
        XCTAssertEqual(push.forgotten, 1)
    }

    func testWhatTheServerOrThePersonAnswers() async {
        let push = FakePush()
        let rig = Rig({ request in
            if URL(string: request.url)?.path == "/api/push/devices" { return reply(404) }
            return try await healthy(request)
        }, push: push)
        await rig.signIn()
        await rig.controller.setPush(true)
        XCTAssertEqual(rig.controller.pushState, .serverOff)
        push.answer = .denied
        await rig.controller.syncPush()
        XCTAssertEqual(rig.controller.pushState, .denied)
        rig.controller.control.setListenOnly(true)
        push.answer = .token("sample-device")
        await rig.controller.syncPush()
        XCTAssertEqual(rig.controller.pushState, .listenOnly)

        let none = Rig()
        await none.signIn()
        await none.controller.setPush(true)
        XCTAssertFalse(none.controller.pushEnabled, "a build without the configuration cannot switch it on")
    }

    // MARK: - The camera switch

    func testTheCameraSwitchIsACommandThatListenOnlyHolds() async {
        let rig = Rig()
        await rig.signIn()
        await rig.controller.control.setVision(2, true)?.value
        let sent = rig.transport.requests.last { $0.url.hasSuffix("/api/robot/2/command") }
        let body = sent?.body.flatMap { HydraClient.object($0) }
        XCTAssertEqual(body?["command"] as? String, "vision")
        XCTAssertEqual((body?["params"] as? [String: Any])?["enabled"] as? Bool, true)
        XCTAssertTrue(rig.controller.cell.cameraOn(2))
        rig.controller.control.setListenOnly(true)
        XCTAssertNil(rig.controller.control.setVision(2, false))
    }
}
