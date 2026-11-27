// HYDRA-UMC-IOS-CONTROL - the STOP on a simulator: present and pressable on every tab, with a sheet and with an alert open; the pictures of the screens.
// The app runs with the pretend server of the debug build: nothing leaves the simulator.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest

final class StopUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ screen: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hydraDemo", screen, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        picture.name = name
        picture.lifetime = .keepAlways
        add(picture)
        if let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        }
    }

    private func topStop(_ app: XCUIApplication) -> XCUIElement { app.buttons["stop-all"] }

    /// Presses the top STOP, sees the answer of the robots and closes it.
    private func pressAndRead(_ app: XCUIApplication, _ where_: String) {
        let stop = topStop(app)
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "no STOP \(where_)")
        XCTAssertTrue(stop.isHittable, "STOP not pressable \(where_)")
        stop.tap()
        XCTAssertTrue(app.staticTexts["stop-result"].waitForExistence(timeout: 10), "no answer of the STOP \(where_)")
    }

    private func closeResult(_ app: XCUIApplication) {
        app.buttons["stop-result-close"].tap()
        XCTAssertTrue(app.staticTexts["stop-result"].waitForNonexistence(timeoutSeconds: 5))
    }

    func testNoStopBeforeSigningIn() {
        let app = launch("login")
        XCTAssertTrue(app.buttons["login-submit"].waitForExistence(timeout: 20))
        XCTAssertFalse(topStop(app).exists)
        shot("01_login")
        app.buttons["login-help"].tap()
        XCTAssertTrue(app.buttons["sheet-close"].waitForExistence(timeout: 5))
        XCTAssertFalse(topStop(app).exists)
    }

    func testFirstUse() {
        let app = launch("welcome")
        XCTAssertTrue(app.buttons["first-by-hand"].waitForExistence(timeout: 20))
        shot("02_first_use")
        app.buttons["first-by-hand"].tap()
        XCTAssertTrue(app.buttons["login-submit"].waitForExistence(timeout: 5))
    }

    func testStopOnEveryTabAndTheRoundOneInControl() {
        let app = launch("main")
        XCTAssertTrue(topStop(app).waitForExistence(timeout: 20))
        shot("03_home")
        for tab in ["Home", "Control", "Cameras", "Alerts", "More"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(topStop(app).isHittable, "STOP not pressable on \(tab)")
            XCTAssertEqual(app.buttons["stop-all-large"].exists, tab == "Control", tab)
            if tab == "Control" { shot("04_control") }
        }
        shot("06_more")
        app.tabBars.buttons["Control"].tap()
        app.buttons["stop-all-large"].tap()
        XCTAssertTrue(app.staticTexts["stop-result"].waitForExistence(timeout: 10))
        shot("07_stop_result")
        closeResult(app)
    }

    func testStopOverASheet() {
        let app = launch("main")
        XCTAssertTrue(topStop(app).waitForExistence(timeout: 20))
        app.tabBars.buttons["More"].tap()
        app.buttons["more-about"].tap()
        XCTAssertTrue(app.buttons["sheet-close"].waitForExistence(timeout: 5))
        shot("08_stop_over_sheet")
        pressAndRead(app, "over a sheet")
        closeResult(app)
        XCTAssertTrue(app.buttons["sheet-close"].isHittable, "the sheet can still be closed")
        app.buttons["sheet-close"].tap()
    }

    func testStopOverAnAlert() {
        let app = launch("main")
        XCTAssertTrue(topStop(app).waitForExistence(timeout: 20))
        app.tabBars.buttons["More"].tap()
        let signOut = app.buttons["more-signout"]
        if !signOut.isHittable { app.swipeUp() }
        signOut.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        shot("09_stop_over_alert")
        pressAndRead(app, "over an alert")
        XCTAssertTrue(app.alerts.firstMatch.exists, "the STOP does not answer the question of the alert")
    }

    func testAStopWithoutAnswerStaysSaid() {
        let app = launch("main", extra: ["-hydraDemoStopFails"])
        XCTAssertTrue(topStop(app).waitForExistence(timeout: 20))
        topStop(app).tap()
        XCTAssertTrue(app.staticTexts["stop-unconfirmed"].waitForExistence(timeout: 10))
        shot("10_stop_not_confirmed")
        app.tabBars.buttons["More"].tap()
        XCTAssertTrue(app.staticTexts["stop-unconfirmed"].exists)
        XCTAssertTrue(topStop(app).isHittable)
        XCTAssertTrue(app.buttons["stop-retry"].isHittable)
    }
}

private extension XCUIElement {
    func waitForNonexistence(timeoutSeconds: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter().wait(for: [gone], timeout: timeoutSeconds) == .completed
    }
}
