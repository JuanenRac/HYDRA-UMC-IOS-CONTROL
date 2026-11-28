// HYDRA-UMC-IOS-CONTROL - the help and the diagnostic report.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest
@testable import HydraCore

@MainActor
final class HelpTests: XCTestCase {
    func testEveryTopicHasItsTextsInEveryLanguage() {
        for language in Translator.languages {
            let table = Translator.load(language)
            for topic in HelpTopic.allCases {
                for key in [topic.titleKey] + HelpLevel.texts.map({ topic.textKey($0) }) {
                    XCTAssertFalse((table[key] ?? "").isEmpty, "\(language) \(key)")
                }
            }
            for level in HelpLevel.allCases { XCTAssertNotNil(table[level.labelKey], "\(language) \(level)") }
        }
    }

    func testTheSearchAsksForEveryWord() {
        let english = Translator(language: "en")
        XCTAssertEqual(HelpTopic.search("", { english($0) }), HelpTopic.allCases)
        XCTAssertEqual(HelpTopic.search("MJPEG stream", { english($0) }), [.cameras])
        XCTAssertEqual(HelpTopic.search("MJPEG Keychain", { english($0) }), [])
        XCTAssertEqual(HelpTopic.of(.alerts), .alerts)
        XCTAssertEqual(HelpLevel.all.shown, HelpLevel.texts)
    }

    func testTheLevelIsKept() async {
        let rig = Rig()
        XCTAssertEqual(rig.controller.helpLevel, .basic)
        rig.controller.helpLevel = .technical
        XCTAssertEqual(Rig(prefs: rig.prefs).controller.helpLevel, .technical)
    }

    func testTheDiagnosticNamesNobodyAndNothing() async {
        let rig = Rig()
        await rig.signIn()
        rig.controller.serverMessage(title: "Sample message", body: "")
        let report = rig.controller.diagnostic(appVersion: "0.0.1", system: "iOS test")
        XCTAssertTrue(report.contains("robots: 2"))
        XCTAssertTrue(report.contains("notices kept: 1"))
        for secret in ["192.168", "3000", "operator", "t1", "r1", "sample-pass", "A1", "demo-cell", "Sample message"] {
            XCTAssertNil(report.range(of: "\\b\(NSRegularExpression.escapedPattern(for: secret))\\b", options: .regularExpression), secret)
        }
    }
}
