import XCTest

/// "What happened" in the control sheet: the demo box's morning (a 3 s
/// dispatch block at a restart, the battery taking 1.2 kW of the 4.2 kW
/// asked from 06:14, the charger going quiet) stays in the sheet after it
/// passed. Photographs the sheet when asked:
///
///     TEST_RUNNER_FTW_SHOTS=1 xcodebuild test … \
///       -only-testing:FTWUITests/ControlJournalTour -resultBundlePath journal.xcresult
///     xcrun xcresulttool export attachments --path journal.xcresult --output-path journal
///
/// Light or dark is the simulator's own setting; `FTW_LANG=sv` for Swedish.
final class ControlJournalTour: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testThePassedWarningStaysInTheSheet() throws {
        let env = ProcessInfo.processInfo.environment
        let lang = env["FTW_LANG"] ?? "en"
        let app = XCUIApplication()
        app.launchArguments = [
            "-FTWDemo", "YES", "-FTWTab", "now", "-FTWSheet", "control", "-appearance", "system",
            "-AppleLanguages", "(\(lang))", "-AppleLocale", lang == "sv" ? "sv_SE" : "en_US",
            "-UIPreferredContentSizeCategoryName", env["FTW_TEXT"] ?? "UICTContentSizeCategoryL",
        ]
        app.launch()
        let summary = app.descendants(matching: .any)["control.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "the control sheet did not open")
        let blocked = app.staticTexts[lang == "sv" ? "FTW styrde inte" : "FTW was not in control"]
        // The sheet opens half way: pull it up to see the whole list.
        let grabber = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.49))
        grabber.press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        Thread.sleep(forTimeInterval: 2)
        guard env["FTW_SHOTS"] == "1" else {
            XCTAssertTrue(blocked.waitForExistence(timeout: 10), "the journal's dispatch line is missing")
            return
        }
        shoot(app, "journal-top")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(blocked.waitForExistence(timeout: 10), "the journal's dispatch line is missing")
        shoot(app, "journal-list")
    }

    @MainActor
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
