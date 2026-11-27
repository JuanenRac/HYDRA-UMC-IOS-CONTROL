// HYDRA-UMC-IOS-CONTROL - the STOP on a simulator: present and pressable on every tab, with a sheet and with an alert open; the pictures of the screens.
// "Pressable" is proven with a real touch at the place of the button on the screen and the answer it brings, whatever window is on top there.
// (`isHittable` of XCTest is not used for the top STOP: it answers false for a button of a second window that a touch does reach.)
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

    /// A touch of the screen at the middle of the element.
    private func touch(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The button keeps its size (a squashed STOP is easy to miss) and sits in the top corner.
    private func assertFullSize(_ stop: XCUIElement) {
        XCTAssertGreaterThanOrEqual(stop.frame.height, 44, "STOP is squashed: \(stop.frame)")
        XCTAssertGreaterThanOrEqual(stop.frame.width, 100, "STOP is narrow: \(stop.frame)")
        XCTAssertLessThan(stop.frame.minY, 100, "STOP is not at the top: \(stop.frame)")
    }

    /// Touches the top STOP and sees the answer of the robots.
    private func pressAndRead(_ app: XCUIApplication, _ where_: String) {
        let stop = topStop(app)
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "no STOP \(where_)")
        assertFullSize(stop)
        touch(stop)
        XCTAssertTrue(app.staticTexts["stop-result"].waitForExistence(timeout: 10), "no answer of the STOP \(where_)")
    }

    private func gone(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 8) == .completed
    }

    private func closeResult(_ app: XCUIApplication) {
        touch(app.buttons["stop-result-close"])
        XCTAssertTrue(gone(app.staticTexts["stop-result"]), "the answer does not close")
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
            XCTAssertEqual(app.buttons["stop-all-large"].exists, tab == "Control", tab)
            if tab == "Control" { shot("04_control") }
            if tab == "More" { shot("05_more") }
            pressAndRead(app, "on the tab \(tab)")
            closeResult(app)
        }
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
        XCTAssertTrue(app.buttons["sheet-close"].exists, "the STOP does not close the sheet")
        closeResult(app)
        app.buttons["sheet-close"].tap()
        XCTAssertTrue(gone(app.buttons["sheet-close"]), "the sheet can still be closed")
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
        shot("11_after_stop_over_alert")
        // Whatever the system does with the question, the STOP must never answer it with "yes": the person is still signed in.
        XCTAssertTrue(topStop(app).exists, "the STOP signed the person out")
        XCTAssertFalse(app.buttons["login-submit"].exists, "the STOP signed the person out")
        let kept = XCTAttachment(string: "alert still open after the STOP: \(app.alerts.firstMatch.exists)")
        kept.lifetime = .keepAlways
        add(kept)
        print("STOP_OVER_ALERT alert_still_open=\(app.alerts.firstMatch.exists) sheets=\(app.sheets.count) cancel=\(app.buttons["Cancel"].exists)")
    }

    /// The pretend server leaves the first STOP and its repeat without answer, then answers.
    func testAStopWithoutAnswerStaysSaidUntilOneIsAnswered() {
        let app = launch("main", extra: ["-hydraDemoStopFails"])
        XCTAssertTrue(topStop(app).waitForExistence(timeout: 20))
        touch(topStop(app))
        XCTAssertTrue(app.staticTexts["stop-unconfirmed"].waitForExistence(timeout: 10))
        shot("10_stop_not_confirmed")
        app.tabBars.buttons["More"].tap()
        XCTAssertTrue(app.staticTexts["stop-unconfirmed"].exists)
        touch(app.buttons["stop-retry"])
        XCTAssertTrue(app.staticTexts["stop-result"].waitForExistence(timeout: 10), "the retry was not answered")
        XCTAssertFalse(app.staticTexts["stop-unconfirmed"].exists)
    }
}
