// HYDRA-UMC-IOS-CONTROL - the notices of the phone (what it saw while open and the messages it received), and the fault record and board
// health the server keeps. The same rules as the Android app.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum NoticeGroup: String, CaseIterable, Sendable { case robots, server, jobs }

public enum NoticeKind: String, Sendable {
    case connectionLost, connectionRestored, robotOffline, robotSafeMode, stopNotConfirmed, stopConfirmed, jobDone, serverMessage

    public var group: NoticeGroup {
        switch self {
        case .connectionLost, .connectionRestored, .serverMessage: return .server
        case .robotOffline, .robotSafeMode, .stopNotConfirmed, .stopConfirmed: return .robots
        case .jobDone: return .jobs
        }
    }

    /// Whether it counts as something to look at.
    public var attention: Bool {
        switch self {
        case .connectionLost, .robotOffline, .robotSafeMode, .stopNotConfirmed, .serverMessage: return true
        case .connectionRestored, .stopConfirmed, .jobDone: return false
        }
    }

    public var textKey: String {
        switch self {
        case .connectionLost: return "noticeLost"
        case .connectionRestored: return "noticeRestored"
        case .robotOffline: return "noticeOffline"
        case .robotSafeMode: return "noticeSafeMode"
        case .stopNotConfirmed: return "noticeStopUnconfirmed"
        case .stopConfirmed: return "noticeStopConfirmed"
        case .jobDone: return "noticesJobDone"
        case .serverMessage: return ""
        }
    }
}

/// One notice. `detail` is a robot name or the text of a server message.
public struct Notice: Equatable, Sendable {
    public var kind: NoticeKind
    public var detail: String
    public var at: Date
    public var seen: Bool

    public init(kind: NoticeKind, detail: String = "", at: Date, seen: Bool = false) {
        self.kind = kind
        self.detail = detail
        self.at = at
        self.seen = seen
    }
}

public enum Notices {
    public static let max = 100
    static let detailMax = 300

    /// The newest first; the oldest fall off.
    public static func add(_ list: [Notice], _ notice: Notice) -> [Notice] {
        var cut = notice
        cut.detail = String(cut.detail.prefix(detailMax))
        return Array(([cut] + list).prefix(max))
    }

    public static func unseen(_ list: [Notice]) -> Int { list.filter { !$0.seen && $0.kind.attention }.count }

