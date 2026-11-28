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
    /// The revision the server is at, when a refusal says it.
    public var revision: String?

    public init(status: Int, code: String? = nil, message: String? = nil, revision: String? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.revision = revision
    }

    public var isRevisionMismatch: Bool { status == 412 || code == "revision-mismatch" }
    public var isJogNotArmed: Bool { status == 403 && code == "jog-not-armed" }
    /// An older server that does not know a command.
    public var isUnknownCommand: Bool { status == 400 && code == nil && (message ?? "").lowercased().contains("unknown command") }

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
    /// While true, nothing is written to the server except what stops.
    public var listenOnly: () -> Bool = { false }
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
    /// For what is not read through this client (the camera stream): who asks and the session.
    public var mediaHeaders: [String: String] { clientHeaders.merging(authHeaders) { _, new in new } }

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
        if listenOnly(), !ListenOnly.allows(method: request.method, path: URL(string: request.url)?.path ?? "", body: request.body) {
            throw ApiError(status: 423, code: "listen-only")
        }
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
            throw ApiError(status: response.status, code: body?["code"] as? String, message: body?["error"] as? String, revision: revisionOf(body))
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

    // MARK: - Control

    private var controllerHeaders: [String: String] { ["X-Controller-Id": controllerId] }

    /// A write of control: the controller id in the header and in the body, and the revision when one is given.
    private func control(_ path: String, _ body: [String: Any], ifMatch: String?, timeout: TimeInterval) async throws -> [String: Any] {
        var headers = controllerHeaders
        if let ifMatch { headers["If-Match"] = ifMatch }
        var full = body
        full["controllerId"] = controllerId
        return try await authed(method: "POST", path: path, headers: headers, body: HydraClient.json(full), timeout: timeout)
    }

    public func robotCommand(_ robotId: Int, _ payload: [String: Any], ifMatch: String?, urgent: Bool) async throws -> [String: Any] {
        try await control("/api/robot/\(robotId)/command", payload, ifMatch: ifMatch, timeout: urgent ? 2 : 5)
    }

    public func claims() async throws -> [ClaimInfo] {
        let json = try await authed(method: "GET", path: "/api/claims", headers: controllerHeaders, timeout: 5)
        return ClaimInfo.list(json)
    }

    public func claim(_ robotId: Int, force: Bool = false, ifMatch: String?) async throws -> [String: Any] {
        try await control("/api/robot/\(robotId)/claim", force ? ["force": true] : [:], ifMatch: ifMatch, timeout: 5)
    }

    public func release(_ robotId: Int, ifMatch: String?) async throws -> [String: Any] {
        try await control("/api/robot/\(robotId)/release", [:], ifMatch: ifMatch, timeout: 5)
    }

    public func jogArm(_ robotId: Int, armed: Bool) async throws -> [String: Any] {
        try await control("/api/robot/\(robotId)/jog-arm", ["armed": armed], ifMatch: nil, timeout: 5)
    }

    /// nil on a server without the route.
    public func safetyLimits(_ robotId: Int) async throws -> RobotSafety? {
        do {
            return RobotSafety(json: try await authed(method: "GET", path: "/api/safety-limits?robotId=\(robotId)", timeout: 5))
        } catch let error as ApiError where error.isNotFound {
            return nil
        }
    }

    /// One robot with the revision to use next; nil when the server has none.
    public func robot(_ robotId: Int) async throws -> (robot: [String: Any], revision: String?)? {
        do {
            let json = try await authed(method: "GET", path: "/api/robot/\(robotId)", timeout: 5)
            guard let robot = json["robot"] as? [String: Any] else { return nil }
            return (robot, revisionOf(json))
        } catch let error as ApiError where error.isNotFound {
            return nil
        }
    }

    /// A file of a work folder of the server, as it is.
    public func workBody(folder: String, file: String) async throws -> Data {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#%")
        let path = "/" + ("\(folder)/\(file)".addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        func attempt() async throws -> Data {
            let headers = clientHeaders.merging(authHeaders) { _, new in new }
            let response = try await send(HttpRequest(method: "GET", url: baseUrl + path, headers: headers, timeout: 10))
            guard (200..<300).contains(response.status) else {
                let body = HydraClient.object(response.body)
                throw ApiError(status: response.status, code: body?["code"] as? String, message: body?["error"] as? String)
            }
            return response.body
        }
        do {
            return try await attempt()
        } catch let error as ApiError where error.isSessionProblem {
            guard let renewer = tokenRenewer, let token = await renewer() else { throw error }
            authToken = token
            return try await attempt()
        }
    }

    /// The round trip of one small request, in milliseconds.
    public func ping() async throws -> Int {
        let started = Date()
        let response = try await send(HttpRequest(method: "GET", url: baseUrl + "/api/hydra-info", headers: clientHeaders, timeout: Contract.linkProbeTimeout))
        guard response.status == 200 else { throw ApiError(status: response.status) }
        return Int(Date().timeIntervalSince(started) * 1000)
    }

    // MARK: - The record of the server and push

    public func faults(limit: Int) async throws -> [String: Any] {
        try await authed(method: "GET", path: "/api/faults?limit=\(min(200, max(1, limit)))", timeout: 5)
    }

    public func nodeHealth(slot: Int) async throws -> [String: Any] {
        try await authed(method: "GET", path: "/api/ecosystem/node-health?slot=\(slot)", timeout: 5)
    }

    public func registerPush(_ token: String, locale: String) async throws {
        _ = try await authed(method: "POST", path: "/api/push/devices", body: HydraClient.json(["token": token, "platform": "ios", "locale": locale]), timeout: 10)
    }

    /// With the session given: the one of a sign-out, which the client no longer holds when this leaves.
    public func removePush(_ token: String, bearer: String) async throws {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~:")
        var headers = clientHeaders
        headers["Authorization"] = "Bearer \(bearer)"
        let path = "/api/push/devices/" + (token.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        _ = try HydraClient.expectObject(await send(HttpRequest(method: "DELETE", url: baseUrl + path, headers: headers, timeout: 5)))
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
