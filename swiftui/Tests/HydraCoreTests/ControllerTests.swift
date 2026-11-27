// HYDRA-UMC-IOS-CONTROL - first use, sign-in with its second factor, the saved session and its lock, TLS rules and pairing.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest
@testable import HydraCore

@MainActor
final class ControllerTests: XCTestCase {
    private let pin = String(repeating: "ab", count: 32)

    func testFirstUseThenSignIn() async {
        let rig = Rig()
        await rig.controller.start()
        XCTAssertEqual(rig.controller.screen, .welcome)
        rig.controller.finishFirstRun()
        XCTAssertEqual(rig.controller.screen, .login)
        await rig.controller.login(host: " 192.168.1.50 ", port: "3000", username: "operator", password: "sample-pass", code: "")
        XCTAssertEqual(rig.controller.screen, .main)
        XCTAssertEqual(rig.controller.robots.map(\.name), ["A1", "A2"])
        XCTAssertTrue(rig.controller.linkOk)
        XCTAssertEqual(rig.controller.savedServers.map(\.address.key), ["192.168.1.50:3000"])
        XCTAssertEqual(rig.secrets.values["hydra_token|192.168.1.50:3000"], "t1")
        // the password is nowhere on the phone
        XCTAssertFalse((Array(rig.prefs.values.values) + Array(rig.secrets.values.values)).contains { $0.contains("sample-pass") })
    }

    func testEverythingGoesOverTlsByDefault() async {
        let rig = Rig({ request in
            if request.url.hasPrefix("https://") { throw TransportError.tls }
            return reply(200, infoJson)
        })
        await rig.signIn()
        XCTAssertEqual(rig.controller.screen, .welcome)
        XCTAssertEqual(rig.controller.message?.key, "errTlsFailed")
        XCTAssertFalse(rig.transport.requests.contains { $0.url.hasPrefix("http://") })
    }

    func testPlainHttpOnlyWhenAllowedAndNeverWithAPin() async {
        @Sendable func plainOnly(_ request: HttpRequest) async throws -> HttpResponse {
            if request.url.hasPrefix("https://") { throw TransportError.tls }
            return try await healthy(HttpRequest(method: request.method, url: request.url.replacingOccurrences(of: "http://", with: "https://"), headers: request.headers, timeout: request.timeout))
        }
        let allowed = Rig(plainOnly)
        await allowed.controller.start()
        allowed.controller.setTls(TlsSettings(allowPlainHttp: true))
        await allowed.controller.login(host: "192.168.1.50", port: "3000", username: "u", password: "p", code: "")
        XCTAssertEqual(allowed.controller.screen, .main)
        XCTAssertEqual(allowed.controller.server?.useTls, false)

        let pinned = Rig(plainOnly)
        await pinned.controller.start()
        pinned.controller.setTls(TlsSettings(allowPlainHttp: true).withPin(pin, for: ServerAddress(host: "192.168.1.50", port: 3000)))
        await pinned.controller.login(host: "192.168.1.50", port: "3000", username: "u", password: "p", code: "")
        XCTAssertNotEqual(pinned.controller.screen, .main)
        XCTAssertFalse(pinned.transport.requests.contains { $0.url.hasPrefix("http://") })

        let outside = Rig(plainOnly)
        await outside.controller.start()
        outside.controller.setTls(TlsSettings(allowPlainHttp: true))
        await outside.controller.login(host: "robots.example.org", port: "3000", username: "u", password: "p", code: "")
        XCTAssertFalse(outside.transport.requests.contains { $0.url.hasPrefix("http://") })
    }

    func testAServerSeenOverTlsIsNeverAskedInTheClearAgain() async {
        let rig = Rig()
        await rig.signIn()
        rig.controller.setTls(TlsSettings(allowPlainHttp: true))
        rig.controller.logout()
        rig.transport.answer = { request in
            if request.url.hasPrefix("https://") { throw TransportError.unreachable }
            return reply(200, infoJson)
        }
        let before = rig.transport.requests.count
        await rig.controller.login(host: "192.168.1.50", port: "3000", username: "u", password: "p", code: "")
        XCTAssertFalse(rig.transport.requests.dropFirst(before).contains { $0.url.hasPrefix("http://") })
        XCTAssertEqual(rig.controller.message?.key, "errNoAnswer")
    }

