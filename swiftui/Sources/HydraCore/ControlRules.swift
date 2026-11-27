// HYDRA-UMC-IOS-CONTROL - the rules of control: what may be sent, when and with which limits. No screen and no network here; the same rules as the published app.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// The constants of docs/robot_command_contract.json. A test reads that file and fails when one differs.
public enum Contract {
    public static let numbered: Set<String> = ["stop", "jog", "jogStart", "jogStop", "table", "reset", "joints"]
    public static let continuous: Set<String> = ["jog", "jogHeartbeat", "speed", "jogStep"]
    public static let speedMin = 10.0
    public static let speedMax = 500.0
    public static let jogStepMax = 1000.0
    public static let homeResetEnabledByDefault = false
    public static let homeResetConfirmSteps = 2
    public static let homeResetConfirmWindow: TimeInterval = 20
    public static let deadManEnabledByDefault = false
    public static let linkIndicatorEnabledByDefault = true
    public static let linkBlockJogOnBadLinkDefault = true
    public static let linkProbeInterval: TimeInterval = 2
    public static let linkProbeTimeout: TimeInterval = 1.5
    public static let linkSampleWindow = 8
    public static let linkGoodRttMs = 100
    public static let linkPoorRttMs = 250
    public static let linkBlockRttMs = 500
    public static let linkLostAfterMs = 4000
    public static let worksMaxPoints = 10000
    public static let worksFileMaxBytes = 2_000_000
    public static let worksFileNameMax = 128
    public static let worksFolderMax = 200
}

/// "Listen only": nothing is written to the server except what stops.
public enum ListenOnly {
    private static let allowedCommands: Set<String> = ["stop", "jogStop", "disable"]
    private static let sessionNames: Set<String> = ["login", "refresh", "logout"]

    public static func allows(method: String, path: String, body: Data?) -> Bool {
        let verb = method.uppercased()
        if verb == "GET" || verb == "HEAD" { return true }
        var parts = path.split(separator: "/").map(String.init)
        guard parts.first == "api" else { return false }
        parts.removeFirst()
        if parts.count == 1 && (sessionNames.contains(parts[0]) || parts[0] == "stop-all") { return true }
        if parts == ["device", "login"] { return true }
        if parts.count == 3 && parts[0] == "robot" && parts[2] == "command", let body,
           let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let command = json["command"] as? String {
            return allowedCommands.contains(command)
        }
        return false
    }
}

// MARK: - Reservations and limits

public struct ClaimInfo: Equatable, Sendable {
    public var robotId: Int
    public var robotName: String
    public var ownerUsername: String
    public var controllerId: String?
    public var expiresAt: Int64
    public var jogArmedUntil: Int64?

    public init(robotId: Int, robotName: String = "", ownerUsername: String, controllerId: String?, expiresAt: Int64, jogArmedUntil: Int64? = nil) {
        self.robotId = robotId
        self.robotName = robotName
        self.ownerUsername = ownerUsername
        self.controllerId = controllerId
        self.expiresAt = expiresAt
        self.jogArmedUntil = jogArmedUntil
    }

    public static func list(_ json: [String: Any]) -> [ClaimInfo] {
        (json["claims"] as? [Any] ?? []).compactMap { entry in
            guard let item = entry as? [String: Any], let robotId = item["robotId"] as? Int else { return nil }
            let controller = item["controllerId"] as? String
            let armed = (item["jogArmedUntil"] as? NSNumber)?.int64Value
            return ClaimInfo(robotId: robotId, robotName: item["robotName"] as? String ?? "", ownerUsername: item["ownerUsername"] as? String ?? "",
                             controllerId: controller?.isEmpty == false ? controller : nil, expiresAt: (item["expiresAt"] as? NSNumber)?.int64Value ?? 0,
                             jogArmedUntil: armed.flatMap { $0 > 0 ? $0 : nil })
        }
    }
}

public enum ClaimStanding: Equatable, Sendable {
    case free, mineHere, mineElsewhere, other

    public static func of(_ claim: ClaimInfo?, username: String, controllerId: String) -> ClaimStanding {
        guard let claim else { return .free }
        if claim.controllerId == controllerId { return .mineHere }
        if username.isEmpty || claim.ownerUsername != username { return .other }
        return claim.controllerId == nil ? .mineHere : .mineElsewhere
    }
}

public let claimRenewBeforeMs: Int64 = 120_000

