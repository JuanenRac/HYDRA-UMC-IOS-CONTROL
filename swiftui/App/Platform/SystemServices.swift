// HYDRA-UMC-IOS-CONTROL - what needs the phone: HTTP with the certificate rules, the Keychain, the preferences, Face ID / Touch ID and the network interfaces.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation
import CryptoKit
import LocalAuthentication
import Network
import Security
import HydraCore

/// The certificate rules of a session. With a fingerprint kept for the server only that certificate (in date) is accepted; without one the system decides.
/// `acceptAny` is only for the search of servers, which reads the public identity and sends no credential.
final class TrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let acceptAny: Bool
    private let lock = NSLock()
    private var settings = TlsSettings()
    private var seen: [String: (fingerprint: String, subject: String)] = [:]

    init(acceptAny: Bool) { self.acceptAny = acceptAny }

    func update(_ value: TlsSettings) { lock.lock(); settings = value; lock.unlock() }

    private func current() -> TlsSettings { lock.lock(); defer { lock.unlock() }; return settings }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if acceptAny {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        guard let pin = current().pin(for: ServerAddress(host: space.host, port: space.port)) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let der = SecCertificateCopyData(leaf) as Data
        if CertificateDates.pinMatches(pin: pin, sha256: TrustDelegate.sha256(der), der: der) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

/// Reads the certificate a server presents, so the person can compare its fingerprint before trusting it. Nothing is sent after the handshake.
final class CertificateReader: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var found: (fingerprint: String, subject: String)?

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust, let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first {
            let value = (TrustDelegate.sha256(SecCertificateCopyData(leaf) as Data), SecCertificateCopySubjectSummary(leaf) as String? ?? "")
            lock.lock(); found = value; lock.unlock()
        }
        // the connection is dropped: only the certificate was wanted
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    private func take() -> (fingerprint: String, subject: String)? { lock.lock(); defer { lock.unlock() }; return found }

    static func read(_ address: ServerAddress) async -> (fingerprint: String, subject: String)? {
        guard let url = URL(string: address.baseUrl(tls: true) + "/api/hydra-info") else { return nil }
        let reader = CertificateReader()
        let session = URLSession(configuration: .ephemeral, delegate: reader, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        _ = try? await session.data(for: URLRequest(url: url, timeoutInterval: 5))
        return reader.take()
    }
}

/// No redirect is followed: a request with the session never goes anywhere else.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class UrlSessionTransport: HttpTransport, @unchecked Sendable {
    let trust: TrustDelegate
    private let lock = NSLock()
    private var current: URLSession

    init(acceptAnyCertificate: Bool = false) {
        trust = TrustDelegate(acceptAny: acceptAnyCertificate)
        current = UrlSessionTransport.makeSession(trust)
    }

    private static func makeSession(_ trust: TrustDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: trust, delegateQueue: nil)
    }

    private var session: URLSession { lock.lock(); defer { lock.unlock() }; return current }

    /// New settings need new connections: a pooled one would keep what was decided before. Requests on their way finish.
    func apply(_ settings: TlsSettings) {
        trust.update(settings)
        lock.lock()
        let old = current
        current = UrlSessionTransport.makeSession(trust)
        lock.unlock()
        old.finishTasksAndInvalidate()
    }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        guard let url = URL(string: request.url) else { throw TransportError.unreachable }
        var made = URLRequest(url: url, timeoutInterval: request.timeout)
        made.httpMethod = request.method
        made.httpBody = request.body
        for (name, value) in request.headers { made.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await session.data(for: made, delegate: NoRedirect())
            guard let http = response as? HTTPURLResponse else { throw TransportError.unreachable }
            var headers: [String: String] = [:]
            for (name, value) in http.allHeaderFields {
                if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
            }
            return HttpResponse(status: http.statusCode, headers: headers, body: data)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw TransportError.timeout
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
                throw TransportError.tls
            case .cancelled:
                // cancelled by the certificate rules, unless the caller gave up
                throw Task.isCancelled ? TransportError.timeout : TransportError.tls
            default: throw TransportError.unreachable
            }
        }
    }
}

/// The Keychain of the phone: readable after the first unlock, and never leaves this device.
final class KeychainSecrets: SecretStore {
    private let service = "com.hydraumc.hydraUmcControl.native"
    struct Failure: Error { let status: OSStatus }

    private func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    func write(_ key: String, _ value: String) throws {
        try delete(key)
        var item = base(key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { throw Failure(status: status) }
    }

    func read(_ key: String) throws -> String? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw Failure(status: status) }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) throws {
        let status = SecItemDelete(base(key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { throw Failure(status: status) }
    }
}

final class DefaultsPrefs: PrefsStore {
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    func string(_ key: String) -> String? { defaults.string(forKey: key) }
    func set(_ value: String?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

struct PhoneAuth: DeviceAuth {
    var isAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""   // no passcode way around the lock
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
    }
}

enum NetworkInterfaces {
    /// The IPv4 addresses of the phone by interface name.
    static func ipv4() -> [String: [String]] {
        var result: [String: [String]] = [:]
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return result }
        defer { freeifaddrs(first) }
        var pointer = first
        while let current = pointer {
            let entry = current.pointee
            if let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    result[String(cString: entry.ifa_name), default: []].append(String(cString: host))
                }
            }
            pointer = entry.ifa_next
        }
        return result
    }
}

/// Servers that announce themselves with Bonjour (`_hydra._tcp`): each announcement is resolved to an address and a port.
@MainActor
final class BonjourSearch {
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []

    func start(found: @escaping @MainActor (String, Int) -> Void) {
        stop()
        let browser = NWBrowser(for: .bonjour(type: Discovery.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                for result in results { self?.resolve(result.endpoint, found: found) }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func resolve(_ endpoint: NWEndpoint, found: @escaping @MainActor (String, Int) -> Void) {
        let parameters = NWParameters.tcp
        if let options = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { options.version = .v4 }
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak connection] state in
            guard case .ready = state, case let .hostPort(host, port)? = connection?.currentPath?.remoteEndpoint else { return }
            // "192.168.1.50%en0" carries the interface; only the address is wanted
            let text = "\(host)".split(separator: "%").first.map(String.init) ?? ""
            connection?.cancel()
            Task { @MainActor in found(text, Int(port.rawValue)) }
        }
        connection.start(queue: .main)
        connections.append(connection)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        connections.forEach { $0.cancel() }
        connections = []
    }
}
