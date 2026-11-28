// HYDRA-UMC-IOS-CONTROL - what the app does for the Cameras and Alerts pages, the 3D viewer and the push notifications of a server.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum PushTokenAnswer: Equatable, Sendable {
    case token(String)
    /// The person did not allow notifications.
    case denied
    case none
}

/// The push service of the phone. It only receives: no notification carries an action.
@MainActor
public protocol PushPlatform: AnyObject {
    /// False for a build without the configuration of the push service.
    var available: Bool { get }
    /// Asks for permission once and gives the token of this phone.
    func token() async -> PushTokenAnswer
    /// Drops the token: no server reaches the phone until it registers again.
    func forget()
}

@MainActor
public final class NoPush: PushPlatform {
    public nonisolated init() {}
    public var available: Bool { false }
    public func token() async -> PushTokenAnswer { .none }
    public func forget() {}
}

public enum PushState: Equatable, Sendable {
    case off, registering, registered, denied, serverOff, listenOnly, failed
}

extension PrefKey {
    static let push = "hydra_push"
    /// The token each server was told, by server key.
    static let pushTokens = "hydra_push_tokens"
    static let notices = "hydra_notices"
}

public extension HydraController {
    // MARK: - Notices

    var unseenNotices: Int { Notices.unseen(notices) }

    /// One look at the plant; the app calls it about once a second while it is on screen.
    func noticesTick() {
        guard screen == .main, !paused else { return }
        let stop: PlantStop = stopsInFlight > 0 ? .sending : stopUnconfirmed ? .notConfirmed : stopResult != nil ? .done : .none
        let plant = robots.map { PlantRobot(id: $0.id, name: $0.name, online: $0.online, enabled: $0.enabled, playing: $0.isMoving) }
        for event in alertRules.observe(connected: link == .connected, robots: plant, stop: stop, at: now()) {
            addNotice(event.kind, event.robotName)
        }
    }

    func markNoticesSeen() {
        notices = notices.map { var seen = $0; seen.seen = true; return seen }
    }

