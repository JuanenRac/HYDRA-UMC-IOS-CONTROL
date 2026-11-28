// HYDRA-UMC-IOS-CONTROL - what the Control screen does: the commands of a robot, its reservation, the jog (by steps and held), HOME/RESET and the works.
// The global STOP is not here (Stop.swift): nothing of this file can block it. Every motion is gated before it leaves the phone; the server checks again.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum ControlPref {
    public static let listenOnly = "hydra_listen_only"
    public static let listenOnlyServers = "hydra_listen_only_servers"
    public static let blockSavedData = "hydra_block_cached_commands"
    public static let confirmPlay = "hydra_confirm_play"
    public static let homeReset = "hydra_home_reset"
    public static let deadMan = "hydra_dead_man_jog"
    public static let linkBlock = "hydra_link_block_jog"
    public static let linkIndicator = "hydra_link_indicator"
    public static let conditional = "hydra_conditional_mode"
}

public enum JogTarget: String, CaseIterable, Sendable { case robot, xytable }

@MainActor
public final class RobotControl {
    public static let jogSteps: [Double] = [0.1, 1, 5, 10, 25, 50, 90, 100]
    public static let defaultJogStep = 10.0

    private unowned let app: HydraController
    private let prefs: PrefsStore
    var now: () -> Date = Date.init
    /// How long a slider is quiet before its value is sent.
    var debounceSeconds = 0.3
    var retryPauseNanoseconds: UInt64 = 250_000_000

    // switches, kept between runs
    public private(set) var listenOnlyGeneral: Bool
    public private(set) var listenOnlyServers: Set<String>
    public private(set) var blockOnSavedData: Bool
    public private(set) var confirmPlay: Bool
    public private(set) var homeResetEnabled: Bool
    public private(set) var deadManEnabled: Bool
    public private(set) var blockOnBadLink: Bool
    public private(set) var linkIndicator: Bool
    public private(set) var conditionalMode: ConditionalMode

    // state of the session
    public private(set) var selectedRobotId: Int?
    public private(set) var claims: [ClaimInfo] = []
    public private(set) var safety: [Int: RobotSafety] = [:]
    public private(set) var jogArmedUntil: [Int: Date] = [:]
    public private(set) var claimsPushedAt: Date?
    public private(set) var accessBusy = false
    public private(set) var homeResetSupported = true
    public private(set) var deadManSupported = true
    public private(set) var worksSupported = true
    private var tableSupported = true
    public private(set) var workFiles: [String]?
    public private(set) var workBusy = false
    public private(set) var held: Set<Int> = []
    public var velocity = DeadManSettings.velocityDefault
    public private(set) var link = LinkHealth()
    private var probing = false

    private(set) var revisions = RevisionTracker()
    private var jogsInFlight: [Int: Int] = [:]
    private var generation: [Int: Int] = [:]
    private var pending: [String: Task<Void, Never>] = [:]
    private var renewingClaim = false
    /// The client a held jog started with: its stop leaves through it even while the session is being closed.
    private var jogClient: HydraClient?

    public private(set) lazy var deadMan: DeadManRunner = {
        let runner = DeadManRunner { [weak self] robotId, command, params in
            guard let self, let client = self.jogClient else { throw TransportError.unreachable }
            var payload: [String: Any] = ["command": command, "params": params]
            if Contract.numbered.contains(command) { payload["seq"] = self.app.sequence.next() }
            _ = try await client.robotCommand(robotId, payload, ifMatch: nil, urgent: true)
        }
        runner.linkAllows = { [weak self] in
            guard let self else { return false }
            return !(self.blockOnBadLink && self.link.blocksJog(now: self.now()))
        }
        runner.onRoundTrip = { [weak self] rtt in
            guard let self else { return }
            self.link.record(rtt, now: self.now())
            self.app.changed()
        }
        runner.onEnded = { [weak self] robotId, reason, stopConfirmed in self?.jogEnded(robotId, reason, stopConfirmed) }
        return runner
    }()

    init(app: HydraController, prefs: PrefsStore) {
        self.app = app
        self.prefs = prefs
        listenOnlyGeneral = prefs.bool(ControlPref.listenOnly)
        listenOnlyServers = prefs.codable(Set<String>.self, ControlPref.listenOnlyServers) ?? []
        blockOnSavedData = prefs.bool(ControlPref.blockSavedData)
        confirmPlay = prefs.bool(ControlPref.confirmPlay, default: true)
        homeResetEnabled = prefs.bool(ControlPref.homeReset, default: Contract.homeResetEnabledByDefault)
        deadManEnabled = prefs.bool(ControlPref.deadMan, default: Contract.deadManEnabledByDefault)
        blockOnBadLink = prefs.bool(ControlPref.linkBlock, default: Contract.linkBlockJogOnBadLinkDefault)
        linkIndicator = prefs.bool(ControlPref.linkIndicator, default: Contract.linkIndicatorEnabledByDefault)
        conditionalMode = prefs.string(ControlPref.conditional).flatMap(ConditionalMode.init(rawValue:)) ?? .standard
    }

    // MARK: - Switches