public func claimNeedsRenewal(_ claim: ClaimInfo?, standing: ClaimStanding, nowMs: Int64, renewBeforeMs: Int64 = claimRenewBeforeMs) -> Bool {
    guard let claim, standing == .mineHere else { return false }
    let left = claim.expiresAt - nowMs
    return left > 0 && left <= renewBeforeMs
}

/// The role written in the session token, or nil. Only to show or hide; the server decides again.
public func jwtRole(_ token: String?) -> String? {
    guard let parts = token?.split(separator: ".", omittingEmptySubsequences: false), parts.count >= 2 else { return nil }
    var base = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    base += String(repeating: "=", count: (4 - base.count % 4) % 4)
    guard let data = Data(base64Encoded: base), let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let role = json["role"] as? String, !role.isEmpty else { return nil }
    return role
}

public func roleMayMove(_ role: String?) -> Bool { role == nil || role == "admin" || role == "operator" }

public func canTakeOverRobot(role: String?, standing: ClaimStanding) -> Bool { role == "admin" && (standing == .other || standing == .mineElsewhere) }

public struct JogLimits: Equatable, Sendable {
    public var maxAmount: Double
    public var maxAbsolute: Double

    public init(maxAmount: Double, maxAbsolute: Double) {
        self.maxAmount = maxAmount
        self.maxAbsolute = maxAbsolute
    }
}

public struct RobotSafety: Equatable, Sendable {
    public var jog: JogLimits
    public var armRequired: Bool
    public var armTtlMs: Int64
    public var jogArmedUntil: Int64?

    public init(jog: JogLimits, armRequired: Bool, armTtlMs: Int64 = 60_000, jogArmedUntil: Int64? = nil) {
        self.jog = jog
        self.armRequired = armRequired
        self.armTtlMs = armTtlMs
        self.jogArmedUntil = jogArmedUntil
    }

    public init?(json: [String: Any]) {
        guard let robot = json["robot"] as? [String: Any], let jog = robot["jog"] as? [String: Any],
              let amount = (jog["maxAmount"] as? NSNumber)?.doubleValue, let absolute = (jog["maxAbsolute"] as? NSNumber)?.doubleValue,
              amount > 0, absolute > 0 else { return nil }
        let global = (json["limits"] as? [String: Any])?["jog"] as? [String: Any]
        let armed = (robot["jogArmedUntil"] as? NSNumber)?.int64Value
        self.init(jog: JogLimits(maxAmount: amount, maxAbsolute: absolute), armRequired: global?["armRequired"] as? Bool == true,
                  armTtlMs: (global?["armTtlMs"] as? NSNumber)?.int64Value ?? 60_000, jogArmedUntil: armed.flatMap { $0 > 0 ? $0 : nil })
    }
}

/// The limit a jog goes over, or nil when it may be sent.
public func jogLimitExceeded(_ amount: Double, _ limits: JogLimits?, absolute: Bool = false) -> Double? {
    guard let limits else { return nil }
    let limit = absolute ? limits.maxAbsolute : limits.maxAmount
    return amount.isNaN || abs(amount) > limit ? limit : nil
}

public func formatLimit(_ limit: Double) -> String {
    let text = String(limit)
    return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
}

/// A table move is checked as a whole, and a relative one also by where it ends.
public func tableLimitExceeded(x: Double, y: Double, relative: Bool, _ limits: JogLimits?, currentX: Double = 0, currentY: Double = 0) -> Double? {
    guard let limits else { return nil }
    let limit = relative ? limits.maxAmount : limits.maxAbsolute
    for value in [x, y] where !value.isFinite || abs(value) > limit { return limit }
    if relative && (abs(currentX + x) > limits.maxAbsolute || abs(currentY + y) > limits.maxAbsolute) { return limits.maxAbsolute }
    return nil
}

/// The jogs a server without the `table` command understands.
public func tableAsJogs(_ params: [String: Any]) -> [[String: Any]] {
    let absolute = params["mode"] as? String != "relative"
    return ["x", "y"].compactMap { axis in
        guard let amount = (params[axis] as? NSNumber)?.doubleValue, amount.isFinite, absolute || amount != 0 else { return nil }
        var jog: [String: Any] = ["axis": axis, "amount": amount, "target": "xytable"]
        if absolute { jog["absolute"] = true }
        return jog
    }
}

// MARK: - Conditional writes

public enum ConditionalMode: String, CaseIterable, Sendable {
    case off, standard, strict

