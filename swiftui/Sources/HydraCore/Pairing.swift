// HYDRA-UMC-IOS-CONTROL - the pairing link of the admin page of the server (hydra-umc://pair?host=..&port=..&fp=..&name=..). The fingerprint is required.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public struct PairingOffer: Equatable, Sendable {
    public var address: ServerAddress
    public var fingerprint: String
    public var name: String
}

public enum PairingProblem: Error, Equatable {
    case empty, tooLong, notAPairingLink, missingHost, badHost, badPort, badFingerprint, missingFingerprint, badName, repeatedField, badEncoding

    /// The text of the catalog that says it.
    public var textKey: String {
        switch self {
        case .notAPairingLink: return "pairingProblemNotLink"
        case .missingHost, .badHost: return "pairingProblemHost"
        case .badPort: return "pairingProblemPort"
        case .badFingerprint: return "pairingProblemFingerprint"
        case .missingFingerprint: return "pairingProblemNoFingerprint"
        case .badName: return "pairingProblemName"
        case .empty, .tooLong, .repeatedField, .badEncoding: return "pairingProblemGeneric"
        }
    }
}

public enum PairingLink {
    static let prefix = "hydra-umc://pair?"
    static let maxLength = 600
    static let nameMax = 64

    public static func parse(_ input: String) -> Result<PairingOffer, PairingProblem> {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .failure(.empty) }
        if text.count > maxLength { return .failure(.tooLong) }
        if !text.lowercased().hasPrefix(prefix) { return .failure(.notAPairingLink) }
        var query = String(text.dropFirst(prefix.count))
        if let hash = query.firstIndex(of: "#") { query = String(query[..<hash]) }
        var fields: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = parts[0].lowercased()
            let raw = parts.count > 1 ? String(parts[1]) : ""
            guard let value = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else { return .failure(.badEncoding) }
            if ["host", "port", "fp", "name"].contains(key) {
                if fields[key] != nil { return .failure(.repeatedField) }
                fields[key] = value
            }
        }
        var host = (fields["host"] ?? "").trimmingCharacters(in: .whitespaces)
        if host.hasPrefix("[") { host.removeFirst() }
        if host.hasSuffix("]") { host.removeLast() }
        if host.isEmpty { return .failure(.missingHost) }
        if !HostRules.isValid(host) { return .failure(.badHost) }
        let portText = (fields["port"] ?? "").trimmingCharacters(in: .whitespaces)
        guard HostRules.matches(portText, "^\\d{1,5}$"), let port = Int(portText), (1...65535).contains(port) else { return .failure(.badPort) }
        let fingerprintText = (fields["fp"] ?? "").trimmingCharacters(in: .whitespaces)
        if fingerprintText.isEmpty { return .failure(.missingFingerprint) }
        guard let fingerprint = Fingerprint.normalize(fingerprintText) else { return .failure(.badFingerprint) }
        let name = (fields["name"] ?? "").trimmingCharacters(in: .whitespaces)
        if name.unicodeScalars.count > nameMax || name.unicodeScalars.contains(where: { $0.value < 0x20 || (0x7f...0x9f).contains($0.value) }) { return .failure(.badName) }
        return .success(PairingOffer(address: ServerAddress(host: host, port: port), fingerprint: fingerprint, name: name.isEmpty ? host : name))
    }
}
