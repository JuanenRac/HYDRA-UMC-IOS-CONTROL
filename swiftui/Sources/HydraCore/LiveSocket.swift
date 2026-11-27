// HYDRA-UMC-IOS-CONTROL - the live link (`/ws`): the token travels as a subprotocol, a lost link is retried with growing pauses and a refused
// token (close 1008) is reported once and not retried. The same rules as the published app (SDK, hydra_websocket).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum LinkStatus: Equatable, Sendable { case connecting, connected, disconnected }

public enum SocketEvent: Sendable, Equatable {
    case opened
    case text(String)
    /// The connection ended; `code` is the close code when the server sent one.
    case closed(code: Int?)
}

@MainActor
public protocol LiveConnection: AnyObject {
    func close()
}

@MainActor
public protocol LiveSocketTransport {
    func open(url: String, protocols: [String], onEvent: @escaping @MainActor (SocketEvent) -> Void) -> LiveConnection
}

/// Runs `block` after some seconds; the returned closure cancels it.
public typealias Scheduler = @MainActor (_ seconds: Double, _ block: @escaping @MainActor () -> Void) -> () -> Void

public let standardScheduler: Scheduler = { seconds, block in
    let task = Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        if !Task.isCancelled { block() }
    }
    return { task.cancel() }
}

/// What the socket hands to its owner.
public enum LiveMessage {
    case settings([String: Any])
    /// A change of one robot (schema 2).
    case delta([String: Any])
    case claims([String: Any])
    case canOtaProgress([String: Any])
}

@MainActor
public final class LiveSocket {
    public static let closePolicyViolation = 1008
    public static let subprotocol = "hydra.bearer"
    public static let firstDelay = 3.0
    public static let maxDelay = 30.0

    public var onStatus: ((LinkStatus) -> Void)?
    public var onMessage: ((LiveMessage) -> Void)?
    /// The server refused the token: the socket stops, the owner renews the session and opens it again.
    public var onAuthRejected: (() -> Void)?

    private let transport: LiveSocketTransport
    private let schedule: Scheduler
    private let jitter: () -> Double
    private var connection: LiveConnection?
    private var cancelRetry: (() -> Void)?
    private var target: (url: String, token: String)?
    /// Callbacks of an older attempt are ignored.
    private var generation = 0
    private var failedAttempts = 0
    private var opened = false

    public init(transport: LiveSocketTransport, schedule: @escaping Scheduler = standardScheduler, jitter: @escaping () -> Double = { Double.random(in: 0..<0.5) }) {
        self.transport = transport
        self.schedule = schedule
        self.jitter = jitter
    }

    /// The address of the socket. The token is never part of it.
    public static func url(address: ServerAddress, tls: Bool) -> String {
        let base = address.baseUrl(tls: tls)
        let scheme = tls ? "wss" : "ws"
        return "\(scheme)\(base.dropFirst(tls ? 5 : 4))/ws?remoteApiVersion=2"
    }

    /// 3 s, doubled after every attempt that did not open, at most 30 s.
    public static func backoff(failedAttempts: Int) -> Double {
        let doublings = min(max(0, failedAttempts - 1), 10)
        return min(firstDelay * Double(1 << doublings), maxDelay)
    }

    public func connect(address: ServerAddress, tls: Bool, token: String) {
        disconnect()
        failedAttempts = 0
        target = (LiveSocket.url(address: address, tls: tls), token)
        open()
    }

    public func disconnect() {
        let was = target != nil
        generation += 1
        target = nil
        cancelRetry?()
        cancelRetry = nil
        connection?.close()
        connection = nil
        if was { onStatus?(.disconnected) }
    }

    private func open() {
        guard let target else { return }
        generation += 1
        let mine = generation
        opened = false
        // a token a subprotocol cannot carry was not issued by this server: it is not pasted anywhere else
        guard target.token.range(of: "^[A-Za-z0-9!#$%&'*+.^_`|~-]+$", options: .regularExpression) != nil else {
            reject()
            return
        }
        onStatus?(.connecting)
        connection = transport.open(url: target.url, protocols: [LiveSocket.subprotocol, target.token]) { [weak self] event in
            guard let self, mine == self.generation else { return }
            self.handle(event)
        }
    }

    private func reject() {
        disconnect()
        onAuthRejected?()
    }

    private func handle(_ event: SocketEvent) {
        switch event {
        case .opened:
            opened = true
            failedAttempts = 0
            onStatus?(.connected)
        case .text(let text):
            read(text)
        case .closed(let code):
            if code == LiveSocket.closePolicyViolation {
                reject()
                return
            }
            connection?.close()
            connection = nil
            generation += 1
            if !opened { failedAttempts += 1 }
            onStatus?(.disconnected)
            cancelRetry?()
            cancelRetry = schedule(LiveSocket.backoff(failedAttempts: failedAttempts) + jitter()) { [weak self] in self?.open() }
        }
    }

    private func read(_ text: String) {
        guard let message = HydraClient.object(Data(text.utf8)) else { return }
        if let error = message["error"] as? String, !error.isEmpty {
            // "Access denied ..." comes just before the 1008 close: one event, told once
            if error.lowercased().contains("denied") || error.lowercased().contains("token") { reject() }
            return
        }
        switch message["type"] as? String ?? "" {
        case "claims": onMessage?(.claims(message))
        case "canota_progress": onMessage?(.canOtaProgress(message))
        case "delta" where (message["schema"] as? Int) == 2 && message["robotId"] != nil: onMessage?(.delta(message))
        case "settings", "delta":
            if let payload = message["payload"] as? [String: Any] { onMessage?(.settings(payload)) }
        default: break
        }
    }
}
