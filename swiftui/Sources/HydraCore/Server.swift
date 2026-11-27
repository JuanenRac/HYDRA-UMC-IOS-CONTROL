// HYDRA-UMC-IOS-CONTROL - what a server is: its address, and what the app keeps about the ones it used.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum HostRules {
    private static let name = "^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$"
    private static let ipv6 = "^[0-9A-Fa-f:]{2,45}$"
    private static let ipv4 = "^(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})$"

    static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// True for a host the app accepts: a name, an IPv4 address or an IPv6 address without brackets. Nothing with a path, a user or a space.
    public static func isValid(_ host: String) -> Bool {
        if matches(host, ipv4) { return host.split(separator: ".").allSatisfy { (Int($0) ?? 256) <= 255 } }
        if host.contains(":") { return matches(host, ipv6) }
        return matches(host, name)
    }
}

public struct ServerAddress: Equatable, Hashable, Codable, Sendable {
    public var host: String
    public var port: Int
    public static let defaultPort = 3000

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    /// The address typed by a person, or nil when it is not one.
    public static func parse(host: String, port: String) -> ServerAddress? {
        var cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHost.hasPrefix("["), cleanHost.hasSuffix("]") { cleanHost = String(cleanHost.dropFirst().dropLast()) }
        let cleanPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HostRules.isValid(cleanHost), HostRules.matches(cleanPort, "^\\d{1,5}$"), let number = Int(cleanPort), (1...65535).contains(number) else { return nil }
        return ServerAddress(host: cleanHost, port: number)
    }

    /// The key the certificate pins are kept under.
    public var key: String { "\(host.trimmingCharacters(in: .whitespaces).lowercased()):\(port)" }

    public func baseUrl(tls: Bool) -> String {
        let shown = host.contains(":") ? "[\(host)]" : host
        return "\(tls ? "https" : "http")://\(shown):\(port)"
    }
}

/// A server this phone has signed in to (never with a password or a token).
public struct SavedServer: Equatable, Codable, Sendable, Identifiable {
    public var address: ServerAddress
    public var name: String
    public var useTls: Bool
    public var id: String { address.key }

    public init(address: ServerAddress, name: String, useTls: Bool) {
        self.address = address
        self.name = name
        self.useTls = useTls
    }

    public static let limit = 5

    /// The list with `server` first, without repeats, at most `limit` long.
    public static func remember(_ server: SavedServer, in list: [SavedServer]) -> [SavedServer] {
        Array(([server] + list.filter { $0.id != server.id }).prefix(limit))
    }
}

/// A server found on the network by its answer to `GET /api/hydra-info`.
public struct FoundServer: Equatable, Sendable, Identifiable {
    public var address: ServerAddress
    public var name: String
    public var robotCount: Int
    public var useTls: Bool
    public var id: String { address.key }

    public init(address: ServerAddress, name: String, robotCount: Int, useTls: Bool) {
        self.address = address
        self.name = name
        self.robotCount = robotCount
        self.useTls = useTls
    }

    public init(address: ServerAddress, info: [String: Any], useTls: Bool) {
        let hostname = info["hostname"] as? String ?? ""
        self.init(address: address, name: hostname.isEmpty ? address.host : hostname, robotCount: info["robotCount"] as? Int ?? 0, useTls: useTls)
    }
}