    /// Listen only for everything, or for the server in use.
    public var listenOnly: Bool { listenOnlyGeneral || app.serverKey.map(listenOnlyServers.contains) == true }
    public var listenOnlyThisServer: Bool { app.serverKey.map(listenOnlyServers.contains) == true }

    public func setListenOnly(_ on: Bool) {
        if on { interrupt() }   // before the switch holds: a held jog stops
        listenOnlyGeneral = on
        prefs.set(on, ControlPref.listenOnly)
        app.changed()
    }

    public func setListenOnlyThisServer(_ on: Bool) {
        guard let key = app.serverKey else { return }
        if on {
            interrupt()
            listenOnlyServers.insert(key)
        } else {
            listenOnlyServers.remove(key)
        }
        prefs.setCodable(listenOnlyServers, ControlPref.listenOnlyServers)
        app.changed()
    }

    public func setBlockOnSavedData(_ on: Bool) { blockOnSavedData = on; keep(on, ControlPref.blockSavedData) }
    public func setConfirmPlay(_ on: Bool) { confirmPlay = on; keep(on, ControlPref.confirmPlay) }
    public func setHomeResetEnabled(_ on: Bool) { homeResetEnabled = on; keep(on, ControlPref.homeReset) }
    public func setBlockOnBadLink(_ on: Bool) { blockOnBadLink = on; keep(on, ControlPref.linkBlock) }
    public func setLinkIndicator(_ on: Bool) { linkIndicator = on; keep(on, ControlPref.linkIndicator) }

    public func setDeadManEnabled(_ on: Bool) {
        deadManEnabled = on
        if !on { interrupt() }
        keep(on, ControlPref.deadMan)
    }

    public func setConditionalMode(_ mode: ConditionalMode) {
        conditionalMode = mode
        prefs.set(mode.rawValue, ControlPref.conditional)
        app.changed()
    }

    private func keep(_ on: Bool, _ key: String) {
        prefs.set(on, key)
        app.changed()
    }

    // MARK: - Session

    /// Nothing of a session survives it. Held jogs were interrupted before.
    func reset() {
        interrupt()
        for task in pending.values { task.cancel() }
        pending = [:]
        jogsInFlight = [:]
        selectedRobotId = nil
        claims = []
        claimsPushedAt = nil
        safety = [:]
        jogArmedUntil = [:]
        revisions = RevisionTracker()
        homeResetSupported = true
        deadManSupported = true
        worksSupported = true
        tableSupported = true
        workFiles = nil
        link.reset()
    }

    func linkLost() {
        interrupt()
        link.reset()
    }

    func stoppedAll() {
        jogArmedUntil = [:]
        app.changed()
    }

    private func say(_ key: String, _ values: [String: String] = [:]) {
        app.message = Message(key, values)
    }

    // MARK: - The robot in view

    public var selected: RobotInfo? { app.robots.first { $0.robotId == selectedRobotId } ?? app.robots.first }

    public func select(_ robotId: Int) {
        if robotId != selected?.robotId { interrupt() }
        selectedRobotId = robotId
        workFiles = nil
        app.changed()
    }

    private func info(_ robotId: Int) -> RobotInfo? { app.robots.first { $0.robotId == robotId } }
    private func raw(_ robotId: Int) -> [String: Any]? { app.cell.robot(robotId)?.raw }

    /// The jog step the server keeps for the robot, snapped to one the screen offers.
    public func jogStep(of robotId: Int) -> Double {
        guard let value = (raw(robotId)?["jogStep"] as? NSNumber)?.doubleValue, value.isFinite, value > 0 else { return RobotControl.defaultJogStep }
        return RobotControl.jogSteps.min { abs($0 - value) < abs($1 - value) } ?? RobotControl.defaultJogStep
    }

    /// The valves or pumps of a robot (two when it says nothing).
    public func outputs(_ kind: String, of robotId: Int) -> [Bool] {
        let list = raw(robotId)?[kind] as? [Any] ?? [false, false]
        return list.map { $0 as? Bool == true }
    }

    public func recordedPoints(of robotId: Int) -> Int { (raw(robotId)?["recordedPoints"] as? [Any])?.count ?? 0 }

    // MARK: - Commands

    private static func isStopping(_ command: String) -> Bool { command == "stop" || command == "disable" }

