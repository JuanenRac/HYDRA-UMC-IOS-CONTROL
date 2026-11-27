// HYDRA-UMC-IOS-CONTROL - the state of the app and what changes it: first use, sign-in, the saved session and its lock, pairing and the global STOP. No screen here.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// Face ID or Touch ID. Biometrics only: there is no passcode way around the lock, as in the published app.
public protocol DeviceAuth {
    var isAvailable: Bool { get }
    func authenticate(reason: String) async -> Bool
}

public enum AppScreen: Equatable {
    case starting, welcome, locked, login, main
}

public enum SecondFactorStep: Equatable {
    case none, needed, wrong
    case wait(seconds: Int)
}

/// A text of the catalog to show, with its values.
public struct Message: Equatable {
    public var key: String
    public var values: [String: String]

    public init(_ key: String, _ values: [String: String] = [:]) {
        self.key = key
        self.values = values
    }
}

public enum PrefKey {
    public static let server = "hydra_server"
    public static let username = "hydra_last_username"
    public static let savedServers = "hydra_saved_servers"
    public static let tls = "hydra_tls"
    public static let pairing = "hydra_pairing"
    public static let biometric = "hydra_biometric"
    public static let language = "hydra_language"
    public static let controllerId = "hydra_controller_id"
    public static let firstRunDone = "hydra_first_run_done"
    public static let skipMobileVpn = "hydra_scan_skip_mobile_vpn"
}

@MainActor
public final class HydraController {
    private let transport: HttpTransport
    private let discoveryTransport: HttpTransport
    private let prefs: PrefsStore
    private let secrets: SecretStore
    /// One session per server, by `ServerAddress.key`.
    private var stores: [String: SessionStore] = [:]
    private let auth: DeviceAuth
    private let appVersion: String
    private let sequence = CommandSequence()

    /// Called after every change of the state below.
    public var onChange: (() -> Void)?

    public private(set) var screen: AppScreen = .starting { didSet { changed() } }
    public private(set) var server: SavedServer? { didSet { changed() } }
    public private(set) var savedServers: [SavedServer] = [] { didSet { changed() } }
    public private(set) var signingIn = false { didSet { changed() } }
    public private(set) var secondFactor: SecondFactorStep = .none { didSet { changed() } }
    public var message: Message? { didSet { changed() } }
    /// Whether the last read of the server answered.
    public private(set) var linkOk = false { didSet { changed() } }
    public private(set) var roster: [RosterRobot] = [] { didSet { changed() } }

    public private(set) var stopsInFlight = 0 { didSet { changed() } }
    /// A STOP got no answer (until a later one does): the robots may still be moving.
    public private(set) var stopUnconfirmed = false { didSet { changed() } }
    public private(set) var stopResult: StopAllResult? { didSet { changed() } }

    public private(set) var tlsSettings = TlsSettings() { didSet { changed() } }
    public private(set) var pairingEnabled = false { didSet { changed() } }
    public private(set) var pendingPairing: PairingOffer? { didSet { changed() } }
    /// The address a confirmed pairing leaves for the sign-in form.
    public private(set) var pairedAddress: ServerAddress? { didSet { changed() } }
    public private(set) var biometricEnabled = false { didSet { changed() } }
    public private(set) var chosenLanguage: String? { didSet { changed() } }

    private var client: HydraClient?
    /// The renewal on its way and the client it belongs to: its token never goes to another one.
    private var renewal: (client: HydraClient, task: Task<String?, Never>)?
    /// Rises with every sign-in and sign-out: an answer of an earlier session is dropped.
    private var generation = 0

    public init(transport: HttpTransport, discoveryTransport: HttpTransport, secrets: SecretStore, prefs: PrefsStore, auth: DeviceAuth, appVersion: String) {
        self.transport = transport
        self.discoveryTransport = discoveryTransport
        self.prefs = prefs
        self.secrets = secrets
        self.auth = auth
        self.appVersion = appVersion
    }

    private func changed() { onChange?() }

