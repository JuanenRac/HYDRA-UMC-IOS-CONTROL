// HYDRA-UMC-IOS-CONTROL - the state of the cell as the server tells it: the settings tree (kept as it came), what is read from it, the copy
// saved on the phone, the line of the Home screen and the progress of a CAN flash. The same rules as the published apps.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// One robot as the screens show it.
public struct RobotInfo: Equatable, Sendable, Identifiable {
    public var controllerId: String?
    public var robotId: Int
    public var name: String
    public var role: String
    public var model: String
    public var tool: String
    public var online: Bool
    /// False while the robot is in safe mode; a robot that says nothing is enabled.
    public var enabled: Bool
    public var isPlaying: Bool
    public var isPaused: Bool
    public var x, y, z: Double
    public var hasXYTable: Bool
    public var xyX, xyY: Double
    public var speed: Double
    public var acceleration: Double
    /// The short names of the modules the robot has (CAM, XY, ATC...).
    public var modules: [String]
    public var id: String { "\(controllerId ?? "")/\(robotId)" }

    public var isMoving: Bool { isPlaying && !isPaused }

    public init(controllerId: String?, robotId: Int, raw: [String: Any]) {
        func map(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
        func number(_ value: Any?, _ fallback: Double = 0) -> Double { (value as? NSNumber)?.doubleValue ?? fallback }
        func enabledModule(_ key: String) -> Bool { map(raw[key])["enabled"] as? Bool == true }
        self.controllerId = controllerId
        self.robotId = robotId
        name = raw["name"] as? String ?? "Robot \(robotId)"
        role = raw["role"] as? String ?? ""
        model = raw["model"] as? String ?? "Generic (6-DOF)"
        tool = raw["tool"] as? String ?? "None"
        online = raw["online"] as? Bool == true
        enabled = raw["enabled"] as? Bool != false
        let playback = map(raw["playbackState"])
        isPlaying = (playback["isPlaying"] ?? playback["playing"]) as? Bool == true
        isPaused = (playback["isPaused"] ?? playback["paused"]) as? Bool == true
        speed = number(playback["speed"], 100)
        acceleration = number(playback["acceleration"], 100)
        let pos = map(raw["pos"])
        x = number(pos["x"]); y = number(pos["y"]); z = number(pos["z"])
        let xy = map(map(raw["xyTable"])["pos"])
        hasXYTable = raw["hasXYTable"] as? Bool == true
        xyX = number(xy["x"]); xyY = number(xy["y"])
        var found: [String] = []
        if raw["visionEnabled"] as? Bool == true || map(raw["camera"])["connected"] as? Bool == true { found.append("CAM") }
        if hasXYTable { found.append("XY") }
        if raw["atc"] != nil { found.append("ATC") }
        if enabledModule("juanenPnP") || enabledModule("lumenPnP") { found.append("PNP") }
        if enabledModule("juanenCNC") { found.append("CNC") }
        if enabledModule("juanenLaser") { found.append("LSR") }
        if enabledModule("heatedBed") { found.append("BED") }
        if enabledModule("vacuumTable") { found.append("VAC") }
        if enabledModule("rackSystem") { found.append("RCK") }
        modules = found
    }
}

/// The settings tree. Changes of the live link are folded into it; fields the app does not know pass through untouched.
public struct CellState {
    public private(set) var raw: [String: Any]

    public init(_ raw: [String: Any] = [:]) { self.raw = raw }

    private var controllers: [[String: Any]] { (raw["controllers"] as? [Any] ?? []).compactMap { $0 as? [String: Any] } }

    public var controllerCount: Int { controllers.count }

    public var robots: [RobotInfo] {
        controllers.flatMap { controller -> [RobotInfo] in
            let controllerId = controller["id"] as? String
            return (controller["robots"] as? [Any] ?? []).compactMap { entry in
                guard let robot = entry as? [String: Any], let robotId = robot["id"] as? Int else { return nil }
                return RobotInfo(controllerId: controllerId, robotId: robotId, raw: robot)
            }
        }
    }

    public var roster: [RosterRobot] { RosterRobot.list(settings: raw) }