    public func applies(to command: String) -> Bool {
        if command == "stop" || self == .off { return false }
        return self == .strict || !Contract.continuous.contains(command)
    }
}

public func revisionOf(_ body: [String: Any]?) -> String? {
    guard let value = body?["revision"] as? String, value.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return nil }
    return value
}

/// The last revision seen of each robot.
public struct RevisionTracker {
    private var counter = 0
    private var known: [Int: (revision: String, seq: Int)] = [:]
    private var inFlight: [Int: Int] = [:]

    public init() {}

    public mutating func begin(_ robotId: Int, command: String, mode: ConditionalMode) -> (ifMatch: String?, seq: Int) {
        counter += 1
        let busy = (inFlight[robotId] ?? 0) > 0
        inFlight[robotId, default: 0] += 1
        var header: String?
        if !busy, let entry = known[robotId], mode.applies(to: command) { header = "\"\(entry.revision)\"" }
        return (header, counter)
    }

    public mutating func finish(_ robotId: Int, seq: Int, revision: String?) {
        let left = (inFlight[robotId] ?? 1) - 1
        inFlight[robotId] = left <= 0 ? nil : left
        guard let revision else {
            if left <= 0 { known[robotId] = nil }
            return
        }
        if let entry = known[robotId], seq < entry.seq { return }
        known[robotId] = (revision, seq)
    }

    public mutating func learn(_ robotId: Int, _ revision: String?) {
        guard let revision else {
            known[robotId] = nil
            return
        }
        counter += 1
        known[robotId] = (revision, counter)
    }

    public func revision(of robotId: Int) -> String? { known[robotId]?.revision }
}

// MARK: - HOME/RESET and PLAY

public enum HomeResetBlock: String, Equatable, Sendable {
    case none, off, notConnected, offline, safeMode, moving, jogBusy, stopPending, notArmed, role, noPose, notSupported