    private func sessions(_ address: ServerAddress) -> SessionStore {
        if let kept = stores[address.key] { return kept }
        let made = SessionStore(secrets: secrets, prefs: prefs, scope: address.key)
        stores[address.key] = made
        return made
    }

    /// Whether this phone holds a session of that server.
    public func hasSession(_ saved: SavedServer) -> Bool { sessions(saved.address).token != nil }

    public var biometricAvailable: Bool { auth.isAvailable }
    public var lastUsername: String { prefs.string(PrefKey.username) ?? "" }
    public var signedIn: Bool { screen == .main }
    /// The STOP exists only with a session in use: before it there is no server to stop.
    public var showsStop: Bool { screen == .main }

    public var skipMobileAndVpn: Bool {
        get { prefs.bool(PrefKey.skipMobileVpn) }
        set { prefs.set(newValue, PrefKey.skipMobileVpn); changed() }
    }

    /// The id of this installation (`ios-` and twelve hexadecimal digits, as the published app writes it): made once and kept.
    private var controllerId: String {
        if let kept = prefs.string(PrefKey.controllerId), kept.range(of: "^ios-[0-9a-f]{12}$", options: .regularExpression) != nil { return kept }
        let digits = Array("0123456789abcdef")
        let made = "ios-" + String((0..<12).map { _ in digits[Int.random(in: 0..<digits.count)] })
        prefs.set(made, PrefKey.controllerId)
        return made
    }

    private func makeClient(_ address: ServerAddress, useTls: Bool, transport: HttpTransport) -> HydraClient {
        HydraClient(address: address, transport: transport, tlsSettings: { [weak self] in self?.tlsSettings ?? TlsSettings() },
                    appVersion: appVersion, controllerId: controllerId, useTls: useTls)
    }

    private func bind(_ made: HydraClient) {
        made.tokenRenewer = { [weak self, weak made] in
            guard let self, let made else { return nil }
            return await self.renew(made)
        }
        client = made
    }

    // MARK: - Start, lock

    public func start() async {
        SessionStore.purgeOnFirstRun(secrets: secrets, prefs: prefs)
        tlsSettings = prefs.codable(TlsSettings.self, PrefKey.tls) ?? TlsSettings()
        pairingEnabled = prefs.bool(PrefKey.pairing)
        biometricEnabled = prefs.bool(PrefKey.biometric)
        chosenLanguage = prefs.string(PrefKey.language)
        savedServers = prefs.codable([SavedServer].self, PrefKey.savedServers) ?? []
        server = prefs.codable(SavedServer.self, PrefKey.server)
        guard let server, let token = sessions(server.address).token else {
            screen = prefs.bool(PrefKey.firstRunDone) || server != nil ? .login : .welcome
            return
        }
        await open(server, token: token)
    }

    /// Takes the saved session of a server into use, behind the lock when it is on.
    private func open(_ server: SavedServer, token: String) async {
        let made = makeClient(server.address, useTls: server.useTls, transport: transport)
        made.authToken = token
        bind(made)
        if biometricEnabled {
            if auth.isAvailable {
                screen = .locked
                return
            }
            // The lock is on and cannot be shown: it fails closed, the saved session is dropped.
            dropSession()
            return
        }
        await enterMain()
    }

    /// Uses the session this phone keeps of a saved server, without the password.
    public func resume(_ saved: SavedServer) async {
        guard screen == .login, !signingIn, let token = sessions(saved.address).token else { return }
        generation += 1
        message = nil
        secondFactor = .none
        server = saved
        prefs.setCodable(saved, PrefKey.server)
        await open(saved, token: token)
    }

    /// Goes back to the sign-in keeping this server's session, to use another one. Refused while a STOP is on its way or without answer.
    @discardableResult
    public func leaveServer() -> Bool {
        guard screen == .main else { return false }
        guard stopsInFlight == 0, !stopUnconfirmed else {
            message = Message("errStopNotConfirmed")
            return false
        }
        closeConnection()
        message = nil
        screen = .login
        return true
    }

