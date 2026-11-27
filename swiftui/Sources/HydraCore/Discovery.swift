// HYDRA-UMC-IOS-CONTROL - looking for servers on the local network: which subnets to walk, and the walk. The probe only reads `GET /api/hydra-info`, never with a session.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum Discovery {
    public static let serviceType = "_hydra._tcp"
    public static let concurrency = 32

    /// Mobile data and VPN interfaces by the names of the systems.
    public static func isMobileOrVpn(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["pdp_ip", "rmnet", "ccmni", "wwan", "utun", "ipsec", "ppp", "tun", "tap", "wg"].contains { lower.hasPrefix($0) }
    }

    /// The first three numbers of every IPv4 address of the phone, plus those of the last server used.
    public static func prefixes(interfaces: [String: [String]], lastHost: String?, skipMobileAndVpn: Bool) -> [String] {
        var result: [String] = []
        func add(_ address: String) {
            let parts = address.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4, parts.allSatisfy({ (Int($0) ?? 256) <= 255 }) else { return }
            let prefix = parts[0..<3].joined(separator: ".")
            if !result.contains(prefix) { result.append(prefix) }
        }
        for name in interfaces.keys.sorted() where !(skipMobileAndVpn && isMobileOrVpn(name)) {
            // loopback is never walked
            for address in interfaces[name] ?? [] where !address.hasPrefix("127.") { add(address) }
        }
        if let lastHost { add(lastHost) }
        return result.isEmpty ? ["192.168.1"] : result
    }

    public static func hosts(prefix: String) -> [String] { (1...254).map { "\(prefix).\($0)" } }

    /// Asks every host, at most `concurrency` at a time, and reports each server as it answers.
    @MainActor
    public static func scan(hosts: [String], probe: @escaping @MainActor (String) async -> FoundServer?, found: @escaping @MainActor (FoundServer) -> Void) async {
        await withTaskGroup(of: FoundServer?.self) { group in
            var waiting = hosts.makeIterator()
            for _ in 0..<concurrency {
                if let host = waiting.next() { group.addTask { await probe(host) } }
            }
            while let answer = await group.next() {
                if Task.isCancelled { continue }
                if let server = answer { await found(server) }
                if let host = waiting.next() { group.addTask { await probe(host) } }
            }
        }
    }
}