    /// Applies `{controllerId, robotId, patch, cameraId?, cameraPatch?}`. False when the robot is not known (or the message is not one):
    /// a partial change never creates a robot, the whole state has to be read again.
    public mutating func apply(delta: [String: Any]) -> Bool {
        guard let controllerId = delta["controllerId"] as? String, let robotId = delta["robotId"] as? Int,
              let patch = delta["patch"] as? [String: Any] else { return false }
        var list = raw["controllers"] as? [Any] ?? []
        for (index, entry) in list.enumerated() {
            guard var controller = entry as? [String: Any], controller["id"] as? String == controllerId else { continue }
            var robots = controller["robots"] as? [Any] ?? []
            guard let at = robots.firstIndex(where: { ($0 as? [String: Any])?["id"] as? Int == robotId }), var robot = robots[at] as? [String: Any] else { return false }
            robot.merge(patch) { _, new in new }
            robots[at] = robot
            controller["robots"] = robots
            if let cameraId = delta["cameraId"] as? NSObject, let cameraPatch = delta["cameraPatch"] as? [String: Any] {
                var cameras = controller["cameras"] as? [Any] ?? []
                if let c = cameras.firstIndex(where: { (($0 as? [String: Any])?["id"] as? NSObject) == cameraId }), var camera = cameras[c] as? [String: Any] {
                    camera.merge(cameraPatch) { _, new in new }
                    cameras[c] = camera
                    controller["cameras"] = cameras
                }
            }
            list[index] = controller
            raw["controllers"] = list
            return true
        }
        return false
    }

    /// Shows a robot the server said it stopped as stopped, until the state of the server arrives.
    public mutating func markStopped(controllerId: String?, robotId: Int) {
        var list = raw["controllers"] as? [Any] ?? []
        for (index, entry) in list.enumerated() {
            guard var controller = entry as? [String: Any], controllerId == nil || controller["id"] as? String == controllerId else { continue }
            var robots = controller["robots"] as? [Any] ?? []
            for (at, item) in robots.enumerated() {
                guard var robot = item as? [String: Any], robot["id"] as? Int == robotId else { continue }
                var playback = robot["playbackState"] as? [String: Any] ?? [:]
                for key in ["isPlaying", "playing", "isPaused", "paused", "requestPause"] { playback[key] = false }
                playback["requestStop"] = true
                playback["activeStep"] = -1
                robot["playbackState"] = playback
                robots[at] = robot
            }
            controller["robots"] = robots
            list[index] = controller
        }
        raw["controllers"] = list
    }
}

/// Where the copy of the last state is kept (a file of the app).
public protocol CacheStore: AnyObject {
    func read() -> Data?
    func write(_ data: Data?)
}

/// The last state read, saved so the screens are not empty while the link opens or when there is none. Never a source of truth.
/// It belongs to one account of one server; asking for another erases it. Camera credentials never reach the disk.
public struct StateCache {
    private let store: CacheStore
    private static let secretKeys: Set<String> = ["ipUsername", "ipPassword"]

    public init(store: CacheStore) { self.store = store }

    public static func scope(address: ServerAddress, username: String) -> String { "\(username)@\(address.key)" }

    public static func redact(_ value: Any) -> Any {
        if let map = value as? [String: Any] {
            return map.filter { !secretKeys.contains($0.key) }.mapValues(redact)
        }
        if let list = value as? [Any] { return list.map(redact) }
        return value
    }

    public func save(_ raw: [String: Any], scope: String, at: Date) {
        let entry: [String: Any] = ["scope": scope, "savedAt": at.timeIntervalSince1970, "state": StateCache.redact(raw)]
        guard JSONSerialization.isValidJSONObject(entry), let data = try? JSONSerialization.data(withJSONObject: entry) else { return }
        store.write(data)
    }

    /// The copy of that scope and when it was saved, or nil.
    public func load(scope: String) -> (state: [String: Any], savedAt: Date)? {
        guard let data = store.read() else { return nil }
        guard let entry = HydraClient.object(data), entry["scope"] as? String == scope, let state = entry["state"] as? [String: Any],
              let savedAt = entry["savedAt"] as? Double else {
            store.write(nil)
            return nil
        }
        return (state, Date(timeIntervalSince1970: savedAt))
    }

    public func clear() { store.write(nil) }

