// HYDRA-UMC-IOS-CONTROL - the live state: the socket and its retries, changes of one robot, the saved copy, no connection, the line of Home.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest
@testable import HydraCore

@MainActor
final class LiveTests: XCTestCase {
    private let full = #"{"type":"settings","payload":{"controllers":[{"id":"c1","robots":[{"id":1,"name":"A1","online":true},{"id":2,"name":"A2","online":true}]}]}}"#

    func testTheSocketCarriesTheTokenAsASubprotocolAndNeverInTheAddress() async {
        let rig = Rig()
        await rig.signIn()
        XCTAssertEqual(rig.sockets.last.url, "wss://192.168.1.50:3000/ws?remoteApiVersion=2")
        XCTAssertEqual(rig.sockets.last.protocols, ["hydra.bearer", "t1"])
        XCTAssertFalse(rig.sockets.last.url.contains("t1"))
        XCTAssertEqual(rig.controller.link, .connected)
    }

    func testSettingsAndDeltasChangeWhatIsShown() async {
        let rig = Rig()
        await rig.signIn()
        rig.sockets.last.say(full)
        XCTAssertEqual(HomeState.of(link: rig.controller.link, robots: rig.controller.robots), .ready(2))
        rig.sockets.last.say(#"{"type":"delta","schema":2,"controllerId":"c1","robotId":2,"patch":{"enabled":false}}"#)
        XCTAssertEqual(rig.controller.robots.map(\.enabled), [true, false])
        XCTAssertEqual(rig.controller.robots[1].name, "A2", "what the change does not name stays")
        XCTAssertEqual(HomeState.of(link: rig.controller.link, robots: rig.controller.robots), .safeMode(1))
    }

    func testAChangeOfAnUnknownRobotReadsTheWholeStateAgain() async {
        let rig = Rig()
        await rig.signIn()
        let reads = rig.transport.paths().filter { $0 == "/api/settings" }.count
        rig.sockets.last.say(#"{"type":"delta","schema":2,"controllerId":"c1","robotId":9,"patch":{"online":true}}"#)
        await until { rig.transport.paths().filter { $0 == "/api/settings" }.count > reads }
        XCTAssertEqual(rig.transport.paths().filter { $0 == "/api/settings" }.count, reads + 1)
        XCTAssertEqual(rig.controller.robots.map(\.robotId), [1, 2], "a partial change never creates a robot")
    }

    func testALostLinkIsRetriedWithGrowingPausesAndTheDataIsSaidToBeOld() async {
        let rig = Rig()
        await rig.signIn()
        rig.sockets.opens = false
        rig.sockets.last.end()
        XCTAssertEqual(rig.controller.link, .disconnected)
        XCTAssertTrue(rig.controller.isStale)
        for expected in [3.0, 3.0, 6.0, 12.0, 24.0, 30.0] {
            let waiting = rig.timers.waiting.filter { $0 != 1 && $0 != 5 }
            XCTAssertEqual(waiting.count, 1)
            XCTAssertEqual(waiting.first ?? 0, expected, accuracy: 0.5)
            let before = rig.sockets.made.count
            rig.timers.fire { $0 != 1 && $0 != 5 }
            XCTAssertEqual(rig.sockets.made.count, before + 1)
            XCTAssertEqual(rig.controller.link, .connecting)
            rig.sockets.last.end()
        }
    }

    func testARefusedTokenIsRenewedOnceAndTheSocketOpenedWithTheNewOne() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/refresh") { return reply(200, #"{"success":true,"token":"t2"}"#) }
            return try await healthy(request)
        })
        await rig.signIn()
        rig.sockets.last.say(#"{"error":"Access denied: invalid token"}"#)
        await until { rig.sockets.made.count == 2 }
        XCTAssertEqual(rig.sockets.last.protocols, ["hydra.bearer", "t2"])
        XCTAssertEqual(rig.controller.screen, .main)
        // refused again at once: renewing is not curing anything
        rig.sockets.last.end(1008)
        XCTAssertEqual(rig.controller.screen, .login)
        XCTAssertEqual(rig.controller.message?.key, "errSessionEnded")
        XCTAssertNil(rig.cache.data)
    }

