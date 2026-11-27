// HYDRA-UMC-IOS-CONTROL - a pretend server and phone for the interface tests and the screenshots. Compiled only in debug builds; no release build can start it.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
#if DEBUG
import Foundation
import HydraCore

/// Launch arguments: `-hydraDemo main|login|welcome`, `-hydraDemoStopFails` and `-hydraDemoOffline`.
enum Demo {
    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-hydraDemo"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var stopFails: Bool { ProcessInfo.processInfo.arguments.contains("-hydraDemoStopFails") }
    /// The server signs in and then stops answering: the app shows the saved state.
    static var offline: Bool { ProcessInfo.processInfo.arguments.contains("-hydraDemoOffline") }

    static let settings = #"{"controllers":[{"id":"c1","name":"Cell 1","robots":[{"id":1,"name":"Robot A1","role":"Pick","model":"Parol6","tool":"Gripper","online":true,"visionEnabled":true,"pos":{"x":212.5,"y":-40,"z":318.2},"playbackState":{"speed":80,"acceleration":60}},{"id":2,"name":"Robot A2","role":"Weld","model":"UR5e","tool":"Torch","online":true,"hasXYTable":true,"pos":{"x":0,"y":150,"z":200},"xyTable":{"pos":{"x":12,"y":30}}}]}]}"#
}

/// With `-hydraDemoStopFails` the first STOP and its repeat get no answer; later ones are answered.
final class DemoTransport: HttpTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var failures = Demo.stopFails ? 2 : 0

    private func failsThisStop() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if failures == 0 { return false }
        failures -= 1
        return true
    }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        let json: String
        switch URL(string: request.url)?.path {
        case "/api/hydra-info": json = #"{"remoteApiVersion":2,"hostname":"Demo cell","robotCount":2}"#
        case "/api/settings":
            if Demo.offline { throw TransportError.unreachable }
            json = Demo.settings
        case "/api/system/metrics": json = #"{"cpu_load":12,"memory_usage":41,"temp":47.5,"uptime":93784}"#
        case "/api/stop-all":
            if failsThisStop() { throw TransportError.unreachable }
            json = #"{"success":true,"stoppedCount":2,"failedCount":0,"persisted":true,"robots":[{"robotId":1,"name":"Robot A1","stopped":true},{"robotId":2,"name":"Robot A2","stopped":true}]}"#
        case "/api/login": json = #"{"success":true,"token":"demo","refreshToken":"demo"}"#
        default: json = "{}"
        }
        return HttpResponse(status: 200, body: Data(json.utf8))
    }
}

@MainActor
private final class DemoConnection: LiveConnection {
    var closed = false
    func close() { closed = true }
}

@MainActor
final class DemoSockets: LiveSocketTransport {
    func open(url: String, protocols: [String], onEvent: @escaping @MainActor (SocketEvent) -> Void) -> LiveConnection {
        let connection = DemoConnection()
        Task { @MainActor in
            if connection.closed { return }
            if Demo.offline {
                onEvent(.closed(code: nil))
                return
            }
            onEvent(.opened)
            onEvent(.text(#"{"type":"settings","payload":"# + Demo.settings + "}"))
        }
        return connection
    }
}

/// In memory. With `-hydraDemoOffline` it starts with a copy saved before, as a phone that was used would.
final class DemoCache: CacheStore {
    private var data: Data?

    init() {
        guard Demo.offline else { return }
        data = Data((#"{"scope":"demo@192.168.1.50:3000","savedAt":1000000000,"state":"# + Demo.settings + "}").utf8)
    }

    func read() -> Data? { data }
    func write(_ data: Data?) { self.data = data }
}

final class DemoSecrets: SecretStore {
    private var values: [String: String] = [:]
    func write(_ key: String, _ value: String) throws { values[key] = value }
    func read(_ key: String) throws -> String? { values[key] }
    func delete(_ key: String) throws { values[key] = nil }
    func deleteAll() throws { values = [:] }
}

final class DemoPrefs: PrefsStore {
    private var values: [String: String] = [:]
    func string(_ key: String) -> String? { values[key] }
    func set(_ value: String?, _ key: String) { values[key] = value }
}
#endif
