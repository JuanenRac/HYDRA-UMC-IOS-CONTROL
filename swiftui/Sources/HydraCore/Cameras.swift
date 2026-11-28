// HYDRA-UMC-IOS-CONTROL - the live camera picture: which camera belongs to a robot, the frames of the MJPEG stream and the player that
// opens it again after an end, a refusal or a silence. The same rules as the published apps.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public extension CellState {
    /// The camera that shows a robot: the lowest id of the cameras that name it in `assignedRobotId`, else the robot id (a server
    /// whose cameras carry no assignment numbers them like its robots). The stream route takes the camera id.
    func cameraId(forRobot robotId: Int) -> Int {
        var best: Int?
        for case let controller as [String: Any] in raw["controllers"] as? [Any] ?? [] {
            for case let camera as [String: Any] in controller["cameras"] as? [Any] ?? [] {
                guard let id = camera["id"] as? Int, camera["assignedRobotId"] as? Int == robotId else { continue }
                best = min(best ?? id, id)
            }
        }
        return best ?? robotId
    }

    /// Whether the camera of a robot is on: `visionEnabled` when the server sends it, else the `connected` of an older server.
    func cameraOn(_ robotId: Int) -> Bool {
        guard let robot = robot(robotId)?.raw else { return false }
        if let vision = robot["visionEnabled"] { return vision as? Bool == true }
        return (robot["camera"] as? [String: Any])?["connected"] as? Bool == true
    }
}

/// The pause before a stream is opened again: one second, doubled with every attempt that brought no frame, four doublings at most
/// and never more than fifteen seconds.
public enum MjpegReconnectPolicy {
    public static let baseDelay = 1.0
    public static let maxDelay = 15.0
    /// How long a connection may stay silent before it is given up.
    public static let stallTimeout = 30.0

    public static func failures(after previous: Int, gotFrame: Bool) -> Int {
        gotFrame ? 0 : min(max(previous, 0), 1000) + 1
    }

    public static func delay(failures: Int) -> Double {
        min(baseDelay * Double(1 << min(max(failures, 0), 4)), maxDelay)
    }
}

/// Finds the JPEG pictures in the bytes of a stream by their start and end markers, whatever the multipart framing is.
public struct MjpegParser {
    public static let maxPending = 4 * 1024 * 1024
    private var pending: [UInt8] = []

    public init() {}

    public var pendingCount: Int { pending.count }

    /// Adds a piece of the stream and returns the NEWEST complete picture, so a slow screen never lags further behind.
    public mutating func add(_ data: Data) -> Data? {
        pending.append(contentsOf: data)
        if pending.count > MjpegParser.maxPending {
            // never produced an end: start over
            pending = []
            return nil
        }
        guard pending.count >= 4 else { return nil }
        var end = -1
        var index = pending.count - 2
        while index >= 0 {
            if pending[index] == 0xFF && pending[index + 1] == 0xD9 { end = index; break }
            index -= 1
        }
        if end < 0 { return nil }
        index = end - 2
        while index >= 0 {
            if pending[index] == 0xFF && pending[index + 1] == 0xD8 {
                let frame = Data(pending[index..<(end + 2)])
                pending.removeFirst(end + 2)
                return frame
            }
            index -= 1
        }
        // an end with no start: a picture joined half way
        pending.removeFirst(end + 2)
        return nil
    }
}

public enum CameraEvent: Sendable {
    /// The status of the answer; only 200 is a stream.
    case response(Int)
    case data(Data)
    case ended
}

@MainActor
public protocol CameraStreamTransport {
    func open(url: String, headers: [String: String], onEvent: @escaping @MainActor (CameraEvent) -> Void) -> LiveConnection
}

public struct CameraRequest: Equatable, Sendable {
    public var url: String
    public var headers: [String: String]

    public init(url: String, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }
}

public enum CameraPicture: Equatable, Sendable {
    case connecting, live
    /// With the status of the answer when the server refused it.
    case unavailable(Int?)
}

