// HYDRA-UMC-IOS-CONTROL - the commands of the Control screen against a scripted server: the cases of jog, STOP and reservation of the published app.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest
@testable import HydraCore

/// What the scripted server answers; a test changes it between steps.
final class CellServer: @unchecked Sendable {
    var role = "operator"
    var online = true
    var model = "Generic (6-DOF)"
    var hasTable = false
    var playing = false
    var enabled = true
    var commandStatus = 200
    var commandBody = #"{"success":true}"#
    var claimStatus = 200
    var claimBody = #"{"success":true}"#
    var claims = "[]"
    var armRequired = false
    var maxAmount = 100.0
    var stopAllStatus = 200
    var work = #"[{"x":1,"y":2,"z":3}]"#
    /// Command names that get no answer.
    var silent: Set<String> = []

    var settings: String {
        #"{"controllers":[{"id":"c1","robots":[{"id":1,"name":"A1","model":"\#(model)","online":\#(online),"enabled":\#(enabled),"hasXYTable":\#(hasTable),"#
            + #""pos":{"x":200,"y":0,"z":0},"joints":{"j1":0},"playbackState":{"isPlaying":\#(playing)},"valves":[false,false]},{"id":2,"name":"A2","online":true,"pos":{"x":0,"y":0,"z":0}}]}]}"#
    }

