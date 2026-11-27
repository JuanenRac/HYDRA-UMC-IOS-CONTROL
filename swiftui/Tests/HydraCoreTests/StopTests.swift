// HYDRA-UMC-IOS-CONTROL - the global STOP: what is sent, what is retried, and when the app must say it is not confirmed.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest
@testable import HydraCore

/// Counts calls from the concurrent closure of a fake server.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}

@MainActor
final class StopTests: XCTestCase {
    private func stops(_ rig: Rig) -> [HttpRequest] { rig.transport.requests.filter { $0.url.hasSuffix("/api/stop-all") } }

    func testOneTapSendsOneStopWithTheSession() async {
        let rig = Rig()
        await rig.signIn()
        await rig.controller.stopAll()
        XCTAssertEqual(stops(rig).count, 1)
        XCTAssertEqual(stops(rig)[0].method, "POST")
        XCTAssertEqual(stops(rig)[0].headers["Authorization"], "Bearer t1")
        XCTAssertEqual(stops(rig)[0].headers["X-Hydra-Client"], "ios/0.0.1")
        XCTAssertEqual(stops(rig)[0].timeout, 2)
        XCTAssertEqual(rig.controller.stopResult?.stoppedCount, 2)
        XCTAssertEqual(rig.controller.stopResult?.needsAttention, false)
        XCTAssertFalse(rig.controller.stopUnconfirmed)
    }

    func testNoStopWithoutASession() async {
        let rig = Rig()
        await rig.controller.start()
        await rig.controller.stopAll()
        XCTAssertFalse(rig.controller.showsStop)
        XCTAssertEqual(stops(rig).count, 0)
    }

    func testANetworkFailureIsTriedOnceMoreAndThenSaidNotConfirmed() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/stop-all") { throw TransportError.unreachable }
            return try await healthy(request)
        })
        await rig.signIn()
        await rig.controller.stopAll()
        XCTAssertEqual(stops(rig).count, 2)
        XCTAssertTrue(rig.controller.stopUnconfirmed)
        XCTAssertNil(rig.controller.stopResult)
        XCTAssertEqual(rig.controller.stopsInFlight, 0)
    }

    func testALaterAnsweredStopClearsTheNotConfirmedState() async {
        let counter = Counter()
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/stop-all"), counter.next() <= 2 { throw TransportError.timeout }
            return try await healthy(request)
        })
        await rig.signIn()
        await rig.controller.stopAll()
        XCTAssertTrue(rig.controller.stopUnconfirmed)
        await rig.controller.stopAll()
        XCTAssertFalse(rig.controller.stopUnconfirmed)
        XCTAssertEqual(rig.controller.stopResult?.stoppedCount, 2)
    }

    func testAServerErrorIsNotRetriedAndIsNotConfirmed() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/stop-all") { return reply(500) }
            return try await healthy(request)
        })
        await rig.signIn()
        await rig.controller.stopAll()
        XCTAssertEqual(stops(rig).count, 1)
        XCTAssertTrue(rig.controller.stopUnconfirmed)
    }

    func testAnAnswerThatIsNotJsonIsNotConfirmed() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/stop-all") { return reply(200, "<html>") }
            return try await healthy(request)
        })
        await rig.signIn()
        await rig.controller.stopAll()
        XCTAssertTrue(rig.controller.stopUnconfirmed)
    }

    func testRateLimitAndMissingRouteStopRobotByRobot() async {
        for status in [429, 404] {
            let rig = Rig({ request in
                if request.url.hasSuffix("/api/stop-all") { return reply(status) }
                if request.url.hasSuffix("/api/robot/2/command") { return reply(409, #"{"code":"other-account"}"#) }
                return try await healthy(request)
            })
            await rig.signIn()
            await rig.controller.stopAll()
            let commands = rig.transport.requests.filter { $0.url.hasSuffix("/command") }
            XCTAssertEqual(commands.count, 2, "status \(status)")
            for command in commands {
                let body = HydraClient.object(command.body ?? Data())
                XCTAssertEqual(body?["command"] as? String, "stop")
                XCTAssertNotNil(body?["seq"])
                XCTAssertEqual(command.headers["X-Controller-Id"], body?["controllerId"] as? String)
            }
            XCTAssertEqual(rig.controller.stopResult?.viaFallback, true)
            XCTAssertEqual(rig.controller.stopResult?.stoppedCount, 1)
            XCTAssertEqual(rig.controller.stopResult?.failedCount, 1)
            XCTAssertEqual(rig.controller.stopResult?.needsAttention, true)
        }
    }

    func testTheFallbackWithNoKnownRobotNeverReportsSuccess() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/stop-all") { return reply(404) }
            if request.url.hasSuffix("/api/settings") { return reply(200, #"{"controllers":[]}"#) }
            return try await healthy(request)
        })
        await rig.signIn()
        await rig.controller.stopAll()
        XCTAssertTrue(rig.controller.stopUnconfirmed)
        XCTAssertNil(rig.controller.stopResult)
    }

    func testAnExpiredSessionIsRenewedAndTheStopRepeated() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/stop-all"), request.headers["Authorization"] == "Bearer t1" { return reply(401) }
            if request.url.hasSuffix("/api/refresh") { return reply(200, #"{"success":true,"token":"t2"}"#) }
            return try await healthy(request)
        })
        await rig.signIn()
        await rig.controller.stopAll()
        XCTAssertEqual(stops(rig).map { $0.headers["Authorization"] }, ["Bearer t1", "Bearer t2"])
        XCTAssertEqual(rig.controller.stopResult?.stoppedCount, 2)
    }

    func testASessionThatCannotBeRenewedSignsOutAndSaysTheStopWasNotConfirmed() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/stop-all") || request.url.hasSuffix("/api/refresh") { return reply(401) }
            return try await healthy(request)
        })
        await rig.signIn()
        await rig.controller.stopAll()
        XCTAssertEqual(rig.controller.screen, .login)
        XCTAssertEqual(rig.controller.message?.key, "errStopSessionEnded")
    }

    func testAnswerParsingKeepsDoubtsVisible() {
        let result = StopAllResult(json: ["success": true, "persisted": false, "robots": [["robotId": 3, "stopped": true, "reservedBy": "ana"]]])
        XCTAssertEqual(result.stoppedCount, 1)
        XCTAssertEqual(result.robots[0].name, "3")
        XCTAssertEqual(result.robots[0].reservedBy, "ana")
        XCTAssertTrue(result.needsAttention)
        XCTAssertTrue(StopAllResult(json: [:]).needsAttention)
    }

    func testSequenceAlwaysRises() {
        let sequence = CommandSequence(clock: { 100 })
        XCTAssertEqual([sequence.next(), sequence.next(), sequence.next()], [100, 101, 102])
    }

    func testStopPlacement() {
        let button = StopLayout.button(screenWidth: 390, safeTop: 47, safeRight: 0)
        XCTAssertEqual(button, StopLayout.Frame(x: 274, y: 53, width: 104, height: 48))
        let banner = StopLayout.banner(screenWidth: 390, screenHeight: 844, safeTop: 47, contentHeight: 900)
        XCTAssertGreaterThanOrEqual(banner.y, button.y + button.height)
        XCTAssertLessThanOrEqual(banner.height, 844 * 0.4 + 0.001)
    }

    func testTheBarHasFivePlacesAndControlCarriesTheRoundStop() {
        XCTAssertEqual(MainTab.allCases, [.home, .control, .cameras, .alerts, .more])
        XCTAssertEqual(MainTab.allCases.filter(\.hasRoundStop), [.control])
    }
}
