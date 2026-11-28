// HYDRA-UMC-IOS-CONTROL - the continuous jog held by a dead-man: jogStart, a heartbeat while the control is held, jogStop on release. It stops by itself when the link does not answer.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public struct DeadManSettings: Sendable {
    public var heartbeatMs = 100
    public var serverTimeoutMs = 300
    public var maxMissedHeartbeats = 2
    public var maxHoldMs = 30000
    public var stopAttempts = 3
    public var stopRetryPauseMs = 100
    public var stopTimeoutMs = 2000
    public static let velocityDefault = 20.0
    public static let velocityMin = 1.0
    public static let velocityMax = 100.0

    public init() {}
}

public enum DeadManBlock: String, Equatable, Sendable {
    case none, off, notConnected, offline, safeMode, moving, stopPending, notArmed, role, badLink, alreadyRunning, notSupported

    public var textKey: String {
        switch self {
        case .notConnected: return "errNotConnected"
        case .notArmed: return "errJogNotArmed"
        case .stopPending: return "deadManBlockedStop"
        case .alreadyRunning: return "deadManBlockedAlready"
        default: return "deadManBlocked" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

public struct DeadManSituation: Sendable {
    public var switchedOn, connected, robotOnline, robotEnabled, robotPlaying, stopInProgress, needsArming: Bool
    public var role: String?
    public var linkBlocks, alreadyRunning, serverSupports: Bool

    public init(switchedOn: Bool, connected: Bool, robotOnline: Bool, robotEnabled: Bool, robotPlaying: Bool, stopInProgress: Bool, needsArming: Bool,
                role: String?, linkBlocks: Bool, alreadyRunning: Bool, serverSupports: Bool) {
        self.switchedOn = switchedOn
        self.connected = connected
        self.robotOnline = robotOnline
        self.robotEnabled = robotEnabled
        self.robotPlaying = robotPlaying
        self.stopInProgress = stopInProgress
        self.needsArming = needsArming
        self.role = role
        self.linkBlocks = linkBlocks
        self.alreadyRunning = alreadyRunning
        self.serverSupports = serverSupports
    }

    /// The first reason not to start, in the order a person can fix them.
    public var block: DeadManBlock {
        if !switchedOn { return .off }
        if !connected { return .notConnected }
        if !serverSupports { return .notSupported }
        if !roleMayMove(role) { return .role }
        if !robotOnline { return .offline }
        if !robotEnabled { return .safeMode }
        if stopInProgress { return .stopPending }
        if robotPlaying { return .moving }
        if needsArming { return .notArmed }
        if alreadyRunning { return .alreadyRunning }
        if linkBlocks { return .badLink }
        return .none
    }
}

public enum DeadManEnd: String, Equatable, Sendable { case released, linkLost, tooLong, badLink, serverRefused, interrupted }

public func clampDeadManVelocity(_ velocity: Double) -> Double {
    if velocity.isNaN || velocity == 0 { return DeadManSettings.velocityMin }
    let magnitude = min(DeadManSettings.velocityMax, max(DeadManSettings.velocityMin, abs(velocity)))
    return velocity < 0 ? -magnitude : magnitude
}

/// Decides when a held jog has to end, from the acknowledgements.
public struct DeadManWatchdog {
    private let settings: DeadManSettings
    private let clock: () -> Int
    private let startedAt: Int
    private var lastAck: Int
    public private(set) var missedInARow = 0

    public init(settings: DeadManSettings, clock: @escaping () -> Int) {
        self.settings = settings
        self.clock = clock
        startedAt = clock()
        lastAck = startedAt
    }

    public mutating func acked() {
        lastAck = clock()
        missedInARow = 0
    }

    public mutating func missed() { missedInARow += 1 }

    public func verdict() -> DeadManEnd? {
        let now = clock()
        if missedInARow >= settings.maxMissedHeartbeats { return .linkLost }
        if now - lastAck > settings.serverTimeoutMs { return .linkLost }
        if now - startedAt > settings.maxHoldMs { return .tooLong }
        return nil
    }
}

/// How one dead-man command reaches the server.
public typealias DeadManPoster = @MainActor (_ robotId: Int, _ command: String, _ params: [String: Any]) async throws -> Void

/// The first of the answer and the time limit.
@MainActor
private final class FirstAnswer {
    var continuation: CheckedContinuation<Void, Error>?
    var tasks: [Task<Void, Never>] = []

    func finish(_ result: Result<Void, Error>) {
        guard let waiting = continuation else { return }
        continuation = nil
        for task in tasks { task.cancel() }
        tasks = []
        waiting.resume(with: result)
    }
}

/// Waits for an answer at most that long. The answer that arrives later is dropped.
@MainActor
private func within(milliseconds: Int, _ work: @escaping @MainActor () async throws -> Void) async throws {
    let first = FirstAnswer()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        first.continuation = continuation
        first.tasks.append(Task { @MainActor in
            do {
                try await work()
                first.finish(.success(()))
            } catch {
                first.finish(.failure(error))
            }
        })
        first.tasks.append(Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
            if !Task.isCancelled { first.finish(.failure(TransportError.timeout)) }
        })
    }
}

@MainActor
public final class DeadManRunner {
    private final class Session {
        let robotId: Int
        let id: String
        var ending = false

