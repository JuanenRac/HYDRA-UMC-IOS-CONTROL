// HYDRA-UMC-IOS-CONTROL - the global STOP: one tap, no confirmation, every robot. It waits for nothing, no reservation or mode blocks it, and while no answer came the app says so.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// A robot of the installation, as far as the stop needs to know it.
public struct RosterRobot: Equatable, Sendable, Identifiable {
    public var controllerId: String?
    public var robotId: Int
    public var name: String
    public var id: String { "\(controllerId ?? "")/\(robotId)" }

    public init(controllerId: String?, robotId: Int, name: String) {
        self.controllerId = controllerId
        self.robotId = robotId
        self.name = name
    }

    /// The robots of every controller of the answer of `GET /api/settings`.
    public static func list(settings: [String: Any]) -> [RosterRobot] {
        var result: [RosterRobot] = []
        for case let controller as [String: Any] in settings["controllers"] as? [Any] ?? [] {
            let controllerId = controller["id"] as? String
            for case let robot as [String: Any] in controller["robots"] as? [Any] ?? [] {
                guard let robotId = robot["id"] as? Int else { continue }
                let name = robot["name"] as? String ?? String(robotId)
                result.append(RosterRobot(controllerId: controllerId, robotId: robotId, name: name))
            }
        }
        return result
    }
}

public struct StoppedRobot: Equatable, Sendable, Identifiable {
    public var name: String
    public var stopped: Bool
    public var reservedBy: String?
    public var error: String?
    public var id = UUID()

    public init(name: String, stopped: Bool, reservedBy: String? = nil, error: String? = nil) {
        self.name = name
        self.stopped = stopped
        self.reservedBy = reservedBy
        self.error = error
    }

    public static func == (a: StoppedRobot, b: StoppedRobot) -> Bool {
        a.name == b.name && a.stopped == b.stopped && a.reservedBy == b.reservedBy && a.error == b.error
    }
}

public struct StopAllResult: Equatable, Sendable {
    public var success: Bool
    public var stoppedCount: Int
    public var failedCount: Int
    public var persisted: Bool
    public var robots: [StoppedRobot]
    public var viaFallback: Bool

    public var needsAttention: Bool { failedCount > 0 || !persisted || !success }

    public init(json: [String: Any]) {
        var list: [StoppedRobot] = []
        for case let robot as [String: Any] in json["robots"] as? [Any] ?? [] {
            let name = robot["name"] as? String ?? (robot["robotId"] as? Int).map(String.init) ?? "?"
            list.append(StoppedRobot(name: name, stopped: robot["stopped"] as? Bool == true, reservedBy: robot["reservedBy"] as? String, error: robot["error"] as? String))
        }
        success = json["success"] as? Bool == true
        stoppedCount = json["stoppedCount"] as? Int ?? list.filter(\.stopped).count
        failedCount = json["failedCount"] as? Int ?? list.filter { !$0.stopped }.count
        persisted = json["persisted"] as? Bool != false
        robots = list
        viaFallback = false
    }

    public init(fallback robots: [StoppedRobot]) {
        let stopped = robots.filter(\.stopped).count
        success = stopped == robots.count
        stoppedCount = stopped
        failedCount = robots.count - stopped
        persisted = true
        self.robots = robots
        viaFallback = true
    }
}

/// Numbers motion commands: milliseconds since 1970, always rising.
public final class CommandSequence {
    private var last: Int64 = 0
    private let clock: () -> Int64

    public init(clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) { self.clock = clock }

    public func next() -> Int64 {
        last = max(last + 1, clock())
        return last
    }
}

public enum StopOutcome: Equatable {
    case answered(StopAllResult)
    /// No answer: the robots may still be moving. `sessionEnded` when the session could not be renewed.
    case unconfirmed(sessionEnded: Bool)
}

@MainActor
public enum GlobalStop {
    public static let retryPause: UInt64 = 250_000_000

    /// Sends the stop. A network failure is tried once more; over the rate limit (429) or without the route (404) every known robot is stopped one by one.
    public static func run(client: HydraClient, roster: [RosterRobot], sequence: CommandSequence) async -> StopOutcome {
        do {
            do {
                return .answered(StopAllResult(json: try await client.stopAll()))
            } catch let error as ApiError {
                throw error
            } catch {
                try? await Task.sleep(nanoseconds: retryPause)
                return .answered(StopAllResult(json: try await client.stopAll()))
            }
        } catch let error as ApiError {
            if error.isRateLimited || error.isNotFound { return await eachRobot(client: client, roster: roster, sequence: sequence) }
            return .unconfirmed(sessionEnded: error.isSessionProblem)
        } catch {
            return .unconfirmed(sessionEnded: false)
        }
    }

    private static func eachRobot(client: HydraClient, roster: [RosterRobot], sequence: CommandSequence) async -> StopOutcome {
        var targets = roster
        if targets.isEmpty { targets = RosterRobot.list(settings: (try? await client.settings()) ?? [:]) }
        // With no robot known nothing was stopped: that is never reported as a success.
        if targets.isEmpty { return .unconfirmed(sessionEnded: false) }
        let numbered = targets.map { ($0, sequence.next()) }
        var tasks: [Task<StoppedRobot, Never>] = []
        for (robot, number) in numbered {
            tasks.append(Task { @MainActor in
                do {
                    try await client.stopRobot(robot.robotId, sequence: number)
                    return StoppedRobot(name: robot.name, stopped: true)
                } catch {
                    let detail = (error as? ApiError).map { "HTTP \($0.status)" }
                    return StoppedRobot(name: robot.name, stopped: false, error: detail)
                }
            })
        }
        var results: [StoppedRobot] = []
        for task in tasks { results.append(await task.value) }
        return .answered(StopAllResult(fallback: results))
    }
}
