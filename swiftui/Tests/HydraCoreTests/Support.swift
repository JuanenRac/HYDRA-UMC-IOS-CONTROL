// HYDRA-UMC-IOS-CONTROL - doubles of the phone and of the server for the tests. All data is invented.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation
@testable import HydraCore

/// A scripted server: each request is recorded and answered by `answer`.
final class FakeTransport: HttpTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HttpRequest] = []
    var answer: @Sendable (HttpRequest) async throws -> HttpResponse

    init(_ answer: @escaping @Sendable (HttpRequest) async throws -> HttpResponse = { _ in throw TransportError.unreachable }) {
        self.answer = answer
    }

    var requests: [HttpRequest] { lock.lock(); defer { lock.unlock() }; return recorded }

    private func record(_ request: HttpRequest) { lock.lock(); recorded.append(request); lock.unlock() }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        record(request)
        return try await answer(request)
    }

    func paths() -> [String] { requests.map { URL(string: $0.url)?.path ?? "" } }
}

func reply(_ status: Int, _ json: String = "{}", headers: [String: String] = [:]) -> HttpResponse {
    HttpResponse(status: status, headers: headers, body: Data(json.utf8))
}

let infoJson = #"{"remoteApiVersion":2,"hostname":"demo-cell","robotCount":2}"#
let loginJson = #"{"success":true,"token":"t1","refreshToken":"r1"}"#
let settingsJson = #"{"controllers":[{"id":"c1","robots":[{"id":1,"name":"A1"},{"id":2,"name":"A2"}]}]}"#
let stoppedJson = #"{"success":true,"stoppedCount":2,"failedCount":0,"persisted":true,"robots":[{"robotId":1,"name":"A1","stopped":true},{"robotId":2,"name":"A2","stopped":true}]}"#

/// A server that works: https only.
@Sendable func healthy(_ request: HttpRequest) async throws -> HttpResponse {
    guard request.url.hasPrefix("https://") else { throw TransportError.unreachable }
    switch URL(string: request.url)?.path {
    case "/api/hydra-info": return reply(200, infoJson)
    case "/api/login": return reply(200, loginJson)
    case "/api/settings": return reply(200, settingsJson)
    case "/api/stop-all": return reply(200, stoppedJson)
    default: return reply(200)
    }
}

final class MemorySecrets: SecretStore {
    var values: [String: String] = [:]
    var failWrites = false
    var failDeletes = false
    struct Failure: Error {}

    func write(_ key: String, _ value: String) throws { if failWrites { throw Failure() }; values[key] = value }
    func read(_ key: String) throws -> String? { values[key] }
    func delete(_ key: String) throws { if failDeletes { throw Failure() }; values[key] = nil }
    func deleteAll() throws { if failDeletes { throw Failure() }; values = [:] }
    /// The values of one kind of key, whatever the server.
    func stored(_ kind: String) -> [String] { values.filter { $0.key.hasPrefix(kind + "|") }.map(\.value) }
}

final class MemoryPrefs: PrefsStore {
    var values: [String: String] = [:]
    func string(_ key: String) -> String? { values[key] }
    func set(_ value: String?, _ key: String) { values[key] = value }
}

final class FakeAuth: DeviceAuth {
    var isAvailable = true
    var succeeds = true
    var asked = 0
    func authenticate(reason: String) async -> Bool { asked += 1; return succeeds }
}

@MainActor
struct Rig {
    let transport: FakeTransport
    let secrets: MemorySecrets
    let prefs: MemoryPrefs
    let auth: FakeAuth
    let controller: HydraController

    init(_ answer: @escaping @Sendable (HttpRequest) async throws -> HttpResponse = healthy, secrets: MemorySecrets = MemorySecrets(), prefs: MemoryPrefs = MemoryPrefs(), auth: FakeAuth = FakeAuth()) {
        let transport = FakeTransport(answer)
        self.transport = transport
        self.secrets = secrets
        self.prefs = prefs
        self.auth = auth
        controller = HydraController(transport: transport, discoveryTransport: transport, secrets: secrets, prefs: prefs, auth: auth, appVersion: "0.0.1")
    }

    func signIn() async {
        await controller.start()
        await controller.login(host: "192.168.1.50", port: "3000", username: "operator", password: "sample-pass", code: "")
    }
}
