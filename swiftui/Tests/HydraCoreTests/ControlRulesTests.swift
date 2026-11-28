// HYDRA-UMC-IOS-CONTROL - the rules of control, one by one, with the same cases as the tests of the published app.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest
@testable import HydraCore

final class ControlRulesTests: XCTestCase {
    private func contractFile() throws -> [String: Any] {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { folder.deleteLastPathComponent() }
        let data = try Data(contentsOf: folder.appendingPathComponent("docs/robot_command_contract.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheConstantsAreTheOnesOfTheContractFile() throws {
        let file = try contractFile()
        let commands = try XCTUnwrap(file["commands"] as? [[String: Any]])
        let numbered = Set(commands.filter { $0["numbered"] as? Bool == true }.compactMap { $0["name"] as? String })
        let continuous = Set(commands.filter { $0["continuous"] as? Bool == true }.compactMap { $0["name"] as? String })
        XCTAssertEqual(Contract.numbered, numbered.union(["joints"]))
        XCTAssertEqual(Contract.continuous, continuous)
        func section(_ name: String) -> [String: Any] { file[name] as? [String: Any] ?? [:] }
        func number(_ name: String, _ key: String) -> Double? { (section(name)[key] as? NSNumber)?.doubleValue }
        XCTAssertEqual(number("limits", "speedMin"), Contract.speedMin)
        XCTAssertEqual(number("limits", "speedMax"), Contract.speedMax)
        XCTAssertEqual(number("limits", "jogStepMax"), Contract.jogStepMax)
        XCTAssertEqual(section("homeReset")["enabledByDefault"] as? Bool, Contract.homeResetEnabledByDefault)
        XCTAssertEqual(number("homeReset", "confirmSteps"), Double(Contract.homeResetConfirmSteps))
        XCTAssertEqual(number("homeReset", "confirmWindowMs"), Contract.homeResetConfirmWindow * 1000)
        let jog = DeadManSettings()
        XCTAssertEqual(section("deadManJog")["enabledByDefault"] as? Bool, Contract.deadManEnabledByDefault)
        for (key, value) in [("heartbeatMs", jog.heartbeatMs), ("serverTimeoutMs", jog.serverTimeoutMs), ("maxMissedHeartbeats", jog.maxMissedHeartbeats),
                             ("maxHoldMs", jog.maxHoldMs), ("stopAttempts", jog.stopAttempts), ("stopRetryPauseMs", jog.stopRetryPauseMs), ("stopTimeoutMs", jog.stopTimeoutMs)] {
            XCTAssertEqual(number("deadManJog", key), Double(value), key)
        }
        XCTAssertEqual(number("deadManJog", "velocityDefault"), DeadManSettings.velocityDefault)
        XCTAssertEqual(number("deadManJog", "velocityMin"), DeadManSettings.velocityMin)
        XCTAssertEqual(number("deadManJog", "velocityMax"), DeadManSettings.velocityMax)
        XCTAssertEqual(section("linkHealth")["indicatorEnabledByDefault"] as? Bool, Contract.linkIndicatorEnabledByDefault)
        XCTAssertEqual(section("linkHealth")["blockJogOnBadLinkDefault"] as? Bool, Contract.linkBlockJogOnBadLinkDefault)
        for (key, value) in [("probeIntervalMs", Int(Contract.linkProbeInterval * 1000)), ("probeTimeoutMs", Int(Contract.linkProbeTimeout * 1000)),
                             ("sampleWindow", Contract.linkSampleWindow), ("goodRttMs", Contract.linkGoodRttMs), ("poorRttMs", Contract.linkPoorRttMs),
                             ("blockRttMs", Contract.linkBlockRttMs), ("lostAfterMs", Contract.linkLostAfterMs)] {
            XCTAssertEqual(number("linkHealth", key), Double(value), key)
        }
        XCTAssertEqual(number("works", "maxPoints"), Double(Contract.worksMaxPoints))
        XCTAssertEqual(number("works", "fileMaxBytes"), Double(Contract.worksFileMaxBytes))
        XCTAssertEqual(number("works", "fileNameMax"), Double(Contract.worksFileNameMax))
        XCTAssertEqual(number("works", "folderMax"), Double(Contract.worksFolderMax))
    }

    func testListenOnlyAllowsReadsTheStopsAndTheSession() {
        func command(_ name: String) -> Data { Data(#"{"command":"\#(name)"}"#.utf8) }
        XCTAssertTrue(ListenOnly.allows(method: "GET", path: "/api/settings", body: nil))
        for path in ["/api/login", "/api/refresh", "/api/logout", "/api/stop-all"] { XCTAssertTrue(ListenOnly.allows(method: "POST", path: path, body: nil), path) }
        for name in ["stop", "jogStop", "disable"] { XCTAssertTrue(ListenOnly.allows(method: "POST", path: "/api/robot/1/command", body: command(name)), name) }
        for name in ["play", "pause", "jog", "jogStart", "jogHeartbeat", "table", "reset", "enable", "trajectory", "speed", "valve"] {
            XCTAssertFalse(ListenOnly.allows(method: "POST", path: "/api/robot/1/command", body: command(name)), name)
        }
        for path in ["/api/robot/1/claim", "/api/robot/1/release", "/api/robot/1/jog-arm", "/api/admin/server-config", "/other"] {
            XCTAssertFalse(ListenOnly.allows(method: "POST", path: path, body: nil), path)
        }
        XCTAssertFalse(ListenOnly.allows(method: "POST", path: "/api/robot/1/command", body: Data("x".utf8)))
    }

    func testTheContinuousJogStartsOffAndTheFirstReasonWins() {
        XCTAssertFalse(Contract.deadManEnabledByDefault)
        for (input, wanted) in [(5000.0, 100.0), (-5000, -100), (0, 1), (.nan, 1), (-0.2, -1), (20, 20)] { XCTAssertEqual(clampDeadManVelocity(input), wanted) }
        func block(_ change: (inout DeadManSituation) -> Void) -> DeadManBlock {
            var s = DeadManSituation(switchedOn: true, connected: true, robotOnline: true, robotEnabled: true, robotPlaying: false, stopInProgress: false,
                                     needsArming: false, role: "operator", linkBlocks: false, alreadyRunning: false, serverSupports: true)
            change(&s)
            return s.block
        }
        XCTAssertEqual(block { _ in }, .none)
        XCTAssertEqual(block { $0.switchedOn = false; $0.connected = false }, .off)
        XCTAssertEqual(block { $0.connected = false }, .notConnected)
        XCTAssertEqual(block { $0.serverSupports = false }, .notSupported)
        XCTAssertEqual(block { $0.role = "viewer" }, .role)
        XCTAssertEqual(block { $0.role = nil }, .none)
        XCTAssertEqual(block { $0.robotOnline = false }, .offline)
        XCTAssertEqual(block { $0.robotEnabled = false }, .safeMode)
        XCTAssertEqual(block { $0.stopInProgress = true; $0.robotPlaying = true }, .stopPending)
        XCTAssertEqual(block { $0.robotPlaying = true }, .moving)
        XCTAssertEqual(block { $0.needsArming = true }, .notArmed)
        XCTAssertEqual(block { $0.alreadyRunning = true }, .alreadyRunning)
        XCTAssertEqual(block { $0.linkBlocks = true }, .badLink)
    }

    func testTheWatchdogGivesTheLinkUp() {
        var now = 0
        var dog = DeadManWatchdog(settings: DeadManSettings(), clock: { now })
        XCTAssertNil(dog.verdict())
        dog.missed()
        XCTAssertNil(dog.verdict())
        dog.acked()
        XCTAssertEqual(dog.missedInARow, 0)
        dog.missed()
        dog.missed()
        XCTAssertEqual(dog.verdict(), .linkLost)
        let silent = DeadManWatchdog(settings: DeadManSettings(), clock: { now })
        now += DeadManSettings().serverTimeoutMs + 1
        XCTAssertEqual(silent.verdict(), .linkLost)
        var short = DeadManSettings()
        short.maxHoldMs = 1000
        var long = DeadManWatchdog(settings: short, clock: { now })
        for _ in 0..<20 {
            now += 90
            long.acked()
        }
        XCTAssertEqual(long.verdict(), .tooLong)
    }

    func testTheHomeResetRules() {
        XCTAssertFalse(Contract.homeResetEnabledByDefault)
        func block(_ change: (inout HomeResetSituation) -> Void) -> HomeResetBlock {
            var s = HomeResetSituation(switchedOn: true, connected: true, robotOnline: true, robotEnabled: true, robotPlaying: false, jogInFlight: false,
                                       stopInProgress: false, needsArming: false, role: nil, hasPose: true, serverSupports: true)
            change(&s)
            return s.block
        }
        XCTAssertEqual(block { _ in }, .none)
        XCTAssertEqual(block { $0.switchedOn = false; $0.connected = false }, .off)
        XCTAssertEqual(block { $0.connected = false }, .notConnected)
        XCTAssertEqual(block { $0.serverSupports = false }, .notSupported)
        XCTAssertEqual(block { $0.role = "viewer" }, .role)
        XCTAssertEqual(block { $0.robotOnline = false }, .offline)
        XCTAssertEqual(block { $0.robotEnabled = false }, .safeMode)
        XCTAssertEqual(block { $0.stopInProgress = true }, .stopPending)
        XCTAssertEqual(block { $0.robotPlaying = true }, .moving)
        XCTAssertEqual(block { $0.jogInFlight = true }, .jogBusy)
        XCTAssertEqual(block { $0.needsArming = true }, .notArmed)
        XCTAssertEqual(block { $0.hasPose = false }, .noPose)
    }

    func testOnlyTheLastStepOfHomeResetSends() {
        var confirmation = HomeResetConfirmation()
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(confirmation.advance(now: start))
        XCTAssertTrue(confirmation.advance(now: start.addingTimeInterval(5)))
        XCTAssertFalse(confirmation.advance(now: start))
        // after the window it starts over
        XCTAssertFalse(confirmation.advance(now: start.addingTimeInterval(25)))
        XCTAssertTrue(confirmation.advance(now: start.addingTimeInterval(26)))
        XCTAssertFalse(confirmation.advance(now: start))
        confirmation.cancel()
        XCTAssertFalse(confirmation.advance(now: start))
    }

    func testPlayAsksOnlyWhenItIsOnAndTheRobotIsNotPlaying() {
        XCTAssertTrue(playNeedsConfirmation(askBeforePlay: true, robotIsPlaying: false))
        XCTAssertFalse(playNeedsConfirmation(askBeforePlay: true, robotIsPlaying: true))
        XCTAssertFalse(playNeedsConfirmation(askBeforePlay: false, robotIsPlaying: false))
    }

    func testOnlyAReservationHeldHereAboutToEndIsRenewed() {
        func claim(_ expires: Int64) -> ClaimInfo { ClaimInfo(robotId: 1, ownerUsername: "a", controllerId: "c", expiresAt: expires) }
        XCTAssertTrue(claimNeedsRenewal(claim(60_000), standing: .mineHere, nowMs: 0))
        XCTAssertFalse(claimNeedsRenewal(claim(600_000), standing: .mineHere, nowMs: 0))
        XCTAssertFalse(claimNeedsRenewal(claim(10), standing: .mineHere, nowMs: 20))
        for standing in [ClaimStanding.free, .mineElsewhere, .other] { XCTAssertFalse(claimNeedsRenewal(claim(60_000), standing: standing, nowMs: 0)) }
        XCTAssertTrue(claimNeedsRenewal(claim(600_000), standing: .mineHere, nowMs: 0, renewBeforeMs: 700_000))
    }

    func testWhereAReservationStandsAndWhoMayTakeOver() {
        func claim(_ owner: String, _ controller: String?) -> ClaimInfo { ClaimInfo(robotId: 1, ownerUsername: owner, controllerId: controller, expiresAt: 1) }
        XCTAssertEqual(ClaimStanding.of(nil, username: "alice", controllerId: "ios-1"), .free)
        XCTAssertEqual(ClaimStanding.of(claim("alice", "ios-1"), username: "alice", controllerId: "ios-1"), .mineHere)
        XCTAssertEqual(ClaimStanding.of(claim("alice", "ios-2"), username: "alice", controllerId: "ios-1"), .mineElsewhere)
        XCTAssertEqual(ClaimStanding.of(claim("alice", nil), username: "alice", controllerId: "ios-1"), .mineHere)
        XCTAssertEqual(ClaimStanding.of(claim("bob", "x"), username: "alice", controllerId: "ios-1"), .other)
        XCTAssertEqual(ClaimStanding.of(claim("", "x"), username: "", controllerId: "ios-1"), .other)
        XCTAssertTrue(canTakeOverRobot(role: "admin", standing: .other))
        XCTAssertTrue(canTakeOverRobot(role: "admin", standing: .mineElsewhere))
        XCTAssertFalse(canTakeOverRobot(role: "operator", standing: .other))
        XCTAssertFalse(canTakeOverRobot(role: nil, standing: .other))
        XCTAssertFalse(canTakeOverRobot(role: "admin", standing: .free))
        XCTAssertFalse(canTakeOverRobot(role: "admin", standing: .mineHere))
    }

    func testTheRevisionTracker() {
        var tracker = RevisionTracker()
        let first = tracker.begin(1, command: "play", mode: .standard)
        XCTAssertNil(first.ifMatch)
        tracker.finish(1, seq: first.seq, revision: "r1")
        let second = tracker.begin(1, command: "play", mode: .standard)
        XCTAssertEqual(second.ifMatch, "\"r1\"")
        // a write while another is on its way is not checked
        XCTAssertNil(tracker.begin(1, command: "play", mode: .standard).ifMatch)
        XCTAssertFalse(ConditionalMode.strict.applies(to: "stop"))
        XCTAssertFalse(ConditionalMode.standard.applies(to: "jog"))
        XCTAssertTrue(ConditionalMode.strict.applies(to: "jog"))
        XCTAssertFalse(ConditionalMode.off.applies(to: "play"))
        XCTAssertNil(revisionOf(["revision": "a b"]))
    }

    func testTheLinkHealth() {
        let start = Date(timeIntervalSince1970: 1000)
        var link = LinkHealth()
        XCTAssertEqual(link.level(now: start), .unknown)
        XCTAssertFalse(link.blocksJog(now: start))
        link.record(20, now: start)
        XCTAssertEqual(link.level(now: start), .good)
        link.record(150, now: start)
        XCTAssertEqual(link.level(now: start), .poor)
        link.record(600, now: start)
        XCTAssertEqual(link.level(now: start), .bad)
        XCTAssertTrue(link.blocksJog(now: start))
        XCTAssertEqual(link.level(now: start.addingTimeInterval(5)), .lost)
        link.reset()
        link.recordFailure()
        XCTAssertTrue(link.blocksJog(now: start))
    }

    func testTheWorkFiles() {
        XCTAssertEqual(WorkFiles.folder(worksPaths: nil, robotId: 1, robotName: "Robot A1"), "WORKS/RobotA1")
        XCTAssertEqual(WorkFiles.folder(worksPaths: ["1": "/jobs/a/"], robotId: 1, robotName: "x"), "jobs/a")
        for bad in ["../x", "a/../b", "a//b", "http://x", "a?b"] { XCTAssertNil(WorkFiles.folder(worksPaths: ["1": bad], robotId: 1, robotName: "x"), bad) }
        XCTAssertEqual(WorkFiles.parseIndex(Data(#"["b.json","a.json","../c.json","d.txt",3,"a.json"]"#.utf8)), ["a.json", "b.json"])
        let good = WorkFiles.parsePoints(Data(#"[{"x":1,"y":2,"z":3,"extra":"drop"},{"j1":0,"j2":0,"j3":0,"j4":0,"j5":0,"j6":0,"tx":1}]"#.utf8))
        XCTAssertEqual(good?.points.count, 2)
        XCTAssertNil(good?.points.first?["extra"])
        XCTAssertEqual(good?.usesTable, true)
        for bad in ["x", "{}", "[]", "[1]", #"[{"x":1}]"#, #"[{"x":"1","y":2,"z":3}]"#, #"[{"x":true,"y":2,"z":3}]"#, #"[{"x":1,"y":2,"z":3,"motionType":"other"}]"#] {
            XCTAssertNil(WorkFiles.parsePoints(Data(bad.utf8)), bad)
        }
        let many = "[" + Array(repeating: #"{"x":1,"y":2,"z":3}"#, count: Contract.worksMaxPoints + 1).joined(separator: ",") + "]"
        XCTAssertNil(WorkFiles.parsePoints(Data(many.utf8)))
    }

    func testTheParol6JointsAreTheOnesOfThePublishedApp() {
        func check(_ expected: [Double], _ actual: [Double], line: UInt = #line) {
            for i in 0..<expected.count { XCTAssertEqual(actual[i], expected[i], accuracy: 1e-3, "j\(i + 1)", line: line) }
        }
        check([0.0, 0.072990, -0.072819, 0, 0, 0], Parol6.joints(x: 200, y: 0, z: 0, a: 0, b: 0, c: 0))
        check([33.690068, -4.185567, -2.582369, 0, 0, 90], Parol6.joints(x: 150, y: 100, z: 20, a: 0, b: 0, c: 90))
        check([90.0, -1.573483, 17.459544, 10, -10, 0], Parol6.joints(x: 0, y: 200, z: -50, a: 10, b: -10, c: 0))
        check([97.4, 8.232120, -47.529770, 0, 0, 0], Parol6.joints(x: -150, y: 50, z: 100, a: 0, b: 0, c: 0))
        check([-23.962489, -2.408749, 11.952691, 5, 5, 5], Parol6.joints(x: 180, y: -80, z: -30, a: 5, b: 5, c: 5))
        XCTAssertNotNil(Parol6.jointsOrNil(x: 200, y: 0, z: 0, a: 0, b: 0, c: 0))
        XCTAssertNil(Parol6.jointsOrNil(x: 5000, y: 0, z: 0, a: 0, b: 0, c: 0))
        XCTAssertNil(Parol6.jointsOrNil(x: -150, y: 50, z: 100, a: 0, b: 0, c: 0))
    }
}
