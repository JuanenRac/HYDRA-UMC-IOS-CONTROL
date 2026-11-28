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
final class FakeConnection: LiveConnection {
    let url: String
    let protocols: [String]
    let onEvent: @MainActor (SocketEvent) -> Void
    var closed = false

    init(url: String, protocols: [String], onEvent: @escaping @MainActor (SocketEvent) -> Void) {
        self.url = url
        self.protocols = protocols
        self.onEvent = onEvent
    }

    func close() { closed = true }
    func say(_ text: String) { onEvent(.text(text)) }
    func end(_ code: Int? = nil) { onEvent(.closed(code: code)) }
}

/// Records every socket; with `opens` it is open as soon as it is asked for.
@MainActor
final class FakeSockets: LiveSocketTransport {
    var opens: Bool
    var made: [FakeConnection] = []
    var last: FakeConnection { made[made.count - 1] }

    init(opens: Bool = true) { self.opens = opens }

    func open(url: String, protocols: [String], onEvent: @escaping @MainActor (SocketEvent) -> Void) -> LiveConnection {
        let connection = FakeConnection(url: url, protocols: protocols, onEvent: onEvent)
        made.append(connection)
        if opens { onEvent(.opened) }
        return connection
    }
}

/// Timers a test fires by hand.
@MainActor
final class ManualTimers {
    final class Entry {
        let seconds: Double
        let block: @MainActor () -> Void
        var done = false

        init(_ seconds: Double, _ block: @escaping @MainActor () -> Void) {
            self.seconds = seconds
            self.block = block
        }
    }

    private(set) var entries: [Entry] = []
    var waiting: [Double] { entries.filter { !$0.done }.map(\.seconds) }

    func add(_ seconds: Double, _ block: @escaping @MainActor () -> Void) -> () -> Void {
        let entry = Entry(seconds, block)
        entries.append(entry)
        return { entry.done = true }
    }

    /// Fires what is waiting and matches.
    func fire(_ matches: (Double) -> Bool) {
        for entry in entries where !entry.done && matches(entry.seconds) {
            entry.done = true
            entry.block()
        }
    }
}

final class ManualClock {
    var time = Date(timeIntervalSince1970: 1_000_000)
}

final class MemoryCache: CacheStore {
    var data: Data?
    var text: String { data.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    func read() -> Data? { data }
    func write(_ data: Data?) { self.data = data }
}

/// Waits until `done` or two seconds.
@MainActor
func until(_ done: () -> Bool) async {
    for _ in 0..<400 where !done() {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor
struct Rig {
    let transport: FakeTransport
    let secrets: MemorySecrets
    let prefs: MemoryPrefs
    let auth: FakeAuth
    let sockets: FakeSockets
    let cache: MemoryCache
    let timers: ManualTimers
    let clock: ManualClock
    let controller: HydraController

    init(_ answer: @escaping @Sendable (HttpRequest) async throws -> HttpResponse = healthy, secrets: MemorySecrets = MemorySecrets(), prefs: MemoryPrefs = MemoryPrefs(), auth: FakeAuth = FakeAuth(),
         cache: MemoryCache = MemoryCache(), opens: Bool = true, push: PushPlatform? = nil) {
        let transport = FakeTransport(answer)
        self.transport = transport
        self.secrets = secrets
        self.prefs = prefs
        self.auth = auth
        let sockets = FakeSockets(opens: opens)
        let timers = ManualTimers()
        let clock = ManualClock()
        self.sockets = sockets
        self.cache = cache
        self.timers = timers
        self.clock = clock
        controller = HydraController(transport: transport, discoveryTransport: transport, secrets: secrets, prefs: prefs, auth: auth, appVersion: "0.0.1",
                                     sockets: sockets, cache: cache, schedule: { timers.add($0, $1) }, now: { clock.time }, push: push ?? NoPush())
    }

    func signIn() async {
        await controller.start()
        await controller.login(host: "192.168.1.50", port: "3000", username: "operator", password: "sample-pass", code: "")
    }
}