    public var textKey: String {
        switch self {
        case .notConnected: return "errNotConnected"
        case .notArmed: return "errJogNotArmed"
        case .notSupported: return "homeResetNotSupported"
        case .jogBusy: return "homeResetBlockedJog"
        case .stopPending: return "homeResetBlockedStop"
        default: return "homeResetBlocked" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

public struct HomeResetSituation: Sendable {
    public var switchedOn, connected, robotOnline, robotEnabled, robotPlaying, jogInFlight, stopInProgress, needsArming: Bool
    public var role: String?
    public var hasPose, serverSupports: Bool

    public init(switchedOn: Bool, connected: Bool, robotOnline: Bool, robotEnabled: Bool, robotPlaying: Bool, jogInFlight: Bool, stopInProgress: Bool,
                needsArming: Bool, role: String?, hasPose: Bool, serverSupports: Bool) {
        self.switchedOn = switchedOn
        self.connected = connected
        self.robotOnline = robotOnline
        self.robotEnabled = robotEnabled
        self.robotPlaying = robotPlaying
        self.jogInFlight = jogInFlight
        self.stopInProgress = stopInProgress
        self.needsArming = needsArming
        self.role = role
        self.hasPose = hasPose
        self.serverSupports = serverSupports
    }

    /// The first reason not to send it, in the order a person can fix them.
    public var block: HomeResetBlock {
        if !switchedOn { return .off }
        if !connected { return .notConnected }
        if !serverSupports { return .notSupported }
        if !roleMayMove(role) { return .role }
        if !robotOnline { return .offline }
        if !robotEnabled { return .safeMode }
        if stopInProgress { return .stopPending }
        if robotPlaying { return .moving }
        if jogInFlight { return .jogBusy }
        if needsArming { return .notArmed }
        if !hasPose { return .noPose }
        return .none
    }
}

/// The confirmation in steps: only the last one inside the window sends.
public struct HomeResetConfirmation {
    private var accepted = 0
    private var startedAt = Date.distantPast

    public init() {}

    /// True when this step was the last one.
    public mutating func advance(now: Date = Date(), steps: Int = Contract.homeResetConfirmSteps, window: TimeInterval = Contract.homeResetConfirmWindow) -> Bool {
        if accepted > 0 && now.timeIntervalSince(startedAt) > window { accepted = 0 }
        if accepted == 0 { startedAt = now }
        accepted += 1
        if accepted >= max(1, steps) {
            accepted = 0
            return true
        }
        return false
    }

    public mutating func cancel() { accepted = 0 }
}

public func playNeedsConfirmation(askBeforePlay: Bool, robotIsPlaying: Bool) -> Bool { askBeforePlay && !robotIsPlaying }

// MARK: - Link health

public enum LinkLevel: String, Equatable, Sendable { case unknown, good, poor, bad, lost }

/// The round trips to the server; a bad link blocks the continuous jog.
public struct LinkHealth {
    private var samples: [Int] = []
    private var lastAnswer: Date?
    private var failures = 0

    public init() {}

    public mutating func record(_ rttMs: Int, now: Date = Date()) {
        samples.append(max(0, rttMs))
        if samples.count > Contract.linkSampleWindow { samples.removeFirst(samples.count - Contract.linkSampleWindow) }
        lastAnswer = now
        failures = 0
    }

    public mutating func recordFailure() { failures += 1 }

    public mutating func reset() { self = LinkHealth() }

    public var lastMs: Int? { samples.last }
    public var worstMs: Int? { samples.max() }

    public func level(now: Date = Date()) -> LinkLevel {
        if failures >= 2 { return .lost }
        guard let worst = worstMs, let at = lastAnswer else { return failures > 0 ? .lost : .unknown }
        if now.timeIntervalSince(at) * 1000 > Double(Contract.linkLostAfterMs) { return .lost }
        if worst < Contract.linkGoodRttMs { return .good }
        return worst < Contract.linkPoorRttMs ? .poor : .bad
    }

    public func blocksJog(now: Date = Date()) -> Bool { level(now: now) == .lost || (worstMs ?? 0) >= Contract.linkBlockRttMs }
}

// MARK: - Work files

public enum WorkBlock: String, Equatable, Sendable {
    case none, notConnected, offline, safeMode, playing, stopPending, role, noTable, notSupported

    public var textKey: String {
        switch self {
        case .notConnected: return "errNotConnected"
        case .notSupported: return "workNotSupported"
        case .stopPending: return "workBlockedStop"
        default: return "workBlocked" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

public enum WorkFiles {
    public static let pointFields = ["j1", "j2", "j3", "j4", "j5", "j6", "x", "y", "z", "a", "b", "c", "tx", "ty", "trz"]

    public static func isSafeFileName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,\(Contract.worksFileNameMax - 1)}\\.json$", options: .regularExpression) != nil && !name.contains("\n")
    }

    /// The folder the server serves the works of a robot from; nil when what is configured would leave it.
    public static func folder(worksPaths: Any?, robotId: Int, robotName: String) -> String? {
        let configured = ((worksPaths as? [String: Any])?[String(robotId)] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var folder = configured.isEmpty ? "WORKS/" + robotName.components(separatedBy: .whitespacesAndNewlines).joined() : configured
        folder = folder.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !folder.isEmpty, folder.count <= Contract.worksFolderMax, !folder.contains("\n"),
              folder.range(of: "^[A-Za-z0-9_][A-Za-z0-9_ ./-]*$", options: .regularExpression) != nil,
              !folder.components(separatedBy: "/").contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        return folder
    }

    public static func parseIndex(_ data: Data) -> [String]? {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
        return Set(list.compactMap { $0 as? String }.filter(isSafeFileName)).sorted()
    }

    /// The points reduced to the fields the server keeps, or nil when the file is not a work.
    public static func parsePoints(_ data: Data) -> (points: [[String: Any]], usesTable: Bool)? {
        guard data.count <= Contract.worksFileMaxBytes, let root = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
              !root.isEmpty, root.count <= Contract.worksMaxPoints else { return nil }
        var clean: [[String: Any]] = []
        var usesTable = false
        for entry in root {
            guard let point = entry as? [String: Any] else { return nil }
            var out: [String: Any] = [:]
            for field in pointFields {
                guard let value = point[field] else { continue }
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
                out[field] = number.doubleValue
            }
            if let motion = point["motionType"] {
                guard motion as? String == "model-joints" else { return nil }
                out["motionType"] = "model-joints"
            }
            let hasJoints = ["j1", "j2", "j3", "j4", "j5", "j6"].allSatisfy { out[$0] != nil }
            guard hasJoints || ["x", "y", "z"].allSatisfy({ out[$0] != nil }) else { return nil }
            if ["tx", "ty", "trz"].contains(where: { out[$0] != nil }) { usesTable = true }
            clean.append(out)
        }
        return (clean, usesTable)
    }
}