    /// A push message of a server. It is only listed: nothing of its content is ever read as a command.
    /// With `once` the same text is not listed twice (a message shown and then tapped).
    func serverMessage(title: String, body: String, once: Bool = false) {
        let text = [title, body].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " - ")
        guard !text.isEmpty else { return }
        if once && notices.contains(where: { $0.kind == .serverMessage && $0.detail == String(text.prefix(Notices.detailMax)) }) { return }
        addNotice(.serverMessage, text)
    }

    internal func addNotice(_ kind: NoticeKind, _ detail: String) {
        notices = Notices.add(notices, Notice(kind: kind, detail: detail, at: now()))
    }

    /// A job that ran to its end: the robot stopped playing and says it finished (a STOP does not set that).
    internal func noticeFinishedJobs(before: [RobotInfo], after: [RobotInfo]) {
        for robot in after where robot.isFinished && !robot.isPlaying {
            if before.first(where: { $0.id == robot.id })?.isPlaying == true { addNotice(.jobDone, robot.name) }
        }
    }

    // MARK: - The record of the server

    /// Reads the faults and the board health, only when the person asks.
    func readServerRecord() async {
        guard screen == .main, !readingServer, let client else { return }
        readingServer = true
        defer { readingServer = false }
        let asked = client.address.key
        var result = ServerReading(server: asked)
        var sessionEnded = false
        do {
            if let record = FaultRecord.parse(try await client.faults(limit: FaultRecord.limit)) {
                result.faults = record
            } else {
                result.faultsProblem = .unavailable
            }
        } catch {
            result.faultsProblem = ReadingProblem.of(error)
            sessionEnded = result.faultsProblem == .session
        }
        for slot in BoardHealth.slots where !sessionEnded && client === self.client {
            do {
                guard let board = BoardHealth(json: try await client.nodeHealth(slot: slot)) else {
                    result.boardsProblem = .unavailable
                    break
                }
                result.boards.append(board)
                // a controller that does not answer one slot answers none: the other seven are not asked
                if !board.online { break }
            } catch {
                result.boardsProblem = ReadingProblem.of(error)
                sessionEnded = result.boardsProblem == .session
                break
            }
        }
        guard client === self.client else { return }
        serverReading = result
        if sessionEnded { self.sessionEnded() }
    }

    // MARK: - Cameras and 3D

    /// The stream of the camera of a robot, with the session in the headers (never in the address).
    func cameraRequest(robotId: Int) -> CameraRequest? {
        guard screen == .main, let client, client.authToken != nil else { return nil }
        return CameraRequest(url: "\(client.baseUrl)/api/camera/\(cell.cameraId(forRobot: robotId))/stream", headers: client.mediaHeaders)
    }

    /// The camera refused the session: renew it once; the next attempt carries the new one.
    func cameraRefused() async {
        guard screen == .main, let client, budget.tryAcquire(now: now()) else { return }
        _ = await renew(client)
    }

    func viewerUrl(robotId: Int) -> String? {
        guard screen == .main, let client else { return nil }
        return ViewerUrl.build(base: client.baseUrl, robotId: robotId, token: client.authToken)
    }

    // MARK: - Push

    var pushAvailable: Bool { push.available }

    private var pushTokens: [String: String] {
        get { prefs.codable([String: String].self, PrefKey.pushTokens) ?? [:] }
        set { prefs.setCodable(newValue, PrefKey.pushTokens) }
    }

    /// The switch of the person. Off tells the server in use and drops the token for every server.
    func setPush(_ on: Bool) async {
        pushEnabled = on && push.available
        prefs.set(pushEnabled, PrefKey.push)
        if pushEnabled {
            await syncPush()
            return
        }
        pushState = .off
        guard !pushTokens.isEmpty else { return }
        let current = screen == .main ? client : nil
        let token = current.flatMap { pushTokens[$0.address.key] }
        let bearer = current?.authToken
        pushTokens = [:]
        if let current, let token, let bearer { try? await current.removePush(token, bearer: bearer) }
        push.forget()
    }

    /// Tells the server of the signed-in session, when the switch is on.
    func syncPush() async {
        guard pushEnabled, push.available, screen == .main, let client else { return }
        pushState = .registering
        let answer = await push.token()
        guard client === self.client, pushEnabled else { return }
        switch answer {
        case .denied: pushState = .denied
        case .none: pushState = .failed
        case .token(let token):
            do {
                try await client.registerPush(token, locale: Translator.resolve(chosen: chosenLanguage, preferred: Locale.preferredLanguages))
                let bearer = client.authToken
                // switched off or signed out while it was on its way: taken back
                guard pushEnabled, client === self.client else {
                    if let bearer { try? await client.removePush(token, bearer: bearer) }
                    return
                }
                pushTokens[client.address.key] = token
                pushState = .registered
            } catch let error as ApiError {
                pushState = error.status == 404 ? .serverOff : error.status == 423 ? .listenOnly : .failed
            } catch {
                pushState = .failed
            }
        }
    }

    /// The session of a server ends or the server is forgotten: its registration is taken back, told to it when there still is a
    /// session. When it cannot be told, the token is dropped so it cannot go on sending.
    internal func forgetPush(_ key: String, client leaving: HydraClient?) {
        var tokens = pushTokens
        guard let token = tokens.removeValue(forKey: key) else { return }
        pushTokens = tokens
        pushState = .off
        let teller = leaving?.address.key == key ? leaving : nil
        let bearer = teller?.authToken
        Task { @MainActor in
            var told = false
            if let teller, let bearer { told = (try? await teller.removePush(token, bearer: bearer)) != nil }
            if !told || self.pushTokens.isEmpty {
                self.pushTokens = [:]
                self.push.forget()
            }
        }
    }
}
