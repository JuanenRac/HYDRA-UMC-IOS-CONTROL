// HYDRA-UMC-IOS-CONTROL - the calls to HYDRA-UMC-SERVER: scheme, sign-in, session renewal, global stop. The same contract as the published app.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public struct HttpRequest: Sendable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(method: String, url: String, headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HttpResponse: Sendable {
    public var status: Int
    /// Header names in lowercase.
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

/// What failed below the HTTP answer.
public enum TransportError: Error, Equatable {
    case unreachable
    case timeout
    /// The TLS handshake failed or the certificate was refused.
    case tls
}

public protocol HttpTransport: Sendable {
    func send(_ request: HttpRequest) async throws -> HttpResponse
}

/// An answer of the server that is not a success.
public struct ApiError: Error, Equatable {
    public var status: Int
    public var code: String?
    public var message: String?

    public init(status: Int, code: String? = nil, message: String? = nil) {
        self.status = status
        self.code = code
        self.message = message
    }

    public var isSessionProblem: Bool { status == 401 || (status == 403 && (code == "TOKEN_EXPIRED" || code == "TOKEN_INVALID")) }
    public var isRateLimited: Bool { status == 429 }
    public var isNotFound: Bool { status == 404 }
}

/// The account has a second factor: a code is needed, was wrong, or the person has to wait.
public struct SecondFactorRequired: Error, Equatable {
    public var wrongCode: Bool
    public var waitSeconds: Int?
}

public enum TotpCode {
    public static let defaultWaitSeconds = 60

    /// Six digits written with spaces or dashes become six digits; anything else is a recovery code, in lowercase.
    public static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0 != "-" && !$0.isWhitespace }
        return digits.count == 6 && digits.allSatisfy { "0123456789".contains($0) } ? digits : trimmed.lowercased()
    }
}

public struct LoginGrant: Equatable, Sendable {
    public var token: String
    public var refreshToken: String?
}

@MainActor
public final class HydraClient {
    public let address: ServerAddress
    private let transport: HttpTransport
    private let tlsSettings: () -> TlsSettings
    private let clientHeader: String
    public let controllerId: String

    public private(set) var usesTls: Bool
    /// Set once the server answered over TLS: from then on it is never asked in the clear.
    private var tlsSeen: Bool

    public var authToken: String?
    /// Renews the session and returns the new token, or nil when it cannot be renewed.
    public var tokenRenewer: (() async -> String?)?

    public init(address: ServerAddress, transport: HttpTransport, tlsSettings: @escaping () -> TlsSettings, appVersion: String, controllerId: String, useTls: Bool = false) {
        self.address = address
        self.transport = transport
        self.tlsSettings = tlsSettings
        self.clientHeader = HydraClient.clientHeaderValue(appVersion)
        self.controllerId = controllerId
        self.tlsSeen = useTls
        self.usesTls = useTls || !TlsPolicy.isLoopback(address.host)
    }

    public nonisolated static func clientHeaderValue(_ version: String) -> String {
        HostRules.matches(version, "^[0-9A-Za-z._-]{1,24}$") ? "ios/\(version)" : "ios"
    }

    public var baseUrl: String { address.baseUrl(tls: usesTls) }

    private var clientHeaders: [String: String] { ["X-Hydra-Client": clientHeader] }
    private var authHeaders: [String: String] { authToken.map { ["Authorization": "Bearer \($0)"] } ?? [:] }

    // MARK: - Scheme

    /// `GET /api/hydra-info` on the current scheme, then on the other one when the rules allow it. nil when nothing answered.
    public func hydraInfo() async -> (info: [String: Any]?, failure: TransportError?) {
        let direct = await probe(tls: usesTls)
        if let info = direct.info {
            if usesTls { tlsSeen = true }
            return (info, nil)
        }
        if mayTryOtherScheme {
            let other = await probe(tls: !usesTls)
            if let info = other.info {
                usesTls.toggle()
                if usesTls { tlsSeen = true }
                return (info, nil)
            }
        }
        return (nil, direct.failure)
    }

    /// Plain HTTP is only a second try: allowed by the person, and never for a server that already spoke TLS.
    private var mayTryOtherScheme: Bool {
        if !usesTls { return true }
        if tlsSeen { return false }
        return tlsSettings().plainAllowed(forHost: address.host)
    }

    private func probe(tls: Bool) async -> (info: [String: Any]?, failure: TransportError?) {
        let request = HttpRequest(method: "GET", url: address.baseUrl(tls: tls) + "/api/hydra-info", headers: clientHeaders, timeout: 3)
        do {
            let response = try await send(request)
            guard response.status == 200, let json = HydraClient.object(response.body), json["remoteApiVersion"] != nil else { return (nil, nil) }
            return (json, nil)
        } catch {
            return (nil, error as? TransportError)
        }
    }