    private var token: String {
        let payload = Data(#"{"role":"\#(role)"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "h.\(payload).s"
    }

    func answer(_ request: HttpRequest) async throws -> HttpResponse {
        guard request.url.hasPrefix("https://") else { throw TransportError.unreachable }
        let path = URL(string: request.url)?.path ?? ""
        switch path {
        case "/api/hydra-info": return reply(200, infoJson)
        case "/api/login": return reply(200, #"{"success":true,"token":"\#(token)","refreshToken":"r1"}"#)
        case "/api/settings": return reply(200, settings)
        case "/api/stop-all": return reply(stopAllStatus, stoppedJson)
        case "/api/claims": return reply(200, #"{"claims":\#(claims)}"#)
        case "/api/safety-limits":
            return reply(200, #"{"limits":{"jog":{"armRequired":\#(armRequired),"armTtlMs":60000}},"robot":{"id":1,"jog":{"maxAmount":\#(maxAmount),"maxAbsolute":500}}}"#)
        case "/api/robot/1": return reply(200, #"{"robot":{"id":1,"name":"A1","online":true,"hasXYTable":true},"revision":"r9"}"#)
        case "/api/robot/1/claim", "/api/robot/1/release": return reply(claimStatus, claimBody)
        case "/api/robot/1/jog-arm": return reply(200, #"{"success":true,"ttlMs":60000}"#)
        case "/api/robot/1/command":
            let name = (request.body.flatMap { HydraClient.object($0) })?["command"] as? String ?? ""
            if silent.contains(name) { throw TransportError.unreachable }
            return reply(commandStatus, commandBody)
        case "/WORKS/A1/index.json": return reply(200, #"["a.json","../b.json"]"#)
        case "/WORKS/A1/a.json": return reply(200, work)
        default: return reply(404)
        }
    }
}

@MainActor
struct ControlRig {
    let server: CellServer
    let rig: Rig
    var control: RobotControl { rig.controller.control }
    var controller: HydraController { rig.controller }

    init(_ server: CellServer = CellServer(), prefs: MemoryPrefs = MemoryPrefs(), cache: MemoryCache = MemoryCache(), opens: Bool = true) async {
        self.server = server
        rig = Rig({ try await server.answer($0) }, prefs: prefs, cache: cache, opens: opens)
        await rig.signIn()
        rig.controller.control.retryPauseNanoseconds = 1_000_000
        rig.controller.control.debounceSeconds = 0.02
    }

    /// The bodies of the commands sent, in order.
    var commands: [[String: Any]] {
        rig.transport.requests.filter { $0.url.hasSuffix("/command") }.compactMap { $0.body.flatMap { HydraClient.object($0) } }
    }

    var commandRequests: [HttpRequest] { rig.transport.requests.filter { $0.url.hasSuffix("/command") } }
    func requests(_ suffix: String) -> [HttpRequest] { rig.transport.requests.filter { $0.url.hasSuffix(suffix) } }
    var names: [String] { commands.compactMap { $0["command"] as? String } }
    var error: String? { controller.message?.key }
    var robot: RobotInfo { control.selected! }
    func settle() async { try? await Task.sleep(nanoseconds: 100_000_000) }
}

@MainActor
final class ControlTests: XCTestCase {
    private func params(_ command: [String: Any]) -> [String: Any] { command["params"] as? [String: Any] ?? [:] }

    // MARK: - Jog

    func testAJogSendsTheControllerIdInTheBodyAndTheHeaderAndANumber() async {
        let rig = await ControlRig()
        await rig.control.jog(.robot, axis: "x", amount: 5).first?.value
        let sent = rig.commandRequests.first
        XCTAssertEqual(sent?.headers["X-Controller-Id"], rig.control.controllerId)
        XCTAssertEqual(rig.commands.first?["controllerId"] as? String, rig.control.controllerId)
        XCTAssertNotNil(rig.commands.first?["seq"])
        XCTAssertEqual(rig.robot.x, 205)
        XCTAssertNil(rig.error)
    }

    func testAJogAboveTheLimitOfTheModelIsNotSent() async {
        let server = CellServer()
        server.maxAmount = 5
        let rig = await ControlRig(server)
        await rig.control.refreshAccess()
        XCTAssertTrue(rig.control.jog(.robot, axis: "x", amount: 10).isEmpty)
        XCTAssertEqual(rig.error, "errJogOverLimit")
        XCTAssertEqual(rig.controller.message?.values["limit"], "5")
        XCTAssertTrue(rig.commands.isEmpty)
        await rig.control.jog(.robot, axis: "x", amount: 4).first?.value
        XCTAssertEqual(rig.commands.count, 1)
    }

    func testAJogThatHasToBeArmedIsNotSentUntilItIs() async {
        let server = CellServer()
        server.armRequired = true
        let rig = await ControlRig(server)
        await rig.control.refreshAccess()
        XCTAssertTrue(rig.control.jogNeedsArming(1))
        XCTAssertTrue(rig.control.jog(.robot, axis: "x", amount: 1).isEmpty)
        XCTAssertEqual(rig.error, "errJogNotArmed")
        XCTAssertTrue(rig.commands.isEmpty)
        await rig.control.setJogArmed(true)
        XCTAssertFalse(rig.control.jogNeedsArming(1))
        let arm = rig.requests("/jog-arm").first?.body.flatMap { HydraClient.object($0) }
        XCTAssertEqual(arm?["armed"] as? Bool, true)
        XCTAssertEqual(arm?["controllerId"] as? String, rig.control.controllerId)
        await rig.control.setJogArmed(false)
        XCTAssertTrue(rig.control.jogNeedsArming(1))
    }

    func testARefusalForAnUnarmedJogEndsTheArmingAndNotTheSession() async {
        let server = CellServer()
        server.commandStatus = 403
        server.commandBody = #"{"error":"not armed","code":"jog-not-armed"}"#
        let rig = await ControlRig(server)
        await rig.control.setJogArmed(true)
        await rig.control.jog(.robot, axis: "x", amount: 1).first?.value
        XCTAssertEqual(rig.error, "errJogNotArmed")
        XCTAssertNil(rig.control.jogArmedUntil[1])
        XCTAssertEqual(rig.controller.screen, .main)
        XCTAssertEqual(rig.robot.x, 200, "the optimistic move is undone")
    }

    func testWhileOneJogIsOnTheWireTheNextTickIsDropped() async {
        let rig = await ControlRig()
        let first = rig.control.jogXYZ(.robot, dx: 1, dy: 0, dz: 0, step: 1)
        XCTAssertTrue(rig.control.jogXYZ(.robot, dx: 1, dy: 0, dz: 0, step: 1).isEmpty)
        for task in first { await task.value }
        XCTAssertEqual(rig.commands.count, 1)
    }

    func testNothingJogsWhileARobotRunsOrIsAwayOrDisabled() async {
        let changes: [(CellServer) -> Void] = [{ $0.playing = true }, { $0.online = false }, { $0.enabled = false }]
        for change in changes {
            let server = CellServer()
            change(server)
            let rig = await ControlRig(server)
            XCTAssertTrue(rig.control.jogXYZ(.robot, dx: 1, dy: 0, dz: 0, step: 1).isEmpty)
            XCTAssertNil(rig.control.jogBase(direction: 1, step: 1))
        }
    }

    func testAJogOfTheTableIsOneRelativeCommandCheckedAsAWhole() async {
        let server = CellServer()
        server.hasTable = true
        server.maxAmount = 5
        let rig = await ControlRig(server)
        await rig.control.refreshAccess()
        await rig.control.jog(.xytable, axis: "x", amount: 5).first?.value
        XCTAssertEqual(rig.names, ["table"])
        XCTAssertEqual(params(rig.commands[0])["x"] as? Double, 5)
        XCTAssertEqual(params(rig.commands[0])["mode"] as? String, "relative")
        XCTAssertEqual(rig.robot.xyX, 5)
        XCTAssertTrue(rig.control.jog(.xytable, axis: "x", amount: 6).isEmpty)
        XCTAssertEqual(rig.commands.count, 1)
    }

    func testAServerWithoutTheTableCommandGetsJogsAndIsRemembered() async {
        let server = CellServer()
        server.hasTable = true
        let rig = await ControlRig(server)
        rig.rig.transport.answer = { request in
            if request.url.hasSuffix("/command"), (request.body.flatMap { HydraClient.object($0) })?["command"] as? String == "table" {
                return reply(400, #"{"error":"Unknown command: table"}"#)
            }
            return try await server.answer(request)
        }
        await rig.control.jog(.xytable, axis: "x", amount: 5).first?.value
        await rig.control.jog(.xytable, axis: "x", amount: 5).first?.value
        XCTAssertEqual(rig.names, ["table", "jog", "jog"])
        XCTAssertEqual(params(rig.commands[1])["target"] as? String, "xytable")
    }

    func testAParol6JogCarriesOnePoseAndRefusesWhatItCannotReach() async {
        let server = CellServer()
        server.model = Parol6.modelName
        let rig = await ControlRig(server)
        for task in rig.control.jogXYZ(.robot, dx: 1, dy: 0, dz: 1, step: 10) { await task.value }
        XCTAssertEqual(rig.commands.compactMap { params($0)["axis"] as? String }.sorted(), ["x", "z"])
        XCTAssertEqual(params(rig.commands[0])["joints"] as? [String: Double], params(rig.commands[1])["joints"] as? [String: Double])
        XCTAssertEqual(rig.robot.x, 210)
        XCTAssertTrue(rig.control.jogXYZ(.robot, dx: 1, dy: 0, dz: 0, step: 5000).isEmpty)
        XCTAssertEqual(rig.error, "errJogOutOfReach")
        XCTAssertEqual(rig.commands.count, 2)
    }

    func testTheBaseTurnStopsAtTheRealLimit() async {
        let server = CellServer()
        server.model = Parol6.modelName
        let rig = await ControlRig(server)
        await rig.control.jogBase(direction: 1, step: 10)?.value
        XCTAssertEqual((params(rig.commands[0])["joints"] as? [String: Double])?["j1"], 10)
        XCTAssertEqual(params(rig.commands[0])["amount"] as? Double, 0)
        await rig.control.jogBase(direction: 1, step: 100)?.value
        XCTAssertEqual((params(rig.commands[1])["joints"] as? [String: Double])?["j1"], 97.4)
        XCTAssertNil(rig.control.jogBase(direction: 1, step: 100))
        XCTAssertEqual(rig.commands.count, 2)
    }

    // MARK: - Answers of the server

    func testEachRefusalReadsAsItsOwnAndUndoesTheChange() async {
        let cases: [(Int, String, String)] = [
            (409, #"{"error":"robot is claimed by bob","code":"other-account"}"#, "errRobotReserved"),
            (409, #"{"error":"x","code":"other-controller"}"#, "errClaimOtherController"),
            (409, #"{"error":"x","code":"controller-id-required"}"#, "errClaimControllerRequired"),
            (409, #"{"error":"x","code":"stale-sequence"}"#, "errStaleSequence"),
            (403, #"{"error":"role"}"#, "errPermissionDenied"),
            (403, #"{"error":"x","code":"enable-not-allowed"}"#, "errEnableNotAllowed"),
            (403, #"{"error":"x","code":"admin-required"}"#, "errAdminRequired"),
            (400, #"{"error":"bad"}"#, "errCommandRejected"),
            (423, #"{"error":"x","code":"robot-disabled"}"#, "errRobotDisabled"),
            (423, #"{"error":"x","code":"server-read-only"}"#, "errServerReadOnly"),
            (200, #"{"success":true,"warnings":[{"message":"out of range"}]}"#, "errCommandNotApplied"),
        ]
        for (status, body, wanted) in cases {
            let server = CellServer()
            server.commandStatus = status
            server.commandBody = body
            let rig = await ControlRig(server)
            await rig.control.play()?.value
            XCTAssertEqual(rig.error, wanted)
            XCTAssertFalse(rig.robot.isPlaying, "the optimistic play is undone: \(wanted)")
            XCTAssertEqual(rig.controller.screen, .main, wanted)
        }
    }

    func testPauseIsSentAsTheWantedState() async {
        let server = CellServer()
        server.playing = true
        let rig = await ControlRig(server)
        await rig.control.togglePause()?.value
        XCTAssertEqual(params(rig.commands[0])["paused"] as? Bool, true)
        XCTAssertTrue(rig.robot.isPaused)
    }

    func testSafeModeStopsTheRobotAndEnableBringsItBack() async {
        let server = CellServer()
        server.playing = true
        let rig = await ControlRig(server)
        await rig.control.disable()?.value
        XCTAssertEqual(rig.names, ["disable"])
        XCTAssertFalse(rig.robot.enabled)
        XCTAssertFalse(rig.robot.isPlaying)
        await rig.control.enable()?.value
        XCTAssertTrue(rig.robot.enabled)
    }

    func testADebouncedSliderSendsOnlyItsLastValue() async {
        let rig = await ControlRig()
        rig.control.setSpeed(100, acceleration: 100)
        let last = rig.control.setSpeed(9000, acceleration: 1)
        await last?.value
        await rig.settle()
        XCTAssertEqual(rig.names, ["speed"])
        XCTAssertEqual(params(rig.commands[0])["speed"] as? Double, 500)
        XCTAssertEqual(params(rig.commands[0])["acceleration"] as? Double, 10)
    }

    // MARK: - Blocks

    func testListenOnlyLetsOnlyTheStopsOut() async {
        let rig = await ControlRig()
        XCTAssertFalse(rig.control.listenOnly)
        rig.control.setListenOnly(true)
        XCTAssertNil(rig.control.play())
        XCTAssertTrue(rig.control.jog(.robot, axis: "x", amount: 1).isEmpty)
        XCTAssertNil(rig.control.setSpeed(100, acceleration: 100))
        XCTAssertNil(rig.control.toggleOutput("valves", index: 0))
        XCTAssertNil(rig.control.enable())
        XCTAssertNil(rig.control.homeReset())
        await rig.control.claimRobot()
        await rig.control.setJogArmed(true)
        XCTAssertTrue(rig.requests("/claim").isEmpty, "the transport refuses it")
        XCTAssertTrue(rig.requests("/jog-arm").isEmpty)
        XCTAssertTrue(rig.commands.isEmpty)
        await rig.control.stopRobot()?.value
        await rig.control.disable()?.value
        await rig.controller.stopAll()
        XCTAssertEqual(rig.names, ["stop", "disable"])
        XCTAssertEqual(rig.requests("/api/stop-all").count, 1)
        rig.control.setListenOnly(false)
        await rig.control.enable()?.value
        XCTAssertEqual(rig.names.last, "enable")
    }

    func testListenOnlyCanBeForOneServerAndIsKept() async {
        let prefs = MemoryPrefs()
        let rig = await ControlRig(prefs: prefs)
        rig.control.setListenOnlyThisServer(true)
        XCTAssertTrue(rig.control.listenOnly)
        XCTAssertFalse(rig.control.listenOnlyGeneral)
        XCTAssertNil(rig.control.play())
        let again = await ControlRig(prefs: prefs)
        XCTAssertTrue(again.control.listenOnly)
        again.control.setListenOnlyThisServer(false)
        XCTAssertFalse(again.control.listenOnly)
    }

    func testTheBlockOnSavedDataHoldsEverythingButTheStops() async {
        let cache = MemoryCache()
        let server = CellServer()
        let rig = await ControlRig(server, cache: cache, opens: false)
        XCTAssertFalse(rig.control.blockOnSavedData, "off by default")
        // a copy saved by a first run, then a server that does not answer the state
        let copy = StateCache(store: cache)
        copy.save(HydraClient.object(Data(server.settings.utf8)) ?? [:], scope: "operator@192.168.1.50:3000", at: Date())
        rig.rig.transport.answer = { request in
            if request.url.hasSuffix("/api/settings") { throw TransportError.unreachable }
            return try await server.answer(request)
        }
        rig.controller.leaveServer()
        await rig.controller.resume(rig.controller.savedServers[0])
        XCTAssertTrue(rig.controller.showingSavedData)
        await rig.control.play()?.value
        XCTAssertEqual(rig.names, ["play"], "with the block off it goes the normal way")
        rig.control.setBlockOnSavedData(true)
        XCTAssertTrue(rig.controller.showingSavedData)
        XCTAssertTrue(rig.control.jog(.robot, axis: "x", amount: 1).isEmpty)
        XCTAssertEqual(rig.error, "errSavedDataBlocked")
        XCTAssertNil(rig.control.enable())
        rig.control.setDeadManEnabled(true)
        XCTAssertNil(rig.control.press(1, target: .robot, axis: "x", direction: 1))
        XCTAssertEqual(rig.error, "errSavedDataBlocked")
        await rig.control.stopRobot()?.value
        await rig.control.disable()?.value
        XCTAssertEqual(rig.names, ["play", "stop", "disable"])
        XCTAssertTrue(rig.rig.prefs.bool(ControlPref.blockSavedData))
    }

    // MARK: - STOP

    func testAStopGoesOutUrgentWithoutRevisionAndIsRepeatedWhenNobodyAnswers() async {
        let rig = await ControlRig()
        await rig.control.play()?.value
        rig.server.silent = ["stop"]
        await rig.control.stopRobot()?.value
        XCTAssertEqual(rig.names, ["play", "stop", "stop", "stop"])
        XCTAssertEqual(rig.error, "errStopNotConfirmed")
        let stops = rig.commandRequests.dropFirst()
        XCTAssertTrue(stops.allSatisfy { $0.headers["If-Match"] == nil && $0.timeout == 2 })
        let numbers = rig.commands.dropFirst().compactMap { ($0["seq"] as? NSNumber)?.int64Value }
        XCTAssertEqual(numbers.count, 3)
        XCTAssertEqual(numbers, numbers.sorted())
    }

    func testAnOrdinaryCommandIsNotRepeated() async {
        let rig = await ControlRig()
        rig.server.silent = ["play"]
        await rig.control.play()?.value
        XCTAssertEqual(rig.names, ["play"])
        XCTAssertEqual(rig.error, "errTxError")
    }

    func testTheGlobalStopEndsTheArming() async {
        let server = CellServer()
        server.armRequired = true
        let rig = await ControlRig(server)
        await rig.control.setJogArmed(true)
        await rig.controller.stopAll()
        XCTAssertTrue(rig.control.jogArmedUntil.isEmpty)
    }

    func testAnUnconfirmedGlobalStopHoldsTheHomeResetAndTheHeldJogBack() async {
        let server = CellServer()
        server.stopAllStatus = 500
        let rig = await ControlRig(server)
        rig.control.setHomeResetEnabled(true)
        rig.control.setDeadManEnabled(true)
        await rig.controller.stopAll()
        XCTAssertTrue(rig.controller.stopUnconfirmed)
        XCTAssertEqual(rig.control.homeResetBlock(1), .stopPending)
        XCTAssertNil(rig.control.homeReset())
        XCTAssertEqual(rig.control.deadManBlock(1), .stopPending)
        XCTAssertTrue(rig.commands.isEmpty)
    }

    // MARK: - HOME/RESET

    func testHomeReset() async {
        let rig = await ControlRig()
        XCTAssertFalse(rig.control.homeResetEnabled)
        XCTAssertNil(rig.control.homeReset())
        XCTAssertTrue(rig.commands.isEmpty)
        rig.control.setHomeResetEnabled(true)
        XCTAssertEqual(rig.control.homeResetBlock(1), .none)
        await rig.control.homeReset()?.value
        XCTAssertEqual(rig.names, ["reset"])
        XCTAssertEqual(params(rig.commands[0])["target"] as? String, "robot")
        XCTAssertNotNil(rig.commands[0]["seq"])
        XCTAssertEqual(rig.robot.x, 0)
    }

    func testAServerWithoutResetIsRememberedAndThePoseComesBack() async {
        let server = CellServer()
        server.commandStatus = 400
        server.commandBody = #"{"error":"Unknown command: reset"}"#
        let rig = await ControlRig(server)
        rig.control.setHomeResetEnabled(true)
        await rig.control.homeReset()?.value
        XCTAssertEqual(rig.error, "homeResetNotSupported")
        XCTAssertEqual(rig.robot.x, 200)
        XCTAssertNil(rig.control.homeReset())
        XCTAssertEqual(rig.commands.count, 1)
    }

    // MARK: - Conditional writes

    func testTheRevisionTravelsAsIfMatchAndAMismatchReadsTheRobotAgain() async {
        let server = CellServer()
        server.commandBody = #"{"success":true,"revision":"rev-1"}"#
        let rig = await ControlRig(server)
        await rig.control.play()?.value
        await rig.control.play()?.value
        XCTAssertNil(rig.commandRequests[0].headers["If-Match"])
        XCTAssertEqual(rig.commandRequests[1].headers["If-Match"], "\"rev-1\"")
        await rig.control.jog(.robot, axis: "x", amount: 1).first?.value
        server.commandStatus = 412
        server.commandBody = #"{"error":"changed","code":"revision-mismatch","revision":"r5"}"#
        await rig.control.disable()?.value
        XCTAssertEqual(rig.error, "errRevisionChanged")
        XCTAssertEqual(rig.requests("/api/robot/1").count, 1)
        XCTAssertTrue(rig.robot.hasXYTable, "what the server says now is shown")
        XCTAssertEqual(rig.control.revisions.revision(of: 1), "r9")
    }

    func testAJogIsUnconditionalUnlessStrictAndAStopNeverCarriesIt() async {
        let server = CellServer()
        server.commandBody = #"{"success":true,"revision":"rev-1"}"#
        let rig = await ControlRig(server)
        await rig.control.play()?.value
        await rig.control.stopRobot()?.value
        await rig.control.jog(.robot, axis: "x", amount: 1).first?.value
        XCTAssertNil(rig.commandRequests[1].headers["If-Match"])
        XCTAssertNil(rig.commandRequests[2].headers["If-Match"])
        rig.control.setConditionalMode(.strict)
        await rig.control.jog(.robot, axis: "x", amount: 1).first?.value
        XCTAssertEqual(rig.commandRequests[3].headers["If-Match"], "\"rev-1\"")
    }

    // MARK: - Reservations

    func testReservingAndReleasingSendTheControllerIdAndReadTheListAgain() async {
        let server = CellServer()
        server.claimBody = #"{"success":true,"revision":"after-claim"}"#
        let rig = await ControlRig(server)
        await rig.control.claimRobot()
        await rig.control.releaseRobot()
        for suffix in ["/api/robot/1/claim", "/api/robot/1/release"] {
            let sent = rig.requests(suffix)
            XCTAssertEqual(sent.count, 1, suffix)
            XCTAssertEqual(sent.first?.headers["X-Controller-Id"], rig.control.controllerId, suffix)
            XCTAssertEqual(sent.first?.body.flatMap { HydraClient.object($0) }?["controllerId"] as? String, rig.control.controllerId, suffix)
        }
        XCTAssertNil(rig.requests("/claim").first?.headers["If-Match"])
        XCTAssertEqual(rig.requests("/release").first?.headers["If-Match"], "\"after-claim\"")
        XCTAssertFalse(rig.requests("/api/claims").isEmpty)
        XCTAssertNil(rig.error)
    }

    func testARefusedReservationSaysWhy() async {
        for (body, wanted) in [(#"{"error":"claimed by bob","code":"other-account"}"#, "errRobotReserved"),
                               (#"{"error":"x","code":"other-controller"}"#, "errClaimOtherController"),
                               (#"{"error":"x","code":"controller-id-required"}"#, "errClaimControllerRequired")] {
            let server = CellServer()
            server.claimStatus = 409
            server.claimBody = body
            let rig = await ControlRig(server)
            await rig.control.claimRobot()
            XCTAssertEqual(rig.error, wanted)
        }
    }

    func testTheListSaysWhereTheRobotStands() async {
        let rig = await ControlRig()
        XCTAssertEqual(rig.control.standing(1), .free)
        let mine = rig.control.controllerId
        for (owner, controller, wanted) in [("operator", mine, ClaimStanding.mineHere), ("operator", "ios-elsewhere", .mineElsewhere), ("bob", "x", .other)] {
            rig.server.claims = #"[{"robotId":1,"ownerUsername":"\#(owner)","controllerId":"\#(controller)","expiresAt":1}]"#
            await rig.control.refreshAccess()
            XCTAssertEqual(rig.control.standing(1), wanted)
        }
        XCTAssertTrue(rig.requests("/claim").isEmpty, "a reservation that ended is not brought back")
    }

    func testOnlyAnAdministratorTakesOverAndOnlyAHeldRobot() async {
        let held = #"[{"robotId":1,"ownerUsername":"bob","controllerId":"x","expiresAt":1}]"#
        let server = CellServer()
        server.role = "admin"
        server.claims = held
        let admin = await ControlRig(server)
        await admin.control.refreshAccess()
        XCTAssertTrue(admin.control.canTakeOver(1))
        await admin.control.takeOver()
        let sent = admin.requests("/claim").first
        XCTAssertEqual(sent?.body.flatMap { HydraClient.object($0) }?["force"] as? Bool, true)
        XCTAssertNil(sent?.headers["If-Match"])

        let other = CellServer()
        other.claims = held
        let operatorRig = await ControlRig(other)
        await operatorRig.control.refreshAccess()
        XCTAssertFalse(operatorRig.control.canTakeOver(1))
        await operatorRig.control.takeOver()
        XCTAssertTrue(operatorRig.requests("/claim").isEmpty)

        let free = CellServer()
        free.role = "admin"
        let freeRig = await ControlRig(free)
        await freeRig.control.refreshAccess()
        XCTAssertFalse(freeRig.control.canTakeOver(1))
    }

    func testAReservationHeldHereAboutToEndIsRenewed() async {
        let rig = await ControlRig()
        let soon = Int64(Date().timeIntervalSince1970 * 1000) + 60_000
        rig.server.claims = #"[{"robotId":1,"ownerUsername":"operator","controllerId":"\#(rig.control.controllerId)","expiresAt":\#(soon)}]"#
        await rig.control.refreshAccess()
        XCTAssertEqual(rig.requests("/api/robot/1/claim").count, 1)
    }

    func testAPushOfTheReservationsRestsThePoll() async {
        let rig = await ControlRig()
        rig.rig.sockets.last.say(#"{"type":"claims","claims":[{"robotId":1,"ownerUsername":"bob","controllerId":"x","expiresAt":1}]}"#)
        XCTAssertEqual(rig.control.standing(1), .other)
        let before = rig.requests("/api/claims").count
        await rig.control.refreshAccess(fromPoll: true)
        XCTAssertEqual(rig.requests("/api/claims").count, before)
    }

    // MARK: - Works

    func testAWorkIsLoadedWithTrajectoryAndNeverStarted() async {
        let rig = await ControlRig()
        await rig.control.loadWorkList(1)
        XCTAssertEqual(rig.control.workFiles, ["a.json"])
        await rig.control.loadWork(1, file: "a.json")
        XCTAssertEqual(rig.names, ["trajectory"])
        XCTAssertEqual(params(rig.commands[0])["selectedWorkFile"] as? String, "a.json")
        XCTAssertFalse(rig.robot.isPlaying)
    }

    func testABadWorkOrABusyRobotSendsNothing() async {
        let server = CellServer()
        server.work = "{}"
        let rig = await ControlRig(server)
        await rig.control.loadWork(1, file: "a.json")
        XCTAssertEqual(rig.error, "workInvalidFile")
        await rig.control.loadWork(1, file: "../a.json")
        XCTAssertEqual(rig.error, "workLoadFailed")
        XCTAssertTrue(rig.commands.isEmpty)
        let playing = CellServer()
        playing.playing = true
        let busy = await ControlRig(playing)
        await busy.control.loadWork(1, file: "a.json")
        XCTAssertEqual(busy.error, "workBlockedPlaying")
        XCTAssertTrue(busy.requests("/a.json").isEmpty, "refused before anything is read")
    }

    // MARK: - Held jog

    func testTheSwitchesStartAsTheContractSaysAndAPressWhileOffSendsNothing() async {
        let rig = await ControlRig()
        XCTAssertFalse(rig.control.deadManEnabled)
        XCTAssertTrue(rig.control.linkIndicator)
        XCTAssertTrue(rig.control.blockOnBadLink)
        XCTAssertTrue(rig.control.confirmPlay)
        XCTAssertNil(rig.control.press(1, target: .robot, axis: "x", direction: 1))
        XCTAssertEqual(rig.error, "deadManBlockedOff")
        XCTAssertTrue(rig.commands.isEmpty)
    }

    private func held(_ rig: ControlRig, direction: Int = 1) async {
        rig.control.setDeadManEnabled(true)
        await rig.control.press(1, target: .robot, axis: "x", direction: direction)?.value
        await until { rig.names.contains("jogHeartbeat") }
    }

    private func ended(_ rig: ControlRig) async {
        await until { rig.names.contains("jogStop") && !rig.control.deadMan.stopping }
    }

    func testPressAndReleaseSendStartHeartbeatsAndStop() async {
        let rig = await ControlRig()
        await held(rig, direction: -1)
        XCTAssertEqual(rig.control.held, [1])
        XCTAssertEqual(params(rig.commands[0])["velocity"] as? Double, -20)
        rig.control.release(1)
        await ended(rig)
        XCTAssertTrue(rig.control.held.isEmpty)
        XCTAssertEqual(rig.names.first, "jogStart")
        XCTAssertEqual(rig.names.last, "jogStop")
        XCTAssertNil(rig.error)
    }

    func testAReleaseBeforeTheStartLeavesSendsNothing() async {
        let rig = await ControlRig()
        rig.control.setDeadManEnabled(true)
        let task = rig.control.press(1, target: .robot, axis: "x", direction: 1)
        rig.control.release(1)
        await task?.value
        await rig.settle()
        XCTAssertTrue(rig.commands.isEmpty)
    }

    func testEveryWayOutEndsAHeldJog() async {
        let ways: [(String, @MainActor (ControlRig) async -> Void)] = [
            ("global STOP", { await $0.controller.stopAll() }),
            ("stop of the robot", { await $0.control.stopRobot()?.value }),
            ("safe mode", { await $0.control.disable()?.value }),
            ("listen only", { $0.control.setListenOnly(true) }),
            ("listen only for this server", { $0.control.setListenOnlyThisServer(true) }),
            ("the switch", { $0.control.setDeadManEnabled(false) }),
            ("another robot", { $0.control.select(2) }),
            ("leaving the page", { $0.control.interrupt() }),
            ("background", { $0.controller.pause() }),
            ("the link lost", { $0.rig.sockets.last.end() }),
            ("signing out", { $0.controller.logout() }),
            ("another server", { $0.controller.leaveServer() }),
        ]
        for (name, way) in ways {
            let rig = await ControlRig()
            await held(rig)
            await way(rig)
            await ended(rig)
            XCTAssertTrue(rig.names.contains("jogStop"), name)
            XCTAssertFalse(rig.control.deadMan.anyRunning, name)
            XCTAssertTrue(rig.control.held.isEmpty, name)
            XCTAssertNotEqual(rig.error, "deadManStopNotConfirmed", name)
            let stop = rig.commandRequests.last { ($0.body.flatMap { HydraClient.object($0) })?["command"] as? String == "jogStop" }
            XCTAssertNotNil(stop?.headers["Authorization"], "the stop leaves with the session it was held with: \(name)")
        }
    }

    func testAStopBeforeTheStartLeavesSendsNoStart() async {
        let ways: [@MainActor (ControlRig) async -> Void] = [
            { await $0.controller.stopAll() },
            { await $0.control.stopRobot()?.value },
            { $0.controller.pause() },
            { $0.control.interrupt() },
        ]
        for way in ways {
            let rig = await ControlRig()
            rig.control.setDeadManEnabled(true)
            let task = rig.control.press(1, target: .robot, axis: "x", direction: 1)
            await way(rig)
            await task?.value
            await rig.settle()
            XCTAssertFalse(rig.names.contains("jogStart"))
            XCTAssertTrue(rig.control.held.isEmpty)
        }
    }

    func testARobotThatPlaysALostLinkOrASlowOneAreRefused() async {
        let server = CellServer()
        server.playing = true
        let playing = await ControlRig(server)
        playing.control.setDeadManEnabled(true)
        XCTAssertNil(playing.control.press(1, target: .robot, axis: "x", direction: 1))
        XCTAssertEqual(playing.error, "deadManBlockedMoving")

        let rig = await ControlRig()
        rig.control.setDeadManEnabled(true)
        rig.rig.sockets.last.end()
        XCTAssertNil(rig.control.press(1, target: .robot, axis: "x", direction: 1))
        XCTAssertEqual(rig.error, "errNotConnected")

        let slow = await ControlRig()
        slow.control.setDeadManEnabled(true)
        await slow.control.probeLink()
        XCTAssertNotNil(slow.control.link.lastMs)
        slow.control.now = { Date().addingTimeInterval(10) }   // the last answer is old now
        XCTAssertEqual(slow.control.deadManBlock(1), .badLink)
        slow.control.setBlockOnBadLink(false)
        XCTAssertEqual(slow.control.deadManBlock(1), .none)
    }

    func testAServerWithoutTheHeldJogIsRemembered() async {
        let server = CellServer()
        server.commandStatus = 400
        server.commandBody = #"{"error":"Unknown command: jogStart"}"#
        let rig = await ControlRig(server)
        rig.control.setDeadManEnabled(true)
        await rig.control.press(1, target: .robot, axis: "x", direction: 1)?.value
        XCTAssertEqual(rig.error, "errTxError")
        await until { !rig.control.deadMan.stopping }
        XCTAssertFalse(rig.control.deadMan.anyRunning)
        XCTAssertEqual(rig.control.deadManBlock(1), .notSupported)
        XCTAssertFalse(rig.names.contains("jogHeartbeat"))
    }
}

// MARK: - The runner of the held jog

@MainActor
private final class JogServer {
    var log: [(command: String, params: [String: Any])] = []
    var heartbeatError: Error?
    var hangHeartbeats = false
    var stopFailures = 0
    var startError: Error?

    func post(_ robotId: Int, _ command: String, _ params: [String: Any]) async throws {
        log.append((command, params))
        switch command {
        case "jogStart": if let startError { throw startError }
        case "jogHeartbeat":
            if hangHeartbeats { try await Task.sleep(nanoseconds: 30_000_000_000) }
            if let heartbeatError { throw heartbeatError }
        default:
            if stopFailures > 0 {
                stopFailures -= 1
                throw TransportError.unreachable
            }
        }
    }

    func count(_ command: String) -> Int { log.filter { $0.command == command }.count }
}

@MainActor
final class DeadManRunnerTests: XCTestCase {
    private var ends: [(reason: DeadManEnd, confirmed: Bool)] = []

    /// Longer limits than the real ones, so a slow machine does not lose the link by itself.
    private var patient: DeadManSettings {
        var s = DeadManSettings()
        s.heartbeatMs = 20
        s.serverTimeoutMs = 2000
        s.stopRetryPauseMs = 5
        return s
    }

    private func runner(_ server: JogServer, _ settings: DeadManSettings) -> DeadManRunner {
        let made = DeadManRunner(settings: settings) { try await server.post($0, $1, $2) }
        made.onEnded = { [weak self] _, reason, confirmed in self?.ends.append((reason, confirmed)) }
        return made
    }

    private func finished() async { await until { !self.ends.isEmpty } }

    func testStartHeartbeatsAndStopOnReleaseWithOneSession() async throws {
        let server = JogServer()
        let runner = runner(server, patient)
        try await runner.start(2, target: "robot", axis: "z", velocity: 5000)
        XCTAssertTrue(runner.isRunning(2))
        // a second start of the same robot does nothing
        try await runner.start(2, target: "robot", axis: "z", velocity: 10)
        XCTAssertEqual(server.count("jogStart"), 1)
        await until { server.count("jogHeartbeat") >= 3 }
        runner.release(2)
        await finished()
        XCTAssertEqual(ends.first?.reason, .released)
        XCTAssertEqual(ends.first?.confirmed, true)
        XCTAssertEqual(server.log.first?.params["velocity"] as? Double, 100)
        XCTAssertEqual(server.log.first?.params["heartbeatMs"] as? Int, 20)
        XCTAssertEqual(Set(server.log.compactMap { $0.params["sessionId"] as? String }).count, 1)
        let sequences = server.log.compactMap { $0.params["sequence"] as? Int }
        XCTAssertEqual(sequences, Array(1...sequences.count))
        XCTAssertEqual(server.log.last?.command, "jogStop")
        let beats = server.count("jogHeartbeat")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(server.count("jogHeartbeat"), beats, "no heartbeat after the release")
        XCTAssertFalse(runner.isRunning(2))
    }

    private func ending(_ change: (JogServer) -> Void, settings: DeadManSettings, linkAllows: Bool = true) async throws -> (JogServer, DeadManEnd?) {
        ends = []
        let server = JogServer()
        change(server)
        let runner = runner(server, settings)
        runner.linkAllows = { linkAllows }
        try await runner.start(1, target: "robot", axis: "x", velocity: 20)
        await finished()
        return (server, ends.first?.reason)
    }

    func testFailedHeartbeatsStopTheAxis() async throws {
        let (server, reason) = try await ending({ $0.heartbeatError = TransportError.unreachable }, settings: patient)
        XCTAssertEqual(reason, .linkLost)
        XCTAssertEqual(server.count("jogHeartbeat"), 2)
        XCTAssertEqual(server.count("jogStop"), 1)
    }

    func testAHeartbeatThatNeverAnswersStopsTheAxis() async throws {
        let (server, reason) = try await ending({ $0.hangHeartbeats = true }, settings: DeadManSettings())
        XCTAssertEqual(reason, .linkLost)
        XCTAssertEqual(server.count("jogStop"), 1)
    }

    func testARefusalEndsAtOnceButARateLimitOnlyCountsAsMissed() async throws {
        let (server, reason) = try await ending({ $0.heartbeatError = ApiError(status: 403) }, settings: patient)
        XCTAssertEqual(reason, .serverRefused)
        XCTAssertEqual(server.count("jogHeartbeat"), 1)
        for status in [408, 429, 500] {
            let (limited, why) = try await ending({ $0.heartbeatError = ApiError(status: status) }, settings: patient)
            XCTAssertEqual(why, .linkLost, "\(status)")
            XCTAssertEqual(limited.count("jogHeartbeat"), 2, "\(status)")
        }
    }

    func testABadLinkAndAHoldTooLongEnd() async throws {
        let (_, bad) = try await ending({ _ in }, settings: patient, linkAllows: false)
        XCTAssertEqual(bad, .badLink)
        var short = patient
        short.maxHoldMs = 100
        let (_, long) = try await ending({ _ in }, settings: short)
        XCTAssertEqual(long, .tooLong)
    }

    func testInterruptingStopsEveryAxis() async throws {
        let server = JogServer()
        let runner = runner(server, patient)
        try await runner.start(1, target: "robot", axis: "x", velocity: 20)
        try await runner.start(2, target: "robot", axis: "x", velocity: 20)
        runner.interrupt()
        XCTAssertFalse(runner.anyRunning)
        await runner.waitStops()
        XCTAssertEqual(server.count("jogStop"), 2)
        XCTAssertEqual(ends.map { $0.reason }, [.interrupted, .interrupted])
    }

    func testAStopThatDoesNotArriveIsTriedAgainAndReported() async throws {
        let server = JogServer()
        server.stopFailures = 10
        let runner = runner(server, patient)
        try await runner.start(1, target: "robot", axis: "x", velocity: 20)
        runner.release(1)
        await finished()
        XCTAssertEqual(server.count("jogStop"), 3)
        XCTAssertEqual(ends.first?.confirmed, false)
    }

    func testAStartThatFailsLeavesNothingRunningAndIsToldToStop() async {
        let server = JogServer()
        server.startError = ApiError(status: 409)
        let runner = runner(server, patient)
        do {
            try await runner.start(1, target: "robot", axis: "x", velocity: 20)
            XCTFail("the start was refused")
        } catch {}
        XCTAssertFalse(runner.anyRunning)
        await runner.waitStops()
        XCTAssertEqual(server.count("jogHeartbeat"), 0)
        XCTAssertEqual(server.count("jogStop"), 1)
        XCTAssertTrue(ends.isEmpty)
    }
}