    /// Gates a command, shows its effect at once and sends it. The checks and the effect happen before this returns; the task is the send.
    /// nil when nothing is going to be sent.
    @discardableResult
    private func issue(_ command: String, params: [String: Any]? = nil, robot: Int? = nil, combined: Bool = false, debounced: Bool = false,
                       change: (inout [String: Any]) -> Void) -> Task<Void, Never>? {
        let stopping = RobotControl.isStopping(command)
        if listenOnly && !stopping { return nil }
        guard let robotId = robot ?? selected?.robotId else { return nil }
        if stopping { interrupt() }
        if blockOnSavedData && app.showingSavedData && !stopping {
            say("errSavedDataBlocked")
            return nil
        }
        let target = raw(robotId)
        // a stop leaves even for a robot the phone no longer knows
        if target == nil && !stopping {
            say("errRobotNotFound")
            return nil
        }
        guard let client = app.client else {
            say("errNotConnected")
            return nil
        }
        if command == "jog" || command == "table" {
            if jogNeedsArming(robotId) {
                say("errJogNotArmed")
                return nil
            }
            let limits = safety[robotId]?.jog
            func number(_ key: String) -> Double { (params?[key] as? NSNumber)?.doubleValue ?? 0 }
            let exceeded: Double?
            if command == "table" {
                let xy = (target?["xyTable"] as? [String: Any])?["pos"] as? [String: Any]
                exceeded = tableLimitExceeded(x: number("x"), y: number("y"), relative: params?["mode"] as? String == "relative", limits,
                                              currentX: (xy?["x"] as? NSNumber)?.doubleValue ?? 0, currentY: (xy?["y"] as? NSNumber)?.doubleValue ?? 0)
            } else {
                exceeded = jogLimitExceeded(number("amount"), limits, absolute: params?["absolute"] as? Bool == true)
            }
            if let exceeded {
                say("errJogOverLimit", ["limit": formatLimit(exceeded)])
                return nil
            }
        }
        var affected = [robotId]
        if combined { affected += (target?["combinedWith"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue } }
        var before: [(robotId: Int, raw: [String: Any], generation: Int)] = []
        app.changeCell { cell in
            for id in affected {
                guard var value = cell.robot(id)?.raw else { continue }
                let snapshot = value
                change(&value)
                cell.setRobot(id, value)
                generation[id, default: 0] += 1
                before.append((id, snapshot, generation[id, default: 0]))
            }
        }
        var payload: [String: Any] = ["command": command]
        if let params { payload["params"] = params }
        let rollback: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.app.changeCell { cell in
                // a newer command of the same robot has started: this failure is stale
                for entry in before where self.generation[entry.robotId] == entry.generation { cell.setRobot(entry.robotId, entry.raw) }
            }
        }
        let isJog = command == "jog" || command == "table"
        if !debounced {
            if isJog { jogsInFlight[robotId, default: 0] += 1 }
            return Task { @MainActor in
                await self.deliver(command, robotId: robotId, payload: payload, client: client, rollback: rollback)
                if isJog { self.finishedJog(robotId) }
            }
        }
        // a burst of a slider becomes one send once it settles
        pending[command]?.cancel()
        let wait = UInt64(debounceSeconds * 1_000_000_000)
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: wait)
            if Task.isCancelled { return }
            self.pending[command] = nil
            await self.deliver(command, robotId: robotId, payload: payload, client: client, rollback: rollback)
        }
        pending[command] = task
        return task
    }

    private func finishedJog(_ robotId: Int) {
        let left = (jogsInFlight[robotId] ?? 1) - 1
        jogsInFlight[robotId] = left <= 0 ? nil : left
        app.changed()
    }

    public func jogInFlight(_ robotId: Int) -> Bool { (jogsInFlight[robotId] ?? 0) > 0 }

    private func deliver(_ command: String, robotId: Int, payload: [String: Any], client: HydraClient, rollback: @MainActor () -> Void) async {
        // the session changed before it left: nothing of an earlier session is sent
        guard client === app.client else { return }
        do {
            let answer = try await postConditionally(command, robotId: robotId, payload: payload, client: client)
            guard client === app.client else { return }
            if let warnings = answer["warnings"] as? [Any], !warnings.isEmpty {
                // a 200 that applied nothing is a failure
                rollback()
                say("errCommandNotApplied", ["command": command, "reason": warnings.map { ($0 as? [String: Any])?["message"] as? String ?? "\($0)" }.joined(separator: "; ")])
                return
            }
            app.message = nil
            if command == "stop" { jogArmedUntil[robotId] = nil }   // the server disarms the jog on a stop
            app.changed()
        } catch {
            guard client === app.client else { return }
            rollback()
            app.message = describe(error, command: command)
            if let error = error as? ApiError {
                if command == "reset" && error.isUnknownCommand { homeResetSupported = false }
                if command == "trajectory" && error.isUnknownCommand { worksSupported = false }
                if error.isRevisionMismatch { await readAgain(robotId) }
                if error.isJogNotArmed { jogArmedUntil[robotId] = nil }
                if error.isSessionProblem { app.sessionEnded() }
            }
            app.changed()
        }
    }

    /// One send. A stop that gets no answer is repeated; an answer of the server is never repeated.
    private func post(_ robotId: Int, _ payload: [String: Any], ifMatch: String?, urgent: Bool, client: HydraClient) async throws -> [String: Any] {
        var attempt = 0
        while true {
            do {
                var body = payload
                if let command = body["command"] as? String, Contract.numbered.contains(command) { body["seq"] = app.sequence.next() }
                return try await client.robotCommand(robotId, body, ifMatch: ifMatch, urgent: urgent)
            } catch let error as ApiError {
                throw error
            } catch {
                if !urgent || attempt >= 2 { throw error }
            }
            attempt += 1
            try? await Task.sleep(nanoseconds: retryPauseNanoseconds)
        }
    }

    private func withRevision(_ robotId: Int, _ command: String, _ call: (String?) async throws -> [String: Any]) async throws -> [String: Any] {
        let ticket = revisions.begin(robotId, command: command, mode: conditionalMode)
        do {
            let answer = try await call(ticket.ifMatch)
            revisions.finish(robotId, seq: ticket.seq, revision: revisionOf(answer))
            return answer
        } catch {
            revisions.finish(robotId, seq: ticket.seq, revision: nil)
            if let error = error as? ApiError, error.isRevisionMismatch { revisions.learn(robotId, error.revision) }
            throw error
        }
    }

    private func postConditionally(_ command: String, robotId: Int, payload: [String: Any], client: HydraClient) async throws -> [String: Any] {
        let params = payload["params"] as? [String: Any]
        if command == "table", !tableSupported, let params { return try await tableAsJogCommands(robotId, params, client: client) }
        do {
            return try await withRevision(robotId, command) { ifMatch in
                try await self.post(robotId, payload, ifMatch: ifMatch, urgent: command == "stop", client: client)
            }
        } catch let error as ApiError where command == "table" && error.isUnknownCommand && params != nil {
            tableSupported = false
            return try await tableAsJogCommands(robotId, params ?? [:], client: client)
        }
    }

    private func tableAsJogCommands(_ robotId: Int, _ params: [String: Any], client: HydraClient) async throws -> [String: Any] {
        var last: [String: Any] = ["success": true]
        for jog in tableAsJogs(params) {
            last = try await post(robotId, ["command": "jog", "params": jog], ifMatch: nil, urgent: false, client: client)
        }
        return last
    }

    /// What the person reads for a failure, by what the server said.
    private func describe(_ error: Error, command: String) -> Message {
        let values = ["command": command]
        guard let api = error as? ApiError else {
            return command == "stop" ? Message("errStopNotConfirmed") : Message("errTxError", ["command": command, "error": "\(error)"])
        }
        if command == "reset" && api.isUnknownCommand { return Message("homeResetNotSupported") }
        if api.code == "listen-only" { return Message("controlListenOnlyBanner") }
        if api.status == 409 && api.code == "stale-sequence" { return Message("errStaleSequence", values) }
        if (api.status == 400 && api.code == "home-pose-mismatch") || (api.status == 422 && api.code == "home-out-of-limits") { return Message("errHomeRejected", values) }
        if api.isRevisionMismatch { return Message("errRevisionChanged", values) }
        if api.isJogNotArmed { return Message("errJogNotArmed") }
        if api.code == "server-read-only" { return Message("errServerReadOnly", values) }
        if api.status == 423 || api.code == "robot-disabled" { return Message("errRobotDisabled", values) }
        if api.status == 403 && api.code == "enable-not-allowed" { return Message("errEnableNotAllowed") }
        if api.status == 403 && api.code == "admin-required" { return Message("errAdminRequired") }
        let detail = api.message ?? ""
        if api.status == 409 && api.code == "other-controller" { return Message("errClaimOtherController", ["detail": detail]) }
        if api.code == "controller-id-required" { return Message("errClaimControllerRequired", ["detail": detail]) }
        if api.status == 409 { return Message("errRobotReserved", ["owner": detail]) }
        if api.isSessionProblem { return Message("errSessionEnded") }
        if api.status == 403 { return command == "reset" ? Message("homeResetBlockedRole") : Message("errPermissionDenied") }
        if api.status == 400 { return Message("errCommandRejected", ["command": command, "reason": detail]) }
        return Message("errTxError", ["command": command, "error": "HTTP \(api.status)"])
    }

    /// Reads one robot again (after a 412) and shows it. A failure changes nothing.
    private func readAgain(_ robotId: Int) async {
        guard let client = app.client else { return }
        guard let read = try? await client.robot(robotId), client === app.client else { return }
        revisions.learn(robotId, read.revision)
        app.changeCell { cell in
            guard var value = cell.robot(robotId)?.raw else { return }
            value.merge(read.robot) { _, new in new }
            cell.setRobot(robotId, value)
        }
    }

    private static func playback(_ robot: inout [String: Any], _ values: [String: Any]) {
        var playback = robot["playbackState"] as? [String: Any] ?? [:]
        playback.merge(values) { _, new in new }
        robot["playbackState"] = playback
    }

    private static func stopped(_ robot: inout [String: Any]) {
        playback(&robot, ["isPlaying": false, "playing": false, "requestStop": true, "isPaused": false, "paused": false, "requestPause": false, "activeStep": -1])
    }

    private static func set(_ robot: inout [String: Any], _ key: String, _ field: String, _ value: Double) {
        var map = robot[key] as? [String: Any] ?? [:]
        map[field] = value
        robot[key] = map
    }

    /// PLAY of the robot (and its combined ones). The screen asks first when the switch is on.
    @discardableResult
    public func play() -> Task<Void, Never>? {
        guard let robot = selected else { return nil }
        guard robot.online else { return nil }
        return issue("play", combined: true) { value in
            RobotControl.playback(&value, ["isPlaying": true, "playing": true, "requestStop": false, "activeStep": 0, "isFinished": false, "finished": false,
                                           "isPaused": false, "paused": false, "requestPause": false])
        }
    }

    /// Pause or resume, sent as the wanted state so a combined pair never drifts apart.
    @discardableResult
    public func togglePause() -> Task<Void, Never>? {
        guard let robot = selected, robot.online, robot.isPlaying else { return nil }
        let paused = !robot.isPaused
        return issue("pause", params: ["paused": paused], combined: true) { value in
            RobotControl.playback(&value, ["isPaused": paused, "paused": paused, "requestPause": paused, "isPlaying": true, "playing": true, "isFinished": false, "finished": false])
        }
    }

    /// Stop of the selected robot. No switch, mode, reservation or saved data holds it back.
    @discardableResult
    public func stopRobot() -> Task<Void, Never>? {
        issue("stop", combined: true) { RobotControl.stopped(&$0) }
    }

    /// Turns the camera of a robot on or off on the server.
    @discardableResult
    public func setVision(_ robotId: Int, _ on: Bool) -> Task<Void, Never>? {
        issue("vision", params: ["enabled": on], robot: robotId) { robot in
            robot["visionEnabled"] = on
            if var camera = robot["camera"] as? [String: Any] {
                camera["connected"] = on
                robot["camera"] = camera
            }
        }
    }

    /// Safe mode of the selected robot only: it stops, and the server then refuses everything but STOP.
    @discardableResult
    public func disable() -> Task<Void, Never>? {
        issue("disable") { value in
            RobotControl.stopped(&value)
            value["enabled"] = false
        }
    }

    @discardableResult
    public func enable() -> Task<Void, Never>? {
        issue("enable") { $0["enabled"] = true }
    }

    // MARK: - Jog by steps

    /// No jog while one is on its way (the heartbeat of a held button), while the robot runs a trajectory, or while it is away or in safe mode.
    public func jogBlocked(_ robotId: Int) -> Bool {
        if jogInFlight(robotId) { return true }
        guard let robot = info(robotId) else { return true }
        return !robot.online || !robot.enabled || robot.isMoving
    }

    @discardableResult
    public func jog(_ target: JogTarget, axis: String, amount: Double) -> [Task<Void, Never>] {
        guard amount.isFinite, let robot = selected else { return [] }
        if target == .xytable && (axis == "x" || axis == "y") {
            let params: [String: Any] = ["x": axis == "x" ? amount : 0, "y": axis == "y" ? amount : 0, "mode": "relative"]
            let current = axis == "x" ? robot.xyX : robot.xyY
            return [issue("table", params: params) { value in
                var table = value["xyTable"] as? [String: Any] ?? [:]
                RobotControl.set(&table, "pos", axis, current + amount)
                value["xyTable"] = table
            }].compactMap { $0 }
        }
        let params: [String: Any] = ["axis": axis, "amount": amount, "target": target.rawValue]
        return [issue("jog", params: params) { value in
            if target == .robot {
                let current = ((value["pos"] as? [String: Any])?[axis] as? NSNumber)?.doubleValue ?? 0
                RobotControl.set(&value, "pos", axis, current + amount)
            }
        }].compactMap { $0 }
    }

    /// One tick of a jog button: up to three axes, dropped as a whole while the previous tick is on its way.
    @discardableResult
    public func jogXYZ(_ target: JogTarget, dx: Int, dy: Int, dz: Int, step: Double) -> [Task<Void, Never>] {
        guard let robot = selected, !jogBlocked(robot.robotId) else { return [] }
        if target == .robot && robot.model == Parol6.modelName {
            // the combined move is solved once against the arm: every axis command carries the same joints
            let pos = raw(robot.robotId)?["pos"] as? [String: Any] ?? [:]
            func at(_ key: String) -> Double { (pos[key] as? NSNumber)?.doubleValue ?? 0 }
            let x = at("x") + Double(dx) * step, y = at("y") + Double(dy) * step, z = at("z") + Double(dz) * step
            guard let joints = Parol6.jointsOrNil(x: x, y: y, z: z, a: at("a"), b: at("b"), c: at("c")) else {
                say("errJogOutOfReach")
                return []
            }
            var named: [String: Double] = [:]
            for (index, joint) in joints.enumerated() { named["j\(index + 1)"] = joint }
            var sent: [Task<Void, Never>] = []
            let moves: [(axis: String, amount: Double, value: Double)] = [("x", Double(dx) * step, x), ("y", Double(dy) * step, y), ("z", Double(dz) * step, z)]
            for move in moves where move.amount != 0 {
                let task = issue("jog", params: ["axis": move.axis, "amount": move.amount, "target": "robot", "joints": named]) { value in
                    RobotControl.set(&value, "pos", move.axis, move.value)
                    value["joints"] = named
                }
                if let task { sent.append(task) }
            }
            return sent
        }
        var tasks: [Task<Void, Never>] = []
        if dx != 0 { tasks += jog(target, axis: "x", amount: Double(dx) * step) }
        if dy != 0 { tasks += jog(target, axis: "y", amount: Double(dy) * step) }
        if dz != 0 { tasks += jog(.robot, axis: "z", amount: Double(dz) * step) }
        return tasks
    }

    /// Turns the base (J1) alone by one step; it stops at the real limit of the arm.
    @discardableResult
    public func jogBase(direction: Int, step: Double) -> Task<Void, Never>? {
        guard let robot = selected, !jogBlocked(robot.robotId) else { return nil }
        let limit = robot.model == Parol6.modelName ? Parol6.limits["j1"]! : (low: -180.0, high: 180.0)
        let joints = raw(robot.robotId)?["joints"] as? [String: Any] ?? [:]
        func joint(_ name: String) -> Double { (joints[name] as? NSNumber)?.doubleValue ?? 0 }
        let next = min(limit.high, max(limit.low, joint("j1") + Double(direction) * step))
        if next == joint("j1") { return nil }
        var named: [String: Double] = [:]
        for i in 1...6 { named["j\(i)"] = i == 1 ? next : joint("j\(i)") }
        return issue("jog", params: ["axis": "x", "amount": 0.0, "target": "robot", "joints": named]) { value in
            RobotControl.set(&value, "joints", "j1", next)
        }
    }

    // MARK: - Outputs, speed

    @discardableResult
    public func toggleOutput(_ kind: String, index: Int) -> Task<Void, Never>? {
        guard (kind == "valves" || kind == "pumps"), let robot = selected else { return nil }
        let list = outputs(kind, of: robot.robotId)
        guard index >= 0 && index < list.count else { return nil }
        let wanted = !list[index]
        return issue(kind == "valves" ? "valve" : "pump", params: ["index": index, "state": wanted]) { value in
            var next = list
            next[index] = wanted
            value[kind] = next
        }
    }

    @discardableResult
    public func setJogStep(_ step: Double) -> Task<Void, Never>? {
        guard step.isFinite, step > 0, step <= Contract.jogStepMax else { return nil }
        return issue("jogStep", params: ["value": step], debounced: true) { $0["jogStep"] = step }
    }

    @discardableResult
    public func setSpeed(_ speed: Double, acceleration: Double) -> Task<Void, Never>? {
        guard speed.isFinite, acceleration.isFinite else { return nil }
        let speed = min(Contract.speedMax, max(Contract.speedMin, speed))
        let acceleration = min(Contract.speedMax, max(Contract.speedMin, acceleration))
        return issue("speed", params: ["speed": speed, "acceleration": acceleration], debounced: true) { value in
            RobotControl.playback(&value, ["speed": speed, "acceleration": acceleration])
        }
    }

    // MARK: - HOME/RESET

    private var stopInProgress: Bool { app.stopsInFlight > 0 || app.stopUnconfirmed }

    public func homeResetBlock(_ robotId: Int) -> HomeResetBlock {
        let robot = info(robotId)
        return HomeResetSituation(switchedOn: homeResetEnabled, connected: app.client != nil, robotOnline: robot?.online == true, robotEnabled: robot?.enabled ?? true,
                                  robotPlaying: robot?.isPlaying == true, jogInFlight: jogInFlight(robotId), stopInProgress: stopInProgress,
                                  needsArming: jogNeedsArming(robotId), role: role, hasPose: raw(robotId)?["pos"] is [String: Any],
                                  serverSupports: homeResetSupported).block
    }

    /// Takes the selected robot to zero. The screen calls it after the last confirmation; the checks run again here.
    @discardableResult
    public func homeReset() -> Task<Void, Never>? {
        guard !listenOnly, let robot = selected else { return nil }
        let block = homeResetBlock(robot.robotId)
        if block != .none {
            say(block.textKey)
            return nil
        }
        return issue("reset", params: ["target": "robot"]) { value in
            for axis in ["x", "y", "z", "a", "b", "c"] { RobotControl.set(&value, "pos", axis, 0) }
        }
    }

    // MARK: - Reservations and limits

    public var controllerId: String { app.client?.controllerId ?? "" }
    public var role: String? { jwtRole(app.client?.authToken) }

    public func claim(of robotId: Int) -> ClaimInfo? { claims.first { $0.robotId == robotId } }
    public func standing(_ robotId: Int) -> ClaimStanding { ClaimStanding.of(claim(of: robotId), username: app.sessionUser, controllerId: controllerId) }
    public func canTakeOver(_ robotId: Int) -> Bool { canTakeOverRobot(role: role, standing: standing(robotId)) }

    public func jogNeedsArming(_ robotId: Int) -> Bool {
        guard let limits = safety[robotId], limits.armRequired else { return false }
        guard let until = jogArmedUntil[robotId] else { return true }
        return until <= now()
    }

    private var nowMs: Int64 { Int64(now().timeIntervalSince1970 * 1000) }

    /// The clocks may differ: the arming is shown as ending no later than its length allows.
    private func armed(_ robotId: Int, until: Int64?, ttlMs: Int64) {
        guard let until, until > nowMs else {
            jogArmedUntil[robotId] = nil
            return
        }
        jogArmedUntil[robotId] = min(Date(timeIntervalSince1970: Double(until) / 1000), now().addingTimeInterval(Double(ttlMs) / 1000))
    }

    func claimsPushed(_ report: [String: Any]) {
        claims = ClaimInfo.list(report)
        claimsPushedAt = now()
        for claim in claims where claim.controllerId == controllerId {
            armed(claim.robotId, until: claim.jogArmedUntil, ttlMs: safety[claim.robotId]?.armTtlMs ?? 60_000)
        }
        app.changed()
    }

    /// Reads the reservations and the limits of the robot in view. Silent: an older server may not have them.
    public func refreshAccess(fromPoll: Bool = false) async {
        guard let client = app.client else { return }
        let robotId = selected?.robotId
        // while a push is fresh the poll does not ask again
        let pushed = claimsPushedAt.map { now().timeIntervalSince($0) < 30 } == true
        if !(fromPoll && pushed) {
            do {
                let list = try await client.claims()
                guard client === app.client else { return }
                claims = list
            } catch {
                if (error as? ApiError)?.isSessionProblem == true && client === app.client { app.sessionEnded(); return }
            }
        }
        if let robotId {
            do {
                if let limits = try await client.safetyLimits(robotId), client === app.client {
                    safety[robotId] = limits
                    armed(robotId, until: limits.jogArmedUntil, ttlMs: limits.armTtlMs)
                }
            } catch {
                if (error as? ApiError)?.isSessionProblem == true && client === app.client { app.sessionEnded(); return }
            }
        }
        app.changed()
        if let robotId { await renewOwnClaim(robotId) }
    }

    /// Keeps a reservation of this phone alive while the Control screen is open.
    private func renewOwnClaim(_ robotId: Int) async {
        guard !renewingClaim, !accessBusy, !listenOnly, let client = app.client,
              claimNeedsRenewal(claim(of: robotId), standing: standing(robotId), nowMs: nowMs) else { return }
        renewingClaim = true
        defer { renewingClaim = false }
        guard (try? await withRevision(robotId, "claim", { try await client.claim(robotId, ifMatch: $0) })) != nil else { return }
        if let list = try? await client.claims(), client === app.client { claims = list }
        app.changed()
    }

    private func access(_ what: String, _ call: (HydraClient, Int) async throws -> Void) async {
        guard let robotId = selected?.robotId, !accessBusy else { return }
        guard let client = app.client else {
            say("errNotConnected")
            return
        }
        accessBusy = true
        app.changed()
        do {
            try await call(client, robotId)
            if client === app.client { app.message = nil }
        } catch {
            if client === app.client {
                app.message = describe(error, command: what)
                if let error = error as? ApiError {
                    if error.isRevisionMismatch { await readAgain(robotId) }
                    if error.isSessionProblem { app.sessionEnded() }
                }
            }
        }
        accessBusy = false
        app.changed()
        await refreshAccess()
    }

    public func claimRobot() async {
        await access("claim") { client, robotId in
            _ = try await self.withRevision(robotId, "claim") { try await client.claim(robotId, ifMatch: $0) }
        }
    }

    /// Takes the robot from whoever holds it (administrators only). The screen asks first.
    public func takeOver() async {
        guard let robotId = selected?.robotId, canTakeOver(robotId) else { return }
        await access("claim") { client, robotId in _ = try await client.claim(robotId, force: true, ifMatch: nil) }
    }

    public func releaseRobot() async {
        await access("release") { client, robotId in
            _ = try await self.withRevision(robotId, "release") { try await client.release(robotId, ifMatch: $0) }
            self.jogArmedUntil[robotId] = nil
        }
    }

    public func setJogArmed(_ armed: Bool) async {
        await access("jog-arm") { client, robotId in
            let answer = try await client.jogArm(robotId, armed: armed)
            if armed {
                let ttl = (answer["ttlMs"] as? NSNumber)?.int64Value ?? self.safety[robotId]?.armTtlMs ?? 60_000
                self.jogArmedUntil[robotId] = self.now().addingTimeInterval(Double(ttl) / 1000)
            } else {
                self.jogArmedUntil[robotId] = nil
            }
        }
    }

    // MARK: - Continuous jog (dead-man)

    public func linkBlocks() -> Bool { blockOnBadLink && link.blocksJog(now: now()) }

    public func deadManBlock(_ robotId: Int) -> DeadManBlock {
        let robot = info(robotId)
        return DeadManSituation(switchedOn: deadManEnabled, connected: app.client != nil && app.linkOk, robotOnline: robot?.online == true,
                                robotEnabled: robot?.enabled ?? true, robotPlaying: robot?.isPlaying == true, stopInProgress: stopInProgress,
                                needsArming: jogNeedsArming(robotId), role: role, linkBlocks: linkBlocks(),
                                alreadyRunning: held.contains(robotId), serverSupports: deadManSupported).block
    }

    /// The button went down. Nothing starts when something forbids it, and the person is told what.
    @discardableResult
    public func press(_ robotId: Int, target: JogTarget, axis: String, direction: Int) -> Task<Void, Never>? {
        if listenOnly {
            say("controlListenOnlyBanner")
            return nil
        }
        if blockOnSavedData && app.showingSavedData {
            say("errSavedDataBlocked")
            return nil
        }
        let block = deadManBlock(robotId)
        if block != .none {
            say(block.textKey)
            return nil
        }
        held.insert(robotId)
        jogClient = app.client
        app.changed()
        let signed = (direction < 0 ? -1.0 : 1.0) * velocity
        return Task { @MainActor in
            // let go (or stopped) before the start left: nothing is sent
            guard self.held.contains(robotId) else { return }
            do {
                try await self.deadMan.start(robotId, target: target.rawValue, axis: axis, velocity: signed)
                if !self.held.contains(robotId) { self.deadMan.release(robotId) }
            } catch {
                self.held.remove(robotId)
                let api = error as? ApiError
                if api?.isUnknownCommand == true { self.deadManSupported = false }
                self.say("errTxError", ["command": "jogStart", "error": api?.message ?? api.map { "HTTP \($0.status)" } ?? "\(error)"])
                self.app.changed()
            }
        }
    }

    /// The button went up (or was lost): the stop leaves first.
    public func release(_ robotId: Int) {
        let was = held.remove(robotId) != nil
        deadMan.release(robotId)
        if was { app.changed() }
    }

    /// Ends every held jog: leaving the screen, a dialog, the app going away.
    public func interrupt() {
        let was = !held.isEmpty
        held = []
        deadMan.interrupt()
        if was { app.changed() }
    }

    private func jogEnded(_ robotId: Int, _ reason: DeadManEnd, _ stopConfirmed: Bool) {
        held.remove(robotId)
        if !stopConfirmed {
            say("deadManStopNotConfirmed")
        } else {
            switch reason {
            case .released, .interrupted: break
            case .linkLost: say("deadManEndedLinkLost")
            case .tooLong: say("deadManEndedTooLong")
            case .badLink: say("deadManEndedBadLink")
            case .serverRefused: say("deadManEndedRefused")
            }
        }
        app.changed()
    }

    /// One measure of the link. The Control screen asks for one every two seconds while it is open.
    public func probeLink() async {
        guard !probing, app.linkOk, let client = app.client, linkIndicator || deadManEnabled else { return }
        probing = true
        defer { probing = false }
        do {
            let rtt = try await client.ping()
            guard client === app.client else { return }
            link.record(rtt, now: now())
        } catch {
            link.recordFailure()
        }
        app.changed()
    }

    // MARK: - Works

    private func workFolder(_ robotId: Int) -> String? {
        guard let robot = info(robotId) else { return nil }
        return WorkFiles.folder(worksPaths: app.cell.raw["worksPaths"], robotId: robotId, robotName: robot.name)
    }

    public func workBlock(_ robotId: Int, tableMissing: Bool = false) -> WorkBlock {
        let robot = info(robotId)
        if app.client == nil { return .notConnected }
        if !worksSupported { return .notSupported }
        if !roleMayMove(role) { return .role }
        if robot?.online != true { return .offline }
        if robot?.enabled == false { return .safeMode }
        if stopInProgress { return .stopPending }
        if robot?.isPlaying == true { return .playing }
        return tableMissing ? .noTable : .none
    }

    public func selectedWork(_ robotId: Int) -> String { raw(robotId)?["selectedWorkFile"] as? String ?? "" }

    public func loadWorkList(_ robotId: Int) async {
        guard let client = app.client else {
            say("errNotConnected")
            return
        }
        guard let folder = workFolder(robotId) else {
            say("workLoadFailed")
            return
        }
        workBusy = true
        workFiles = nil
        app.changed()
        defer {
            workBusy = false
            app.changed()
        }
        do {
            let body = try await client.workBody(folder: folder, file: "index.json")
            guard client === app.client else { return }
            workFiles = WorkFiles.parseIndex(body) ?? []
        } catch let error as ApiError where error.isNotFound {
            workFiles = []
        } catch {
            say("workLoadFailed")
            if (error as? ApiError)?.isSessionProblem == true && client === app.client { app.sessionEnded() }
        }
    }

    /// Loads a work into the robot with `trajectory`. It never starts it.
    public func loadWork(_ robotId: Int, file: String) async {
        guard let client = app.client else {
            say("errNotConnected")
            return
        }
        guard let folder = workFolder(robotId), WorkFiles.isSafeFileName(file) else {
            say("workLoadFailed")
            return
        }
        let early = workBlock(robotId)
        if early != .none {
            say(early.textKey)
            return
        }
        workBusy = true
        app.changed()
        defer {
            workBusy = false
            app.changed()
        }
        do {
            let body = try await client.workBody(folder: folder, file: file)
            guard client === app.client else { return }
            guard let loaded = WorkFiles.parsePoints(body) else {
                say("workInvalidFile", ["file": file])
                return
            }
            // checked again: the robot may have started while the file was read
            let block = workBlock(robotId, tableMissing: loaded.usesTable && info(robotId)?.hasXYTable != true)
            if block != .none {
                say(block.textKey)
                return
            }
            let task = issue("trajectory", params: ["points": loaded.points, "selectedWorkFile": file], robot: robotId) { $0["selectedWorkFile"] = file }
            await task?.value
        } catch {
            say("workLoadFailed")
            if (error as? ApiError)?.isSessionProblem == true && client === app.client { app.sessionEnded() }
        }
    }
}
