// HYDRA-UMC-IOS-CONTROL - the app against the pretend server of the family, over real sockets: sign-in, live state, reservation, jog and STOP.
// Needs swiftui/bench/hydra_ws_bench.py running and HYDRA_BENCH_URL=host:port; without it the tests are skipped, unless HYDRA_BENCH_REQUIRED=1.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest
@testable import HydraCore

private final class PlainTransport: HttpTransport, @unchecked Sendable {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        guard let url = URL(string: request.url) else { throw TransportError.unreachable }
        var made = URLRequest(url: url, timeoutInterval: request.timeout)
        made.httpMethod = request.method
        made.httpBody = request.body
        for (name, value) in request.headers { made.setValue(value, forHTTPHeaderField: name) }
        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: made) { data, response, _ in
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: TransportError.unreachable)
                    return
                }
                continuation.resume(returning: HttpResponse(status: http.statusCode, body: data ?? Data()))
            }.resume()
        }
    }
}

@MainActor
private final class PlainSocket: LiveConnection {
    private let task: URLSessionWebSocketTask
    private var onEvent: (@MainActor (SocketEvent) -> Void)?
    private var opened = false

    init(url: URL, protocols: [String], onEvent: @escaping @MainActor (SocketEvent) -> Void) {
        self.onEvent = onEvent
        var request = URLRequest(url: url)
        request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        receive()
    }

    private func receive() {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, let tell = self.onEvent else { return }
                switch result {
                case .success(let message):
                    if !self.opened {
                        self.opened = true
                        tell(.opened)
                    }
                    if case .string(let text) = message { tell(.text(text)) }
                    self.receive()
                case .failure:
                    let code = self.task.closeCode.rawValue
                    self.close()
                    tell(.closed(code: code == 0 ? nil : code))
                }
            }
        }
    }

    func close() {
        onEvent = nil
        task.cancel(with: .goingAway, reason: nil)
    }
}

@MainActor
private final class PlainSockets: LiveSocketTransport {
    func open(url: String, protocols: [String], onEvent: @escaping @MainActor (SocketEvent) -> Void) -> LiveConnection {
        PlainSocket(url: URL(string: url)!, protocols: protocols, onEvent: onEvent)
    }
}

@MainActor
final class BenchTests: XCTestCase {
    private func signedIn() async throws -> HydraController {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["HYDRA_BENCH_URL"], let colon = url.lastIndex(of: ":") else {
            XCTAssertNotEqual(environment["HYDRA_BENCH_REQUIRED"], "1", "the bench is required and not there")
            throw XCTSkip("no bench running")
        }
        let controller = HydraController(transport: PlainTransport(), discoveryTransport: PlainTransport(), secrets: MemorySecrets(), prefs: MemoryPrefs(), auth: FakeAuth(),
                                         appVersion: "0.0.1", sockets: PlainSockets(), cache: MemoryCache())
        await controller.start()
        await controller.login(host: String(url[..<colon]), port: String(url[url.index(after: colon)...]), username: "admin", password: "admin", code: "")
        XCTAssertEqual(controller.screen, .main)
        await until { controller.linkOk }
        XCTAssertTrue(controller.linkOk, "the live link opens")
        return controller
    }

    func testTheLiveLinkReservesJogsAndStops() async throws {
        let controller = try await signedIn()
        let control = controller.control
        await until { !controller.robots.isEmpty }
        control.select(1)
        await control.claimRobot()
        XCTAssertNil(controller.message)
        await until { control.standing(1) == .mineHere }
        XCTAssertEqual(control.standing(1), .mineHere)

        // the pretend server wants the jog armed
        await control.jog(.robot, axis: "x", amount: 1).first?.value
        XCTAssertEqual(controller.message?.key, "errJogNotArmed")
        await control.setJogArmed(true)
        await control.jog(.robot, axis: "x", amount: 1).first?.value
        XCTAssertNil(controller.message)

        control.setDeadManEnabled(true)
        await control.press(1, target: .robot, axis: "x", direction: 1)?.value
        XCTAssertTrue(control.deadMan.isRunning(1), controller.message?.key ?? "")
        try await Task.sleep(nanoseconds: 300_000_000)
        control.release(1)
        await control.deadMan.waitStops()
        XCTAssertNotEqual(controller.message?.key, "deadManStopNotConfirmed")

        control.setListenOnly(true)
        XCTAssertNil(control.play())
        await control.stopRobot()?.value
        XCTAssertNil(controller.message)
        await controller.stopAll()
        XCTAssertFalse(controller.stopUnconfirmed)
        XCTAssertEqual(controller.stopResult?.stoppedCount, 2)
        control.setListenOnly(false)
        await control.releaseRobot()
        // the stops moved the revision of the robot: the first release may be refused with 412, and it reads the robot again
        if controller.message?.key == "errRevisionChanged" { await control.releaseRobot() }
        await until { control.standing(1) == .free }
        XCTAssertEqual(control.standing(1), .free)
        controller.logout()
    }
}