    private func closeConnection() {
        generation += 1
        client?.authToken = nil
        client = nil
        roster = []
        linkOk = false
        stopResult = nil
        stopUnconfirmed = false
        secondFactor = .none
    }

    private func keep(_ entry: SavedServer) {
        let before = savedServers
        savedServers = SavedServer.remember(entry, in: savedServers)
        // a server that falls off the list takes its session with it
        for old in before where !savedServers.contains(where: { $0.id == old.id }) { sessions(old.address).clear() }
        prefs.setCodable(savedServers, PrefKey.savedServers)
    }

    public func finishFirstRun() {
        prefs.set(true, PrefKey.firstRunDone)
        screen = .login
    }

    public func unlock(reason: String) async {
        guard screen == .locked else { return }
        if await auth.authenticate(reason: reason) {
            message = nil
            await enterMain()
        } else {
            message = Message("biometricAuthFailed")
        }
    }

    public func setBiometric(_ on: Bool, reason: String) async {
        if on {
            guard auth.isAvailable else { message = Message("biometricNeedsSetup"); return }
            guard await auth.authenticate(reason: reason) else { message = Message("biometricAuthFailed"); return }
        }
        biometricEnabled = on
        prefs.set(on, PrefKey.biometric)
    }

    private func enterMain() async {
        screen = .main
        await refresh()
    }

    // MARK: - Sign-in and sign-out

    public func login(host: String, port: String, username: String, password: String, code: String) async {
        guard !signingIn else { return }
        guard let address = ServerAddress.parse(host: host, port: port) else { message = Message("errBadAddress"); return }
        signingIn = true
        defer { signingIn = false }
        message = nil
        generation += 1
        let mine = generation
        // A server that already answered over TLS is not asked in the clear again.
        let knownTls = (savedServers + [server].compactMap { $0 }).contains { $0.address.key == address.key && $0.useTls }
        let made = makeClient(address, useTls: knownTls, transport: transport)
        do {
            let user = username.trimmingCharacters(in: .whitespaces)
            let grant = try await made.login(username: user, password: password, totp: secondFactor == .none ? nil : code)
            guard mine == generation else { return }
            made.authToken = grant.token
            bind(made)
            sessions(address).save(token: grant.token, username: user, refreshToken: grant.refreshToken, replaceRefreshToken: true)
            let known = savedServers.first { $0.address.key == address.key }
            let entry = SavedServer(address: address, name: known?.name ?? address.host, useTls: made.usesTls)
            server = entry
            keep(entry)
            prefs.setCodable(entry, PrefKey.server)
            prefs.set(user, PrefKey.username)
            prefs.set(true, PrefKey.firstRunDone)
            secondFactor = .none
            await enterMain()
        } catch let need as SecondFactorRequired {
            if let seconds = need.waitSeconds {
                secondFactor = .wait(seconds: seconds)
            } else {
                secondFactor = need.wrongCode ? .wrong : .needed
            }
        } catch TransportError.tls {
            message = Message("errTlsFailed")
        } catch is ApiError {
            message = Message("errLoginFailed")
        } catch {
            message = Message("errNoAnswer")
        }
    }

    /// Takes a server off the list, with its session.
    public func forget(_ saved: SavedServer) {
        sessions(saved.address).clear()
        savedServers.removeAll { $0.id == saved.id }
        prefs.setCodable(savedServers, PrefKey.savedServers)
        if server?.id == saved.id {
            server = nil
            prefs.set(nil, PrefKey.server)
        }
    }

    public func logout() {
        let leaving = client
        let refresh = leaving.flatMap { sessions($0.address).refreshToken }
        dropSession()
        if let leaving, let refresh {
            leaving.authToken = nil
            Task { await leaving.logoutRemote(refresh) }
        }
    }

    private func dropSession(_ reason: Message? = nil) {
        if let address = client?.address { sessions(address).clear() }
        closeConnection()
        message = reason
        screen = .login
    }

