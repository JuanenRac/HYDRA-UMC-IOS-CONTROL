// HYDRA-UMC-IOS-CONTROL - how the app reaches the server and what it trusts: HTTPS first, plain HTTP only when allowed, and certificate fingerprints kept per server.
// The same rules as the published app (SDK, tls_settings).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum TlsPolicy {
    private static func bare(_ host: String) -> String {
        var h = host.trimmingCharacters(in: .whitespaces).lowercased()
        if h.hasPrefix("["), h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }
        return h
    }

    public static func isLoopback(_ host: String) -> Bool {
        let h = bare(host)
        return h == "localhost" || h == "::1" || HostRules.matches(h, "^127\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$")
    }

    /// True for an address of the local network (private ranges, link local, single-label and `.local` names).
    public static func isLocalHost(_ host: String) -> Bool {
        let h = bare(host)
        if h.isEmpty { return false }
        if h == "localhost" { return true }
        if h.contains(":") { return h == "::1" || h.hasPrefix("fe80:") || h.hasPrefix("fc") || h.hasPrefix("fd") }
        let parts = h.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let numbers = parts.compactMap { Int($0) }
        if parts.count == 4, numbers.count == 4, numbers.allSatisfy({ (0...255).contains($0) }) {
            let a = numbers[0], b = numbers[1]
            return a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254)
        }
        if parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) { return false }
        return parts.count == 1 || h.hasSuffix(".local") || h.hasSuffix(".lan") || h.hasSuffix(".home.arpa")
    }
}

public enum Fingerprint {
    /// 64 lowercase hexadecimal digits, or nil. Colons, dashes and spaces are accepted in what is typed.
    public static func normalize(_ input: String) -> String? {
        let cleaned = input.filter { $0 != ":" && $0 != "-" && !$0.isWhitespace }.lowercased()
        return cleaned.count == 64 && cleaned.allSatisfy { "0123456789abcdef".contains($0) } ? cleaned : nil
    }

    public static func display(_ hex: String) -> String {
        let upper = Array(hex.uppercased())
        return stride(from: 0, to: upper.count - 1, by: 2).map { String(upper[$0...($0 + 1)]) }.joined(separator: ":")
    }
}

public struct TlsSettings: Equatable, Codable, Sendable {
    public var allowPlainHttp: Bool
    public var allowPlainRemote: Bool
    /// SHA-256 of the whole certificate, by `ServerAddress.key`.
    public var pins: [String: String]
    public var allowPlainWithPin: Bool

    public init(allowPlainHttp: Bool = false, allowPlainRemote: Bool = false, pins: [String: String] = [:], allowPlainWithPin: Bool = false) {
        self.allowPlainHttp = allowPlainHttp
        self.allowPlainRemote = allowPlainRemote
        self.pins = pins
        self.allowPlainWithPin = allowPlainWithPin
    }

    public func pin(for address: ServerAddress) -> String? { pins[address.key].flatMap(Fingerprint.normalize) }

    public func hasPin(forHost host: String) -> Bool {
        let prefix = "\(host.trimmingCharacters(in: .whitespaces).lowercased()):"
        return pins.contains { $0.key.hasPrefix(prefix) && !$0.value.isEmpty }
    }

    public func withPin(_ fingerprint: String?, for address: ServerAddress) -> TlsSettings {
        var copy = self
        copy.pins[address.key] = fingerprint.flatMap(Fingerprint.normalize)
        return copy
    }

    /// Whether plain HTTP may be tried for `host`. A pinned certificate says the server is trusted over TLS only.
    public func plainAllowed(forHost host: String) -> Bool {
        if TlsPolicy.isLoopback(host) { return true }
        if hasPin(forHost: host), !allowPlainWithPin { return false }
        return allowPlainHttp && (allowPlainRemote || TlsPolicy.isLocalHost(host))
    }
}

/// The validity window of a certificate, read from its DER form: a pinned certificate is refused outside it.
public enum CertificateDates {
    private struct Element {
        let tag: UInt8
        let content: ArraySlice<UInt8>
    }

    private static func read(_ bytes: inout ArraySlice<UInt8>) -> Element? {
        guard bytes.count >= 2 else { return nil }
        let tag = bytes.removeFirst()
        var length = Int(bytes.removeFirst())
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count > 0, count <= 4, bytes.count >= count else { return nil }
            length = 0
            for _ in 0..<count { length = length << 8 | Int(bytes.removeFirst()) }
        }
        guard bytes.count >= length else { return nil }
        let content = bytes.prefix(length)
        bytes = bytes.dropFirst(length)
        return Element(tag: tag, content: content)
    }

    private static func date(_ element: Element) -> Date? {
        guard let text = String(bytes: element.content, encoding: .ascii), text.hasSuffix("Z") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        switch element.tag {
        case 0x17:   // UTCTime: two digit year, 50-99 is the last century
            guard text.count == 13, let year = Int(text.prefix(2)) else { return nil }
            formatter.dateFormat = "yyyyMMddHHmmss'Z'"
            return formatter.date(from: (year >= 50 ? "19" : "20") + text)
        case 0x18:
            formatter.dateFormat = "yyyyMMddHHmmss'Z'"
            return formatter.date(from: text)
        default:
            return nil
        }
    }

    public static func window(der: Data) -> (notBefore: Date, notAfter: Date)? {
        var all = ArraySlice([UInt8](der))
        guard let certificate = read(&all), certificate.tag == 0x30 else { return nil }
        var body = certificate.content
        guard let tbs = read(&body), tbs.tag == 0x30 else { return nil }
        var fields = tbs.content
        guard var first = read(&fields) else { return nil }
        if first.tag == 0xa0 {   // the version is optional
            guard let next = read(&fields) else { return nil }
            first = next
        }
        // first is the serial number; then the signature algorithm, the issuer and the validity
        guard read(&fields) != nil, read(&fields) != nil, let validity = read(&fields), validity.tag == 0x30 else { return nil }
        var pair = validity.content
        guard let from = read(&pair), let to = read(&pair), let notBefore = date(from), let notAfter = date(to) else { return nil }
        return (notBefore, notAfter)
    }

    /// A pinned certificate is accepted when it is the pinned one and it is in date. `sha256` is the hexadecimal digest of `der`.
    public static func pinMatches(pin: String, sha256: String, der: Data, now: Date = Date()) -> Bool {
        guard Fingerprint.normalize(pin) == Fingerprint.normalize(sha256), Fingerprint.normalize(pin) != nil, let window = window(der: der) else { return false }
        return now >= window.notBefore && now <= window.notAfter
    }
}
