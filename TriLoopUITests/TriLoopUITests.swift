import XCTest

final class TriLoopUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A launch lands somewhere usable.
    ///
    /// Since onboarding was added, the destination depends on stored state: a
    /// fresh install opens setup, an onboarded one opens the tabs. The test
    /// accepts either rather than assuming a tab bar that a first launch will
    /// never show.
    @MainActor
    func testLaunchShowsSetupOrTabs() throws {
        let app = XCUIApplication()
        app.launch()

        let todayTab = app.tabBars.buttons["Today"]
        let setUpButton = app.buttons["Set Up My Training"]

        XCTAssertTrue(
            todayTab.waitForExistence(timeout: 10) || setUpButton.waitForExistence(timeout: 10),
            "Launch showed neither the training tabs nor onboarding."
        )
    }
}
