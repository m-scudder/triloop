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
        let app = onboardingApp()
        app.launch()

        let todayTab = app.tabBars.buttons["Today"]
        let setUpButton = app.buttons["Build My Plan"]

        XCTAssertTrue(
            todayTab.waitForExistence(timeout: 10) || setUpButton.waitForExistence(timeout: 10),
            "Launch showed neither the training tabs nor onboarding."
        )
    }

    @MainActor
    func testConsolidatedOnboardingCreatesFirstWeek() throws {
        let app = onboardingApp()
        app.launch()
        XCTAssertTrue(app.buttons["Build My Plan"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Onboarding welcome")
        app.buttons["Build My Plan"].tap()
        XCTAssertTrue(app.staticTexts["What are you training for?"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Where are you starting?"].exists)
        app.buttons["startingPoint.running"].tap()
        let runChoice = app.buttons["I can run continuously for around 10 minutes"]
        reveal(runChoice, in: app)
        runChoice.tap()
        app.buttons["explanation.done"].tap()
        XCTAssertTrue(app.staticTexts["10 min continuous"].exists)
        attachScreenshot(app, name: "Onboarding starting point")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["When can you train?"].exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["Monday"].tap()
        app.buttons["Wednesday"].tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        attachScreenshot(app, name: "Onboarding schedule")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Anything we should consider?"].exists)
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Connect your training"].exists)
        let skip = app.buttons["Not Now"]
        reveal(skip, in: app)
        skip.tap()
        XCTAssertTrue(app.staticTexts["Your first week"].waitForExistence(timeout: 5))
        let start = app.buttons["Start My Plan"]
        XCTAssertTrue(start.isEnabled)
        attachScreenshot(app, name: "Onboarding first week")
        start.tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testInfoDisclosurePreservesBuilderValidation() throws {
        let app = densityApp()
        app.launch()
        openBuilder(app)
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        XCTAssertTrue(app.staticTexts["Before you can save"].exists)
        let info = app.buttons["info.rpe"]
        reveal(info, in: app)
        XCTAssertTrue(info.label.contains("perceived effort"))
        info.tap()
        XCTAssertTrue(app.staticTexts["explanation.heading"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Effort explanation")
        app.buttons["explanation.done"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        attachScreenshot(app, name: "Builder validation")
    }

    @MainActor
    func testWeeklyWhyKeepsPainVisible() throws {
        let app = densityApp()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Progress"].tap()
        let history = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "History and totals")
        ).firstMatch
        reveal(history, in: app)
        history.tap()
        let week = app.staticTexts["Week 1"]
        reveal(week, in: app)
        week.tap()
        let pain = app.staticTexts["Pain reported at 3/10"]
        XCTAssertTrue(pain.waitForExistence(timeout: 5))
        let why = app.buttons["why.Why Running: Reduce"]
        reveal(why, in: app)
        attachScreenshot(app, name: "Weekly analysis with visible pain")
        why.tap()
        XCTAssertTrue(app.staticTexts["explanation.heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Highest reported pain"].exists)
        attachScreenshot(app, name: "Weekly decision evidence")
        app.buttons["explanation.done"].tap()
        XCTAssertTrue(pain.exists)
    }

    @MainActor
    func testExplanationAtAccessibilityTextSize() throws {
        let app = densityApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openBuilder(app)
        let info = app.buttons["info.rpe"]
        reveal(info, in: app)
        info.tap()
        XCTAssertTrue(app.staticTexts["explanation.heading"].waitForExistence(timeout: 5))
        app.swipeUp()
        attachScreenshot(app, name: "Explanation accessibility text")
        XCTAssertTrue(app.buttons["explanation.done"].isHittable)
        try app.performAccessibilityAudit(for: [.textClipped, .dynamicType])
        app.buttons["explanation.done"].tap()
    }

    /// Plan starts with the information needed to choose a session. The edit
    /// controls are still present in the full detail, behind one disclosure.
    @MainActor
    func testPlanSummaryKeepsWorkoutOptionsAvailable() throws {
        let app = densityApp()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Plan"].tap()

        let viewWorkout = app.buttons["View workout"]
        XCTAssertTrue(viewWorkout.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Move Workout"].exists)
        attachScreenshot(app, name: "Plan session summary")

        viewWorkout.tap()
        let options = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Workout options")
        ).firstMatch
        reveal(options, in: app)
        options.tap()
        let moveWorkout = app.buttons["Move Workout"]
        reveal(moveWorkout, in: app)
        attachScreenshot(app, name: "Workout options disclosed")
    }

    @MainActor
    private func densityApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--content-density-ui-tests",
            "-automaticallyImportWorkouts", "NO",
            "-automaticallyScheduleWorkouts", "NO"
        ]
        return app
    }

    @MainActor
    private func onboardingApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--onboarding-ui-tests",
            "-automaticallyImportWorkouts", "NO",
            "-automaticallyScheduleWorkouts", "NO"
        ]
        return app
    }

    @MainActor
    private func openBuilder(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Plan"].tap()
        app.buttons["Workouts"].tap()
        attachScreenshot(app, name: "Workout library")
        app.buttons["Create workout"].tap()
        XCTAssertTrue(app.navigationBars["New Workout"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Could not reveal \(element)")
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