    func testARefusedTokenThatCannotBeRenewedSignsOutAndIsNotRetried() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/refresh") { return reply(401) }
            return try await healthy(request)
        })
        await rig.signIn()
        rig.sockets.last.end(1008)
        await until { rig.controller.screen == .login }
        XCTAssertEqual(rig.controller.screen, .login)
        XCTAssertEqual(rig.sockets.made.count, 1)
        XCTAssertTrue(rig.secrets.stored("hydra_token").isEmpty)
        XCTAssertTrue(rig.timers.waiting.isEmpty)
    }

    func testBackgroundClosesTheSocketAndComingBackOpensIt() async {
        let rig = Rig()
        await rig.signIn()
        let first = rig.sockets.last
        rig.controller.pause()
        XCTAssertTrue(first.closed)
        XCTAssertEqual(rig.controller.link, .disconnected)
        XCTAssertTrue(rig.timers.waiting.isEmpty, "nothing keeps running in the background")
        // what the old socket still says is not taken
        first.say(#"{"type":"settings","payload":{"controllers":[]}}"#)
        XCTAssertEqual(rig.controller.robots.count, 2)
        await rig.controller.resumeLive()
        XCTAssertEqual(rig.sockets.made.count, 2)
        XCTAssertEqual(rig.controller.link, .connected)
    }

    func testTheStateIsSavedWithoutSecretsAndShownWithoutAServer() async {
        let cache = MemoryCache()
        let secrets = MemorySecrets()
        let prefs = MemoryPrefs()
        let rig = Rig(secrets: secrets, prefs: prefs, cache: cache)
        await rig.signIn()
        rig.sockets.last.say(#"{"type":"settings","payload":{"controllers":[{"id":"c1","cameras":[{"id":1,"ipUsername":"cam","ipPassword":"sample"}],"robots":[{"id":1,"name":"Saved","online":true}]}]}}"#)
        XCTAssertNil(cache.data, "written after a quiet second, not at once")
        rig.timers.fire { $0 == 1 }
        XCTAssertTrue(cache.text.contains("Saved"))
        XCTAssertFalse(cache.text.contains("ipPassword"))
        XCTAssertFalse(cache.text.contains("ipUsername"))
        XCTAssertFalse(cache.text.contains("t1"))

        let away = Rig({ _ in throw TransportError.unreachable }, secrets: secrets, prefs: prefs, cache: cache, opens: false)
        await away.controller.start()
        XCTAssertEqual(away.controller.screen, .main)
        XCTAssertEqual(away.controller.robots.map(\.name), ["Saved"])
        XCTAssertTrue(away.controller.showingSavedData)
        XCTAssertTrue(away.controller.isStale)
        XCTAssertEqual(away.controller.stateTime, Date(timeIntervalSince1970: 1_000_000))
        away.sockets.last.end()
        XCTAssertEqual(HomeState.of(link: away.controller.link, robots: away.controller.robots), .notConnected)
    }

    func testSigningOutErasesTheSavedState() async {
        let rig = Rig()
        await rig.signIn()
        rig.timers.fire { $0 == 1 }
        XCTAssertNotNil(rig.cache.data)
        rig.controller.logout()
        XCTAssertNil(rig.cache.data)
        XCTAssertTrue(rig.controller.robots.isEmpty)
        XCTAssertTrue(rig.timers.waiting.isEmpty)
    }

    func testTheCopyOfOneAccountIsNeverShownToAnother() {
        let cache = MemoryCache()
        let states = StateCache(store: cache)
        let address = ServerAddress(host: "192.168.1.50", port: 3000)
        states.save(["controllers": []], scope: StateCache.scope(address: address, username: "ana"), at: Date())
        states.clear(scope: StateCache.scope(address: address, username: "bo"))
        XCTAssertNotNil(cache.data)
        XCTAssertNil(states.load(scope: StateCache.scope(address: ServerAddress(host: "192.168.1.51", port: 3000), username: "ana")))
        XCTAssertNil(cache.data)
    }

    func testTheStopMarksTheStoppedRobotsAndWorksWithoutALink() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/settings") { throw TransportError.unreachable }
            return try await healthy(request)
        }, opens: false)
        await rig.signIn()
        rig.sockets.last.end()
        await rig.controller.stopAll()
        XCTAssertEqual(rig.controller.stopResult?.stoppedCount, 2)
        XCTAssertFalse(rig.controller.stopUnconfirmed)

        var cell = CellState(["controllers": [["id": "c1", "robots": [["id": 1, "playbackState": ["isPlaying": true, "playing": true]]]]]])
        XCTAssertTrue(cell.robots[0].isMoving)
        cell.markStopped(controllerId: "c1", robotId: 1)
        XCTAssertFalse(cell.robots[0].isPlaying)
    }

    func testMetricsAreReadWithTheSession() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/system/metrics") { return reply(200, #"{"cpu_load":7,"memory_usage":30,"temp":51.2,"temp_is_real":false,"uptime":93784}"#) }
            return try await healthy(request)
        })
        await rig.signIn()
        await rig.controller.pollMetrics()
        XCTAssertEqual(rig.controller.metrics?.cpuLoad, 7)
        XCTAssertNil(rig.controller.metrics?.temperature)
        XCTAssertEqual(SystemMetrics.uptimeText(93784), "1d 2h 3m")
        XCTAssertEqual(rig.transport.requests.last?.headers["Authorization"], "Bearer t1")
    }

    func testTheProgressOfAFlashIsOnlyShownWhileTheServerSendsIt() async {
        let rig = Rig()
        await rig.signIn()
        rig.sockets.last.say(#"{"type":"canota_progress","payload":{"phase":"entering_bootloader","percent":140,"pages_sent":-1}}"#)
        XCTAssertEqual(rig.controller.canOta?.percent, 100)
        XCTAssertNil(rig.controller.canOta?.pagesSent)
        XCTAssertEqual(rig.controller.canOta?.phase.textKey, "canOtaPhaseEnteringBootloader")
        rig.sockets.last.say(#"{"type":"canota_progress","payload":{"phase":"unknown"}}"#)
        XCTAssertEqual(rig.controller.canOta?.phase, .enteringBootloader)
        rig.sockets.last.end()
        XCTAssertNil(rig.controller.canOta)
        let english = Translator.load("en")
        for phase in ["connecting", "entering_bootloader", "erasing_fram", "transferring", "verifying", "rebooting", "done", "error"] {
            XCTAssertNotNil(english[CanOtaProgress.Phase(rawValue: phase)?.textKey ?? ""], phase)
        }
    }

    func testTheWorstThingWinsOnHome() {
        func robot(_ values: [String: Any]) -> RobotInfo { RobotInfo(controllerId: "c1", robotId: 1, raw: values) }
        let moving = robot(["online": true, "playbackState": ["isPlaying": true]])
        let away = robot(["online": false])
        let safe = robot(["online": false, "enabled": false])
        XCTAssertEqual(HomeState.of(link: .connecting, robots: [safe]), .connecting)
        XCTAssertEqual(HomeState.of(link: .connected, robots: []), .noRobots)
        XCTAssertEqual(HomeState.of(link: .connected, robots: [moving, away, safe]), .safeMode(1))
        XCTAssertEqual(HomeState.of(link: .connected, robots: [moving, away]), .offline(1))
        XCTAssertEqual(HomeState.of(link: .connected, robots: [moving]), .moving(1))
        XCTAssertEqual(SetupSteps.of(server: true, controller: true, robot: false).pending, [.robot])
        XCTAssertEqual(SetupSteps.of(server: true, controller: nil, robot: nil).total, 1)
    }
}