    // MARK: - Sending

    /// One request with its total time limit.
    private func send(_ request: HttpRequest) async throws -> HttpResponse {
        let transport = self.transport
        return try await withThrowingTaskGroup(of: HttpResponse.self) { group in
            group.addTask { try await transport.send(request) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(request.timeout * 1_000_000_000))
                throw TransportError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TransportError.unreachable }
            return first
        }
    }

    /// A request with the session: an expired one is renewed once and the request repeated once.
    private func authed(method: String, path: String, headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval) async throws -> [String: Any] {
        func attempt() async throws -> [String: Any] {
            var all = clientHeaders.merging(headers) { _, new in new }.merging(authHeaders) { _, new in new }
            if body != nil { all["Content-Type"] = "application/json" }
            return try HydraClient.expectObject(await send(HttpRequest(method: method, url: baseUrl + path, headers: all, body: body, timeout: timeout)))
        }
        do {
            return try await attempt()
        } catch let error as ApiError where error.isSessionProblem {
            guard let renewer = tokenRenewer, let token = await renewer() else { throw error }
            authToken = token
            return try await attempt()
        }
    }

    nonisolated static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    nonisolated static func json(_ value: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    nonisolated static func expectObject(_ response: HttpResponse) throws -> [String: Any] {
        let body = object(response.body)
        guard (200..<300).contains(response.status) else {
            throw ApiError(status: response.status, code: body?["code"] as? String, message: body?["error"] as? String)
        }
        guard let body else { throw ApiError(status: response.status, code: "not-json") }
        return body
    }

    // MARK: - Sign-in

    public func login(username: String, password: String, totp: String?) async throws -> LoginGrant {
        _ = await hydraInfo()
        var payload: [String: Any] = ["username": username, "password": password]
        let code = totp.map(TotpCode.normalize) ?? ""
        if !code.isEmpty { payload["totp"] = code }
        var headers = clientHeaders
        headers["Content-Type"] = "application/json"
        let response = try await send(HttpRequest(method: "POST", url: baseUrl + "/api/login", headers: headers, body: HydraClient.json(payload), timeout: 15))
        if response.status == 401 || response.status == 429, HydraClient.object(response.body)?["totpRequired"] as? Bool == true {
            let wait = response.status == 429 ? (Int(response.headers["retry-after"]?.trimmingCharacters(in: .whitespaces) ?? "") ?? TotpCode.defaultWaitSeconds) : nil
            throw SecondFactorRequired(wrongCode: !code.isEmpty && response.status == 401, waitSeconds: wait)
        }
        let body = try HydraClient.expectObject(response)
        guard body["success"] as? Bool == true, let token = body["token"] as? String else { throw ApiError(status: 401, code: "refused") }
        return LoginGrant(token: token, refreshToken: body["refreshToken"] as? String)
    }

    /// Exchanges the refresh token for a new session; throws when the server refuses.
    public func refresh(_ refreshToken: String) async throws -> LoginGrant {
        var headers = clientHeaders
        headers["Content-Type"] = "application/json"
        let response = try await send(HttpRequest(method: "POST", url: baseUrl + "/api/refresh", headers: headers, body: HydraClient.json(["refreshToken": refreshToken]), timeout: 5))
        let body = try HydraClient.expectObject(response)
        guard body["success"] as? Bool == true, let token = body["token"] as? String else { throw ApiError(status: 401, code: "refused") }
        return LoginGrant(token: token, refreshToken: body["refreshToken"] as? String)
    }

    /// Revokes the refresh token; best effort.
    public func logoutRemote(_ refreshToken: String) async {
        var headers = clientHeaders
        headers["Content-Type"] = "application/json"
        _ = try? await send(HttpRequest(method: "POST", url: baseUrl + "/api/logout", headers: headers, body: HydraClient.json(["refreshToken": refreshToken]), timeout: 5))
    }

    // MARK: - State and commands

    public func settings() async throws -> [String: Any] {
        if !tlsSeen { _ = await hydraInfo() }   // a restored session never ran the sign-in
        return try await authed(method: "GET", path: "/api/settings", timeout: 5)
    }

    public func metrics() async throws -> [String: Any] {
        try await authed(method: "GET", path: "/api/system/metrics", timeout: 4)
    }

    public func stopAll() async throws -> [String: Any] {
        try await authed(method: "POST", path: "/api/stop-all", timeout: 2)
    }

    /// The per-robot stop, used when the global one is not available.
    public func stopRobot(_ robotId: Int, sequence: Int64) async throws {
        _ = try await authed(
            method: "POST", path: "/api/robot/\(robotId)/command",
            headers: ["X-Controller-Id": controllerId],
            body: HydraClient.json(["command": "stop", "seq": sequence, "controllerId": controllerId]),
            timeout: 2)
    }
}
