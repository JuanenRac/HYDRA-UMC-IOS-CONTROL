// HYDRA-UMC-IOS-CONTROL - the live link of the phone (a WebSocket with the same certificate rules as the requests) and the file of the saved state.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation
import HydraCore

/// One socket with its own session. A ping goes every 20 s; one that gets no answer before the next closes the link, so a dead
/// Wi-Fi is noticed. No redirect is followed: the token never goes anywhere else.
@MainActor
private final class PhoneSocket: LiveConnection {
    private final class Delegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
        let trust: TrustDelegate
        var opened: (() -> Void)?
        var ended: ((Int?) -> Void)?

        init(trust: TrustDelegate) { self.trust = trust }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            trust.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol chosen: String?) { opened?() }

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
            ended?(closeCode.rawValue)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let code = (task as? URLSessionWebSocketTask)?.closeCode.rawValue ?? 0
            ended?(code == 0 ? nil : code)
        }
    }

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var timer: Task<Void, Never>?
    private var onEvent: (@MainActor (SocketEvent) -> Void)?
    private var isOpen = false
    private var waitingPong = false

    init(url: URL, protocols: [String], trust: TrustDelegate, onEvent: @escaping @MainActor (SocketEvent) -> Void) {
        self.onEvent = onEvent
        let delegate = Delegate(trust: trust)
        delegate.opened = { [weak self] in Task { @MainActor in self?.didOpen() } }
        delegate.ended = { [weak self] code in Task { @MainActor in self?.end(code) } }
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        self.session = session
        self.task = task
        task.resume()
        receive()
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if Task.isCancelled { return }
            if self?.isOpen == false { self?.end(nil) }
            while !Task.isCancelled {
                self?.ping()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    private func didOpen() {
        guard onEvent != nil, !isOpen else { return }
        isOpen = true
        onEvent?(.opened)
    }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.onEvent != nil else { return }
                switch result {
                case .success(let message):
                    // a binary frame is not part of this protocol
                    if case .string(let text) = message { self.onEvent?(.text(text)) }
                    self.receive()
                case .failure:
                    let code = self.task?.closeCode.rawValue ?? 0
                    self.end(code == 0 ? nil : code)
                }
            }
        }
    }

    private func ping() {
        guard isOpen, onEvent != nil else { return }
        if waitingPong {
            end(nil)
            return
        }
        waitingPong = true
        task?.sendPing { [weak self] error in
            Task { @MainActor in
                if error == nil { self?.waitingPong = false } else { self?.end(nil) }
            }
        }
    }

    /// Told once; then the socket is let go.
    private func end(_ code: Int?) {
        guard let tell = onEvent else { return }
        close()
        tell(.closed(code: code))
    }

    func close() {
        onEvent = nil
        timer?.cancel()
        timer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.finishTasksAndInvalidate()
        session = nil
    }
}

@MainActor
final class PhoneSockets: LiveSocketTransport {
    private let trust: TrustDelegate

    init(trust: TrustDelegate) { self.trust = trust }

    func open(url: String, protocols: [String], onEvent: @escaping @MainActor (SocketEvent) -> Void) -> LiveConnection {
        guard let parsed = URL(string: url) else {
            Task { @MainActor in onEvent(.closed(code: nil)) }
            return DeadSocket()
        }
        return PhoneSocket(url: parsed, protocols: protocols, trust: trust, onEvent: onEvent)
    }
}

@MainActor
private final class DeadSocket: LiveConnection {
    func close() {}
}

/// The copy of the last state in a file of the app: protected while the phone has not been unlocked, and left out of backups.
final class FileCacheStore: CacheStore {
    private let url: URL?

    init() {
        let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        url = folder?.appendingPathComponent("hydra_last_state.json")
    }

    func read() -> Data? { url.flatMap { try? Data(contentsOf: $0) } }

    func write(_ data: Data?) {
        guard var url else { return }
        guard let data else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