/// One camera on screen. It downloads only between `start` and `stop`, keeps the last picture while it reconnects, and drops what
/// an earlier attempt still says.
@MainActor
public final class CameraFeed {
    public private(set) var frame: Data?
    public private(set) var state: CameraPicture = .connecting
    public private(set) var running = false
    public var onChange: (() -> Void)?

    private let transport: CameraStreamTransport
    private let schedule: Scheduler
    private let now: () -> Date
    private var request: (() -> CameraRequest?)?
    private var refused: (() async -> Void)?
    private var connection: LiveConnection?
    private var parser = MjpegParser()
    private var cancelRetry: (() -> Void)?
    private var cancelStall: (() -> Void)?
    private var generation = 0
    private var failures = 0
    private var gotFrame = false
    private var heard = Date()

    public init(transport: CameraStreamTransport, schedule: @escaping Scheduler = standardScheduler, now: @escaping () -> Date = Date.init) {
        self.transport = transport
        self.schedule = schedule
        self.now = now
    }

    /// `request` is asked at every attempt (the token may have been renewed); `refused` runs after a 401.
    public func start(request: @escaping () -> CameraRequest?, refused: @escaping () async -> Void) {
        stop()
        self.request = request
        self.refused = refused
        running = true
        frame = nil
        failures = 0
        state = .connecting
        open()
    }

    public func stop() {
        guard running else { return }
        running = false
        close()
        cancelRetry?()
        cancelRetry = nil
        request = nil
        refused = nil
        frame = nil
        state = .connecting
        onChange?()
    }

    private func close() {
        generation += 1
        cancelStall?()
        cancelStall = nil
        connection?.close()
        connection = nil
    }

    private func open() {
        cancelRetry?()
        cancelRetry = nil
        close()
        parser = MjpegParser()
        gotFrame = false
        guard let next = request?() else {
            state = .unavailable(nil)
            ended()
            return
        }
        let mine = generation
        heard = now()
        watch(mine, MjpegReconnectPolicy.stallTimeout)
        connection = transport.open(url: next.url, headers: next.headers) { [weak self] event in self?.received(event, mine) }
        onChange?()
    }

    private func watch(_ mine: Int, _ seconds: Double) {
        cancelStall = schedule(seconds) { [weak self] in
            guard let self, mine == self.generation else { return }
            let silent = self.now().timeIntervalSince(self.heard)
            if silent < MjpegReconnectPolicy.stallTimeout {
                self.watch(mine, MjpegReconnectPolicy.stallTimeout - silent)
                return
            }
            self.state = .unavailable(nil)
            self.ended()
        }
    }

    private func received(_ event: CameraEvent, _ mine: Int) {
        guard mine == generation, running else { return }
        heard = now()
        switch event {
        case .response(let status):
            guard status != 200 else { return }
            state = .unavailable(status)
            let renew = status == 401 ? refused : nil
            ended()
            if let renew { Task { await renew() } }
        case .data(let data):
            guard let picture = parser.add(data) else { return }
            gotFrame = true
            frame = picture
            state = .live
            onChange?()
        case .ended:
            state = .unavailable(nil)
            ended()
        }
    }

    private func ended() {
        close()
        failures = MjpegReconnectPolicy.failures(after: failures, gotFrame: gotFrame)
        cancelRetry = schedule(MjpegReconnectPolicy.delay(failures: failures)) { [weak self] in
            guard let self, self.running else { return }
            self.open()
        }
        onChange?()
    }
}

/// The address of the 3D viewer of the server. The token goes in the fragment, which is never sent to the server.
public enum ViewerUrl {
    public static func build(base: String, robotId: Int, token: String?) -> String {
        let address = "\(base)/?hideUI=true&robotId=\(robotId)"
        guard let token, !token.isEmpty else { return address }
        let plain = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return address + "#token=" + (token.addingPercentEncoding(withAllowedCharacters: plain) ?? "")
    }
}
