// HYDRA-UMC-IOS-CONTROL - a pretend server and phone for the interface tests and the screenshots. Compiled only in debug builds; no release build can start it.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
#if DEBUG
import Foundation
import HydraCore

/// Launch arguments: `-hydraDemo main|login|welcome` and `-hydraDemoStopFails`.
enum Demo {
    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-hydraDemo"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var stopFails: Bool { ProcessInfo.processInfo.arguments.contains("-hydraDemoStopFails") }
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
        case "/api/settings": json = #"{"controllers":[{"id":"c1","robots":[{"id":1,"name":"Robot A1"},{"id":2,"name":"Robot A2"}]}]}"#
        case "/api/stop-all":
            if failsThisStop() { throw TransportError.unreachable }
            json = #"{"success":true,"stoppedCount":2,"failedCount":0,"persisted":true,"robots":[{"robotId":1,"name":"Robot A1","stopped":true},{"robotId":2,"name":"Robot A2","stopped":true}]}"#
        case "/api/login": json = #"{"success":true,"token":"demo","refreshToken":"demo"}"#
        default: json = "{}"
        }
        return HttpResponse(status: 200, body: Data(json.utf8))
    }
}

final class DemoSecrets: SecretStore {
    private var values: [String: String] = [:]
    func write(_ key: String, _ value: String) throws { values[key] = value }
    func read(_ key: String) throws -> String? { values[key] }
    func delete(_ key: String) throws { values[key] = nil }
}

final class DemoPrefs: PrefsStore {
    private var values: [String: String] = [:]
    func string(_ key: String) -> String? { values[key] }
    func set(_ value: String?, _ key: String) { values[key] = value }
}
#endif