        init(_ robotId: Int, _ id: String) {
            self.robotId = robotId
            self.id = id
        }
    }

    public let settings: DeadManSettings
    private let poster: DeadManPoster
    private let clock: () -> Int
    public var linkAllows: () -> Bool = { true }
    public var onRoundTrip: (Int) -> Void = { _ in }
    public var onEnded: (_ robotId: Int, _ reason: DeadManEnd, _ stopConfirmed: Bool) -> Void = { _, _, _ in }
    private var sessions: [Int: Session] = [:]
    private var counter = 0
    /// Stops on their way, so the session is not let go before they leave.
    private var stops: [Task<Void, Never>] = []

    public init(settings: DeadManSettings = DeadManSettings(), clock: @escaping () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }, poster: @escaping DeadManPoster) {
        self.settings = settings
        self.clock = clock
        self.poster = poster
    }

    public func isRunning(_ robotId: Int) -> Bool { sessions[robotId]?.ending == false }
    public var anyRunning: Bool { sessions.values.contains { !$0.ending } }
    public var stopping: Bool { sessions.values.contains { $0.ending } }

    public func start(_ robotId: Int, target: String, axis: String, velocity: Double) async throws {
        if isRunning(robotId) { return }
        counter += 1
        let session = Session(robotId, "dm-\(counter)-\(clock())")
        sessions[robotId] = session
        let params: [String: Any] = ["sessionId": session.id, "target": target, "axis": axis, "velocity": clampDeadManVelocity(velocity),
                                     "heartbeatMs": settings.heartbeatMs, "timeoutMs": settings.serverTimeoutMs]
        let poster = self.poster
        do {
            try await within(milliseconds: settings.serverTimeoutMs * 5) { try await poster(robotId, "jogStart", params) }
        } catch {
            if !session.ending {
                // the server may have received it: tell it to stop all the same
                end(robotId, .interrupted, report: false)
            }
            throw error
        }
        if session.ending { return }   // ended while the start was on the wire: its stop is already going out
        Task { @MainActor [weak self] in await self?.heartbeats(session) }
    }

    public func release(_ robotId: Int) { end(robotId, .released) }

    public func interrupt() {
        for session in sessions.values.filter({ !$0.ending }) { end(session.robotId, .interrupted) }
    }

    /// Waits for the stops on their way.
    public func waitStops() async {
        while let next = stops.first {
            await next.value
            if !stops.isEmpty { stops.removeFirst() }
        }
    }

    private func end(_ robotId: Int, _ reason: DeadManEnd, report: Bool = true) {
        guard let session = sessions[robotId], !session.ending else { return }
        session.ending = true
        stops.append(Task { @MainActor [weak self] in
            guard let self else { return }
            let confirmed = await self.sendStop(session)
            if self.sessions[robotId] === session { self.sessions[robotId] = nil }
            if report { self.onEnded(robotId, reason, confirmed) }
        })
    }

    private func sendStop(_ session: Session) async -> Bool {
        let poster = self.poster
        let id = session.id
        let robotId = session.robotId
        for attempt in 0..<settings.stopAttempts {
            do {
                try await within(milliseconds: settings.stopTimeoutMs) { try await poster(robotId, "jogStop", ["sessionId": id]) }
                return true
            } catch {
                // try again
            }
            if attempt < settings.stopAttempts - 1 { try? await Task.sleep(nanoseconds: UInt64(settings.stopRetryPauseMs) * 1_000_000) }
        }
        return false
    }

    private func heartbeats(_ session: Session) async {
        var watchdog = DeadManWatchdog(settings: settings, clock: clock)
        var sequence = 0
        let poster = self.poster
        while !session.ending {
            let startedAt = clock()
            sequence += 1
            let params: [String: Any] = ["sessionId": session.id, "sequence": sequence]
            let robotId = session.robotId
            var refused = false
            do {
                try await within(milliseconds: settings.serverTimeoutMs - settings.heartbeatMs) { try await poster(robotId, "jogHeartbeat", params) }
                watchdog.acked()
                onRoundTrip(clock() - startedAt)
            } catch let error as ApiError where (400...499).contains(error.status) && error.status != 408 && error.status != 429 {
                refused = true
            } catch {
                watchdog.missed()
            }
            if session.ending { return }
            let verdict = refused ? .serverRefused : (watchdog.verdict() ?? (linkAllows() ? nil : .badLink))
            if let verdict {
                end(session.robotId, verdict)
                return
            }
            let wait = max(1, settings.heartbeatMs - (clock() - startedAt))
            try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000)
        }
    }
}