    /// Erases the copy only when it is the one of that scope.
    public func clear(scope: String) {
        if let data = store.read(), HydraClient.object(data)?["scope"] as? String == scope { store.write(nil) }
    }
}

/// The one line at the top of the Home screen. The worst thing wins.
public enum HomeState: Equatable {
    case connecting, notConnected, noRobots
    case safeMode(Int), offline(Int), moving(Int), ready(Int)

    public static func of(link: LinkStatus, robots: [RobotInfo]) -> HomeState {
        if link == .connecting { return .connecting }
        if link != .connected { return .notConnected }
        if robots.isEmpty { return .noRobots }
        let safe = robots.filter { !$0.enabled }.count
        if safe > 0 { return .safeMode(safe) }
        let away = robots.filter { !$0.online }.count
        if away > 0 { return .offline(away) }
        let moving = robots.filter(\.isMoving).count
        if moving > 0 { return .moving(moving) }
        return .ready(robots.count)
    }
}

/// The steps of an installation: what is not known is never shown as pending.
public struct SetupSteps: Equatable {
    public enum Step: String, Equatable { case server, controller, robot }
    public var pending: [Step]
    public var done: Int
    public var total: Int

    public static func of(server: Bool?, controller: Bool?, robot: Bool?) -> SetupSteps {
        let answers: [(Step, Bool?)] = [(.server, server), (.controller, controller), (.robot, robot)]
        return SetupSteps(pending: answers.filter { $0.1 == false }.map(\.0), done: answers.filter { $0.1 == true }.count, total: answers.filter { $0.1 != nil }.count)
    }
}

/// The load of the server (`GET /api/system/metrics`).
public struct SystemMetrics: Equatable, Sendable {
    public var cpuLoad: Int
    public var memoryUsage: Int
    /// nil when the server says its temperature is not a real reading.
    public var temperature: Double?
    public var uptime: Int

    public init(json: [String: Any]) {
        func whole(_ key: String) -> Int { (json[key] as? NSNumber)?.intValue ?? 0 }
        cpuLoad = whole("cpu_load")
        memoryUsage = whole("memory_usage")
        uptime = whole("uptime")
        temperature = json["temp_is_real"] as? Bool == false ? nil : (json["temp"] as? NSNumber)?.doubleValue
    }

    public static func uptimeText(_ seconds: Int) -> String {
        let d = seconds / 86400, h = (seconds % 86400) / 3600, m = (seconds % 3600) / 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

/// One report of a flash cycle of a board. The app only shows it; it starts no flash.
public struct CanOtaProgress: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case connecting, transferring, verifying, rebooting, done, error
        case enteringBootloader = "entering_bootloader"
        case erasingFram = "erasing_fram"

        public var textKey: String {
            "canOtaPhase" + rawValue.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        }
    }

    public var phase: Phase
    public var percent: Int?
    public var pagesSent: Int?
    public var pagesTotal: Int?
    public var error: String?

    /// nil when the message names no phase the app knows. Nothing is guessed: a missing number stays nil.
    public init?(message: [String: Any]) {
        guard let payload = message["payload"] as? [String: Any], let name = payload["phase"] as? String, let phase = Phase(rawValue: name) else { return nil }
        func count(_ key: String) -> Int? {
            guard let number = (payload[key] as? NSNumber)?.doubleValue, number >= 0, number <= Double(Int32.max), number == number.rounded(.down) else { return nil }
            return Int(number)
        }
        self.phase = phase
        percent = (payload["percent"] as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? Int(min(100, max(0, $0.rounded()))) : nil }
        pagesSent = count("pages_sent")
        pagesTotal = count("pages_total")
        let reason = (payload["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        error = reason.isEmpty ? nil : String(reason.prefix(300))
    }
}

/// How often the app renews the session by itself: not again within 20 s, and at most 3 times in 10 minutes.
public struct RenewalBudget {
    private var times: [Date] = []

    public init() {}

    public mutating func tryAcquire(now: Date) -> Bool {
        times.removeAll { now.timeIntervalSince($0) > 600 }
        if times.count >= 3 { return false }
        if let last = times.last, now.timeIntervalSince(last) < 20 { return false }
        times.append(now)
        return true
    }

    public mutating func reset() { times = [] }
}