    private func renew(_ of: HydraClient) async -> String? {
        if let renewal, renewal.client === of { return await renewal.task.value }
        let task = Task { [weak self] () -> String? in
            guard let self, of === self.client else { return nil }
            let kept = self.sessions(of.address)
            guard let refresh = kept.refreshToken, let user = kept.username else { return nil }
            let mine = self.generation
            guard let grant = try? await of.refresh(refresh), mine == self.generation else { return nil }
            of.authToken = grant.token
            kept.save(token: grant.token, username: user, refreshToken: grant.refreshToken, replaceRefreshToken: false)
            return grant.token
        }
        renewal = (of, task)
        let token = await task.value
        if renewal?.client === of { renewal = nil }
        return token
    }

    // MARK: - Reading

    /// Reads the state of the installation (the robots, which the STOP needs if the global route is not available).
    public func refresh() async {
        guard screen == .main, let client else { return }
        let mine = generation
        do {
            let settings = try await client.settings()
            guard mine == generation else { return }
            roster = RosterRobot.list(settings: settings)
            linkOk = true
        } catch let error as ApiError where error.isSessionProblem {
            guard mine == generation else { return }
            dropSession(Message("errSessionEnded"))
        } catch {
            guard mine == generation else { return }
            linkOk = false
        }
    }

    // MARK: - STOP

    /// Stops every robot at once. One tap, no confirmation; a second tap while one is on the way sends another.
    public func stopAll() async {
        guard showsStop, let client else { return }
        let mine = generation
        stopsInFlight += 1
        defer { stopsInFlight -= 1 }
        let outcome = await GlobalStop.run(client: client, roster: roster, sequence: sequence)
        guard mine == generation else { return }
        switch outcome {
        case .answered(let result):
            stopUnconfirmed = false
            stopResult = result
            await refresh()
        case .unconfirmed(let sessionEnded):
            if sessionEnded {
                dropSession(Message("errStopSessionEnded"))
            } else {
                stopResult = nil
                stopUnconfirmed = true
            }
        }
    }

    public func dismissStopResult() { stopResult = nil }

    // MARK: - Settings of the connection, pairing, language

    public func setTls(_ value: TlsSettings) {
        var clean = value
        if !clean.allowPlainHttp { clean.allowPlainRemote = false }
        tlsSettings = clean
        prefs.setCodable(clean, PrefKey.tls)
    }

    public func setPairing(_ on: Bool) {
        pairingEnabled = on
        prefs.set(on, PrefKey.pairing)
        if !on { pendingPairing = nil }
    }

    /// A pairing link that was pasted, scanned or opened. Nothing is read while pairing is off, and nothing is kept before the person says yes.
    public func receivePairing(_ text: String) {
        guard pairingEnabled else { return }
        switch PairingLink.parse(text) {
        case .success(let offer):
            message = nil
            pendingPairing = offer
        case .failure(let problem):
            message = Message(problem.textKey)
        }
    }

    public func confirmPairing() {
        guard let offer = pendingPairing else { return }
        pendingPairing = nil
        // a paired server is reached over TLS and must present this certificate
        // a session given before this certificate was named is not sent to it: the person signs in again
        if signedIn, client?.address.key == offer.address.key { dropSession() }
        sessions(offer.address).clear()
        setTls(tlsSettings.withPin(offer.fingerprint, for: offer.address))
        keep(SavedServer(address: offer.address, name: offer.name, useTls: true))
        prefs.set(true, PrefKey.firstRunDone)
        pairedAddress = offer.address
        if screen == .welcome { screen = .login }
    }

    public func dismissPairing() { pendingPairing = nil }

    public func setLanguage(_ code: String?) {
        chosenLanguage = code
        prefs.set(code, PrefKey.language)
    }

    // MARK: - Discovery

    /// Asks one host whether it is a HYDRA-UMC server. No session travels with the question.
    public func probe(host: String, port: Int = ServerAddress.defaultPort) async -> FoundServer? {
        let address = ServerAddress(host: host, port: port)
        let asker = makeClient(address, useTls: false, transport: discoveryTransport)
        guard let info = await asker.hydraInfo().info else { return nil }
        return FoundServer(address: address, info: info, useTls: asker.usesTls)
    }
}
