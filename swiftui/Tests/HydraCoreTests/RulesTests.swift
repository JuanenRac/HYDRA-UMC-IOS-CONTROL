// HYDRA-UMC-IOS-CONTROL - the certificate rules and the eight language tables.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest
@testable import HydraCore

final class RulesTests: XCTestCase {
    /// A minimal certificate shell in DER with the given validity: enough for the reader of the dates.
    private func certificate(from: String, to: String) -> Data {
        func element(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] { [tag, UInt8(content.count)] + content }
        let validity = element(0x30, element(0x17, Array(from.utf8)) + element(0x17, Array(to.utf8)))
        let tbs = element(0x30, element(0xa0, element(0x02, [2])) + element(0x02, [1]) + element(0x30, []) + element(0x30, []) + validity)
        return Data(element(0x30, tbs))
    }

    func testAPinnedCertificateMustMatchAndBeInDate() {
        let der = certificate(from: "260101000000Z", to: "270101000000Z")
        let pin = String(repeating: "0f", count: 32)
        let inside = Date(timeIntervalSince1970: 1_780_000_000)   // 2026
        XCTAssertNotNil(CertificateDates.window(der: der))
        XCTAssertTrue(CertificateDates.pinMatches(pin: pin, sha256: pin, der: der, now: inside))
        XCTAssertTrue(CertificateDates.pinMatches(pin: "0F:" + String(repeating: "0f", count: 31), sha256: pin, der: der, now: inside))
        XCTAssertFalse(CertificateDates.pinMatches(pin: pin, sha256: String(repeating: "0e", count: 32), der: der, now: inside))
        XCTAssertFalse(CertificateDates.pinMatches(pin: pin, sha256: pin, der: der, now: Date(timeIntervalSince1970: 1_700_000_000)))
        XCTAssertFalse(CertificateDates.pinMatches(pin: pin, sha256: pin, der: der, now: Date(timeIntervalSince1970: 1_900_000_000)))
        XCTAssertFalse(CertificateDates.pinMatches(pin: pin, sha256: pin, der: Data([1, 2, 3]), now: inside))
        XCTAssertFalse(CertificateDates.pinMatches(pin: "", sha256: "", der: der, now: inside))
    }

    func testLocalHosts() {
        for host in ["192.168.1.2", "10.0.0.1", "172.16.0.1", "169.254.1.1", "cell", "pi.local", "box.lan", "::1", "fe80::1"] {
            XCTAssertTrue(TlsPolicy.isLocalHost(host), host)
        }
        for host in ["8.8.8.8", "172.32.0.1", "example.org", "999.999.999.999", ""] {
            XCTAssertFalse(TlsPolicy.isLocalHost(host), host)
        }
    }

    func testAddresses() {
        XCTAssertEqual(ServerAddress.parse(host: "[fe80::1]", port: "3000")?.baseUrl(tls: true), "https://[fe80::1]:3000")
        for (host, port) in [("", "3000"), ("a b", "3000"), ("u@host", "3000"), ("host/x", "3000"), ("host", "0"), ("host", "abc"), ("300.1.1.1", "80")] {
            XCTAssertNil(ServerAddress.parse(host: host, port: port), "\(host):\(port)")
        }
    }

    func testTheEightTablesHaveTheSameKeysAndHoles() {
        let english = Translator.load("en")
        XCTAssertGreaterThan(english.count, 100)
        func holes(_ text: String) -> [String] {
            var found: [String] = []
            var rest = Substring(text)
            while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
                found.append(String(rest[open...close]))
                rest = rest[rest.index(after: close)...]
            }
            return found.sorted()
        }
        for language in Translator.languages {
            let table = Translator.load(language)
            XCTAssertEqual(Set(table.keys), Set(english.keys), language)
            for (key, text) in table {
                XCTAssertFalse(text.isEmpty, "\(language) \(key)")
                XCTAssertEqual(holes(text), holes(english[key] ?? ""), "\(language) \(key)")
            }
        }
        for tab in MainTab.allCases { XCTAssertNotNil(english[tab.titleKey]) }
        let problems: [PairingProblem] = [.empty, .notAPairingLink, .badHost, .badPort, .badFingerprint, .missingFingerprint, .badName]
        for problem in problems { XCTAssertNotNil(english[problem.textKey]) }
    }

    func testTheLanguageOfTheApp() {
        XCTAssertEqual(Translator.resolve(chosen: "ja", preferred: ["es-ES"]), "ja")
        XCTAssertEqual(Translator.resolve(chosen: nil, preferred: ["nl-NL", "pt-PT"]), "pt")
        XCTAssertEqual(Translator.resolve(chosen: "xx", preferred: ["nl"]), "en")
        XCTAssertEqual(Translator(language: "es")("loginCodeWait", ["seconds": "9"]).contains("9"), true)
    }
}