    public static func encode(_ list: [Notice]) -> String {
        let entries: [[String: Any]] = list.map { ["kind": $0.kind.rawValue, "detail": $0.detail, "at": $0.at.timeIntervalSince1970, "seen": $0.seen] }
        return (try? JSONSerialization.data(withJSONObject: entries)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// A damaged or unknown entry is dropped, never an error.
    public static func decode(_ text: String) -> [Notice] {
        guard let entries = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [Any] else { return [] }
        let read: [Notice] = entries.compactMap { entry in
            guard let map = entry as? [String: Any], let kind = (map["kind"] as? String).flatMap(NoticeKind.init(rawValue:)) else { return nil }
            return Notice(kind: kind, detail: map["detail"] as? String ?? "", at: Date(timeIntervalSince1970: (map["at"] as? NSNumber)?.doubleValue ?? 0),
                          seen: map["seen"] as? Bool == true)
        }
        return Array(read.prefix(max))
    }
}

// MARK: - What deserves a notice

public struct PlantRobot: Equatable, Sendable {
    public var id: String
    public var name: String
    public var online: Bool
    public var enabled: Bool
    public var playing: Bool

    public init(id: String, name: String, online: Bool, enabled: Bool, playing: Bool) {
        self.id = id
        self.name = name
        self.online = online
        self.enabled = enabled
        self.playing = playing
    }
}

public enum PlantStop: Equatable, Sendable { case none, sending, notConfirmed, done }

public struct PlantEvent: Equatable, Sendable {
    public var kind: NoticeKind
    public var critical: Bool
    public var robotName: String
    public var key: String
}

/// Looks at what the phone sees over time and says which changes deserve a notice, rationed so a burst never floods the list:
/// the same event is not repeated within the dedupe window, the others are spaced and capped per minute, and a critical one is
/// only held back by the dedupe. The numbers are the `watchAlerts` block of `docs/robot_command_contract.json`.
public struct AlertRules {
    public static let dedupeWindow: TimeInterval = 30
    public static let minGap: TimeInterval = 2
    public static let maxPerMinute = 6
    public static let connectionLostAfter: TimeInterval = 10

    private var initialised = false
    private var everConnected = false
    private var lostSince: Date?
    private var lostAnnounced = false
    private var playingWhenLost = false
    private var robots: [PlantRobot] = []
    private var stop = PlantStop.none
    private var lastByKey: [String: Date] = [:]
    private var sent: [Date] = []
    private var lastAny = Date.distantPast

    public init() {}

    /// Call it about once a second; the first call only learns the starting point.
    public mutating func observe(connected: Bool, robots now: [PlantRobot], stop newStop: PlantStop, at time: Date) -> [PlantEvent] {
        if !initialised {
            initialised = true
            everConnected = connected
            robots = now
            stop = newStop
            return []
        }
        var found: [PlantEvent] = []
        if connected {
            everConnected = true
            if lostAnnounced { found.append(PlantEvent(kind: .connectionRestored, critical: false, robotName: "", key: "restored")) }
            lostSince = nil
            lostAnnounced = false
            let after = Dictionary(now.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for before in robots {
                guard let robot = after[before.id] else { continue }
                if before.online && !robot.online {
                    found.append(PlantEvent(kind: .robotOffline, critical: before.playing, robotName: robot.name, key: "offline:\(robot.id)"))
                } else if robot.online && before.enabled && !robot.enabled {
                    found.append(PlantEvent(kind: .robotSafeMode, critical: false, robotName: robot.name, key: "safe:\(robot.id)"))
                }
            }
            robots = now
        } else if everConnected {
            if let since = lostSince {
                if !lostAnnounced && time.timeIntervalSince(since) >= AlertRules.connectionLostAfter {
                    lostAnnounced = true
                    found.append(PlantEvent(kind: .connectionLost, critical: playingWhenLost, robotName: "", key: "lost"))
                }
            } else {
                lostSince = time
                playingWhenLost = robots.contains(where: \.playing)
            }
        }
        if newStop != stop {
            if newStop == .notConfirmed {
                found.append(PlantEvent(kind: .stopNotConfirmed, critical: true, robotName: "", key: "stop-not-confirmed"))
            } else if newStop == .done && (stop == .sending || stop == .notConfirmed) {
                found.append(PlantEvent(kind: .stopConfirmed, critical: false, robotName: "", key: "stop-confirmed"))
            }
            stop = newStop
        }
        return ration(found, time)
    }

    private mutating func ration(_ events: [PlantEvent], _ time: Date) -> [PlantEvent] {
        var out: [PlantEvent] = []
        // the gap is measured from the notices of earlier looks: what was found together goes out together
        let gapFrom = lastAny
        for event in events.filter(\.critical) + events.filter({ !$0.critical }) {
            if let last = lastByKey[event.key], time.timeIntervalSince(last) < AlertRules.dedupeWindow { continue }
            if !event.critical {
                sent.removeAll { time.timeIntervalSince($0) >= 60 }
                if time.timeIntervalSince(gapFrom) < AlertRules.minGap || sent.count >= AlertRules.maxPerMinute { continue }
            }
            lastByKey[event.key] = time
            lastAny = time
            sent.append(time)
            out.append(event)
        }
        return out
    }
}

// MARK: - The record of the server

/// One line of the fault record. `at` is when it was raised (an active fault) or recorded (the history).
public struct ServerFault: Equatable, Sendable {
    public var source: String
    public var robotId: String?
    public var code: String
    /// "info", "warning", "error" or "critical"; an unknown word is read as "error".
    public var severity: String
    public var text: String
    public var cleared: Bool
    public var at: Date
}

public struct FaultRecord: Equatable, Sendable {
    public static let limit = 50
    public var active: [ServerFault]
    public var recent: [ServerFault]

    /// The answer of `GET /api/faults`, newest first; nil when it is not that answer. What cannot be read is left out.
    public static func parse(_ json: [String: Any]) -> FaultRecord? {
        guard let active = json["active"] as? [Any] else { return nil }
        func text(_ map: [String: Any], _ key: String, _ max: Int) -> String {
            let value = (map[key] as? String) ?? (map[key] as? NSNumber)?.stringValue ?? ""
            return String(value.prefix(max))
        }
        func list(_ entries: [Any], _ timeKey: String) -> [ServerFault] {
            entries.compactMap { entry -> ServerFault? in
                guard let map = entry as? [String: Any] else { return nil }
                let source = text(map, "source", 64)
                let code = text(map, "code", 64)
                guard !source.isEmpty, !code.isEmpty else { return nil }
                let severity = text(map, "severity", 16)
                let robot = text(map, "robotId", 64)
                return ServerFault(source: source, robotId: robot.isEmpty ? nil : robot, code: code,
                                   severity: ["info", "warning", "error", "critical"].contains(severity) ? severity : "error",
                                   text: text(map, "text", 240), cleared: text(map, "state", 16) == "cleared",
                                   at: Date(timeIntervalSince1970: ((map[timeKey] as? NSNumber)?.doubleValue ?? 0) / 1000))
            }.sorted { $0.at > $1.at }
        }
        return FaultRecord(active: list(active, "since"), recent: Array(list(json["recent"] as? [Any] ?? [], "at").prefix(limit)))
    }
}

/// One controller board as the server last heard it.
public struct BoardHealth: Equatable, Sendable {
    public static let slots = 0...7

    public var slot: Int
    /// False when the controller of the server did not answer the query.
    public var online: Bool
    /// False when no health frame of the slot was ever heard.
    public var heard: Bool
    public var ageMs: Int?
    public var flags: [String]
    public var txErrors: Int?
    public var rxErrors: Int?
    public var stalls: Int?
    public var uptimeS: Int?

    public init?(json: [String: Any]) {
        func whole(_ key: String) -> Int? { (json[key] as? NSNumber)?.intValue }
        guard let slot = whole("slot"), let online = json["online"] as? Bool else { return nil }
        self.slot = slot
        self.online = online
        heard = json["heard"] as? Bool == true
        ageMs = whole("ageMs")
        flags = (json["flagNames"] as? [Any] ?? []).compactMap { $0 as? String }
        txErrors = whole("txErrors")
        rxErrors = whole("rxErrors")
        stalls = whole("stalls")
        uptimeS = whole("uptimeS")
    }
}

/// Why one of the two readings is not there.
public enum ReadingProblem: Equatable, Sendable {
    case off, forbidden, session, unavailable, network

    public static func of(_ error: Error) -> ReadingProblem {
        guard let api = error as? ApiError else { return .network }
        if api.isSessionProblem { return .session }
        if api.status == 403 { return .forbidden }
        if api.status == 404 { return .off }
        return .unavailable
    }
}

/// What was read of the server, with the key of the server it came from, so it is never shown as another one's.
public struct ServerReading: Equatable, Sendable {
    public var server: String
    public var faults: FaultRecord?
    public var faultsProblem: ReadingProblem?
    public var boards: [BoardHealth] = []
    public var boardsProblem: ReadingProblem?
}