    func testSecondFactorAsksForTheCodeAndSendsItNormalized() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/login") {
                let code = HydraClient.object(request.body ?? Data())?["totp"] as? String
                if code == "123456" { return reply(200, loginJson) }
                return reply(401, #"{"totpRequired":true}"#)
            }
            return try await healthy(request)
        })
        await rig.signIn()
        XCTAssertEqual(rig.controller.secondFactor, .needed)
        await rig.controller.login(host: "192.168.1.50", port: "3000", username: "u", password: "p", code: "000000")
        XCTAssertEqual(rig.controller.secondFactor, .wrong)
        await rig.controller.login(host: "192.168.1.50", port: "3000", username: "u", password: "p", code: "123 456")
        XCTAssertEqual(rig.controller.screen, .main)
        XCTAssertEqual(rig.controller.secondFactor, SecondFactorStep.none)
    }

    func testTooManyCodesSaysHowLongToWait() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/login") { return reply(429, #"{"totpRequired":true}"#, headers: ["retry-after": "30"]) }
            return try await healthy(request)
        })
        await rig.signIn()
        XCTAssertEqual(rig.controller.secondFactor, .wait(seconds: 30))
    }

    func testASavedSessionComesBackAndALogoutErasesIt() async {
        let first = Rig()
        await first.signIn()
        let second = Rig(secrets: first.secrets, prefs: first.prefs)
        await second.controller.start()
        XCTAssertEqual(second.controller.screen, .main)
        second.controller.logout()
        XCTAssertEqual(second.controller.screen, .login)
        XCTAssertEqual(first.secrets.stored("hydra_token"), [])
        let third = Rig(secrets: first.secrets, prefs: first.prefs)
        await third.controller.start()
        XCTAssertEqual(third.controller.screen, .login)
    }

    func testALogoutWhoseDeleteFailsStaysLoggedOut() async {
        let first = Rig()
        await first.signIn()
        first.secrets.failDeletes = true
        first.controller.logout()
        let second = Rig(secrets: first.secrets, prefs: first.prefs)
        await second.controller.start()
        XCTAssertEqual(second.controller.screen, .login)
    }

    func testAFailedSecureWriteNeverFallsBackToPreferences() async {
        let secrets = MemorySecrets()
        secrets.failWrites = true
        let rig = Rig(secrets: secrets)
        await rig.signIn()
        XCTAssertEqual(rig.controller.screen, .main)
        XCTAssertTrue(secrets.values.isEmpty)
        XCTAssertFalse(rig.prefs.values.values.contains("t1"))
    }

    func testTheLockHoldsTheSessionUntilTheBiometricSucceeds() async {
        let first = Rig()
        await first.signIn()
        await first.controller.setBiometric(true, reason: "test")
        XCTAssertTrue(first.controller.biometricEnabled)
        let auth = FakeAuth()
        auth.succeeds = false
        let second = Rig(secrets: first.secrets, prefs: first.prefs, auth: auth)
        await second.controller.start()
        XCTAssertEqual(second.controller.screen, .locked)
        XCTAssertFalse(second.controller.showsStop)
        XCTAssertTrue(second.transport.requests.isEmpty)
        await second.controller.unlock(reason: "test")
        XCTAssertEqual(second.controller.screen, .locked)
        auth.succeeds = true
        await second.controller.unlock(reason: "test")
        XCTAssertEqual(second.controller.screen, .main)
    }

    func testTheLockFailsClosedWhenItCannotBeShown() async {
        let first = Rig()
        await first.signIn()
        await first.controller.setBiometric(true, reason: "test")
        let auth = FakeAuth()
        auth.isAvailable = false
        let second = Rig(secrets: first.secrets, prefs: first.prefs, auth: auth)
        await second.controller.start()
        XCTAssertEqual(second.controller.screen, .login)
        XCTAssertEqual(first.secrets.stored("hydra_token"), [])
    }

    func testTheLockIsNotTurnedOnWithoutProvingWhoYouAre() async {
        let auth = FakeAuth()
        auth.succeeds = false
        let rig = Rig(auth: auth)
        await rig.controller.start()
        await rig.controller.setBiometric(true, reason: "test")
        XCTAssertFalse(rig.controller.biometricEnabled)
        XCTAssertEqual(auth.asked, 1)
    }

    /// Two servers, each giving its own token: whatever is done, a token only travels to the server that gave it.
    @Sendable private static func twoServers(_ request: HttpRequest) async throws -> HttpResponse {
        let name = URL(string: request.url)?.host == "192.168.1.50" ? "a" : "b"
        if request.url.hasSuffix("/api/login") { return reply(200, "{\"success\":true,\"token\":\"token-\(name)\",\"refreshToken\":\"refresh-\(name)\"}") }
        return try await healthy(request)
    }

    private func assertNothingCrossed(_ rig: Rig, file: StaticString = #filePath, line: UInt = #line) {
        for request in rig.transport.requests {
            guard let sent = request.headers["Authorization"] else { continue }
            let name = URL(string: request.url)?.host == "192.168.1.50" ? "a" : "b"
            XCTAssertEqual(sent, "Bearer token-\(name)", request.url, file: file, line: line)
        }
    }

    func testEachSavedServerKeepsItsOwnSession() async {
        let rig = Rig({ try await ControllerTests.twoServers($0) })
        await rig.signIn()
        XCTAssertTrue(rig.controller.leaveServer())
        await rig.controller.login(host: "192.168.1.61", port: "3000", username: "u", password: "p", code: "")
        XCTAssertEqual(rig.controller.savedServers.count, 2)
        XCTAssertTrue(rig.controller.savedServers.allSatisfy { rig.controller.hasSession($0) })
        XCTAssertTrue(rig.controller.leaveServer())
        XCTAssertFalse(rig.controller.showsStop)
        let first = rig.controller.savedServers.first { $0.address.host == "192.168.1.50" }!
        await rig.controller.resume(first)
        XCTAssertEqual(rig.controller.screen, .main)
        await rig.controller.stopAll()
        XCTAssertEqual(rig.transport.requests.last { $0.url.hasSuffix("/api/stop-all") }?.url, "https://192.168.1.50:3000/api/stop-all")
        assertNothingCrossed(rig)
        // signing out of one server leaves the other session
        rig.controller.logout()
        XCTAssertFalse(rig.controller.hasSession(first))
        XCTAssertEqual(rig.secrets.stored("hydra_token"), ["token-b"])
        let other = rig.controller.savedServers.first { $0.address.host == "192.168.1.61" }!
        await rig.controller.resume(other)
        XCTAssertEqual(rig.controller.screen, .main)
        assertNothingCrossed(rig)
    }

    func testARestartUsesTheSessionOfTheLastServerOnly() async {
        let first = Rig({ try await ControllerTests.twoServers($0) })
        await first.signIn()
        first.controller.leaveServer()
        await first.controller.login(host: "192.168.1.61", port: "3000", username: "u", password: "p", code: "")
        let second = Rig({ try await ControllerTests.twoServers($0) }, secrets: first.secrets, prefs: first.prefs)
        await second.controller.start()
        XCTAssertEqual(second.controller.server?.address.host, "192.168.1.61")
        XCTAssertFalse(second.transport.requests.isEmpty)
        XCTAssertTrue(second.transport.requests.allSatisfy { $0.url.contains("192.168.1.61") })
        assertNothingCrossed(second)
    }

    func testAServerIsNotLeftWhileAStopIsNotConfirmed() async {
        let rig = Rig({ request in
            if request.url.hasSuffix("/api/stop-all") { throw TransportError.unreachable }
            return try await healthy(request)
        })
        await rig.signIn()
        await rig.controller.stopAll()
        XCTAssertFalse(rig.controller.leaveServer())
        XCTAssertEqual(rig.controller.screen, .main)
    }

    func testAForgottenServerAndAReinstallLeaveNoSession() async {
        let rig = Rig()
        await rig.signIn()
        let saved = rig.controller.savedServers[0]
        rig.controller.leaveServer()
        rig.controller.forget(saved)
        XCTAssertEqual(rig.secrets.stored("hydra_token"), [])
        await rig.controller.login(host: "192.168.1.50", port: "3000", username: "u", password: "p", code: "")
        // a new install has empty preferences and the Keychain of before
        let again = Rig(secrets: rig.secrets, prefs: MemoryPrefs())
        await again.controller.start()
        XCTAssertTrue(rig.secrets.values.isEmpty)
    }

    func testAPairingThatNamesACertificateDropsTheOldSessionOfThatAddress() async {
        let rig = Rig()
        await rig.signIn()
        let saved = rig.controller.savedServers[0]
        rig.controller.leaveServer()
        rig.controller.setPairing(true)
        rig.controller.receivePairing("hydra-umc://pair?host=192.168.1.50&port=3000&fp=\(pin)")
        XCTAssertTrue(rig.controller.hasSession(saved), "nothing changes before the person says yes")
        rig.controller.confirmPairing()
        XCTAssertFalse(rig.controller.hasSession(saved))
    }

    func testPairingIsOffByDefaultAndAsksBeforeKeeping() async {
        let link = "hydra-umc://pair?host=192.168.1.60&port=3000&fp=\(pin)&name=Cell%20one"
        let rig = Rig()
        await rig.controller.start()
        XCTAssertFalse(rig.controller.pairingEnabled)
        rig.controller.receivePairing(link)
        XCTAssertNil(rig.controller.pendingPairing)
        rig.controller.setPairing(true)
        rig.controller.receivePairing(link)
        XCTAssertEqual(rig.controller.pendingPairing?.name, "Cell one")
        XCTAssertTrue(rig.controller.tlsSettings.pins.isEmpty)
        rig.controller.confirmPairing()
        XCTAssertEqual(rig.controller.tlsSettings.pin(for: ServerAddress(host: "192.168.1.60", port: 3000)), pin)
        XCTAssertEqual(rig.controller.pairedAddress?.host, "192.168.1.60")
        XCTAssertEqual(rig.controller.screen, .login)
    }

    func testPairingLinkRefusals() {
        func problem(_ text: String) -> PairingProblem? {
            if case .failure(let found) = PairingLink.parse(text) { return found }
            return nil
        }
        XCTAssertEqual(problem(""), .empty)
        XCTAssertEqual(problem("https://example.org"), .notAPairingLink)
        XCTAssertEqual(problem("hydra-umc://pair?port=3000&fp=\(pin)"), .missingHost)
        XCTAssertEqual(problem("hydra-umc://pair?host=a%2Fb&port=3000&fp=\(pin)"), .badHost)
        XCTAssertEqual(problem("hydra-umc://pair?host=pi&port=70000&fp=\(pin)"), .badPort)
        XCTAssertEqual(problem("hydra-umc://pair?host=pi&port=3000"), .missingFingerprint)
        XCTAssertEqual(problem("hydra-umc://pair?host=pi&port=3000&fp=12"), .badFingerprint)
        XCTAssertEqual(problem("hydra-umc://pair?host=pi&host=pj&port=3000&fp=\(pin)"), .repeatedField)
        XCTAssertEqual(problem("hydra-umc://pair?host=pi&port=3000&fp=\(pin)&name=%07"), .badName)
    }

    func testDiscoveryReadsOnlyTheIdentityAndSendsNoSession() async {
        let rig = Rig()
        await rig.controller.start()
        let found = await rig.controller.probe(host: "192.168.1.50")
        XCTAssertEqual(found?.name, "demo-cell")
        XCTAssertEqual(found?.robotCount, 2)
        XCTAssertTrue(rig.transport.requests.allSatisfy { $0.url.hasSuffix("/api/hydra-info") && $0.headers["Authorization"] == nil })
    }

    func testSubnetsSkipMobileAndVpnWhenAsked() {
        let interfaces = ["en0": ["192.168.1.7"], "pdp_ip0": ["10.20.30.40"], "utun3": ["100.64.0.2"], "lo0": ["127.0.0.1"]]
        XCTAssertEqual(Discovery.prefixes(interfaces: interfaces, lastHost: nil, skipMobileAndVpn: true), ["192.168.1"])
        XCTAssertEqual(Discovery.prefixes(interfaces: interfaces, lastHost: "10.0.5.9", skipMobileAndVpn: true), ["192.168.1", "10.0.5"])
        XCTAssertEqual(Discovery.prefixes(interfaces: interfaces, lastHost: nil, skipMobileAndVpn: false).count, 3)
        XCTAssertEqual(Discovery.prefixes(interfaces: [:], lastHost: nil, skipMobileAndVpn: false), ["192.168.1"])
        XCTAssertEqual(Discovery.hosts(prefix: "10.0.0").count, 254)
    }

    func testScanAsksEveryHostAndReportsTheServers() async {
        var found: [String] = []
        var asked = 0
        await Discovery.scan(hosts: Discovery.hosts(prefix: "10.0.0"), probe: { host in
            asked += 1
            return host.hasSuffix(".7") ? FoundServer(address: ServerAddress(host: host, port: 3000), name: host, robotCount: 1, useTls: true) : nil
        }, found: { found.append($0.address.host) })
        XCTAssertEqual(asked, 254)
        XCTAssertEqual(found, ["10.0.0.7"])
    }
}
