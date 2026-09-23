import XCTest

final class AtheviaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsSetupOrTabs() throws {
        let app = onboardingApp()
        app.launch()

        let homeTab = app.tabBars.buttons["Home"]
        let setUpButton = app.buttons["Build My Plan"]

        XCTAssertTrue(
            homeTab.waitForExistence(timeout: 10) || setUpButton.waitForExistence(timeout: 10),
            "Launch showed neither the training tabs nor onboarding."
        )
    }

    @MainActor
    func testConsolidatedOnboardingCreatesFirstWeek() throws {
        let app = onboardingApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Where are you starting?"].waitForExistence(timeout: 10))
        app.buttons["startingPoint.running"].tap()

        let runChoice = app.buttons["10 min"]
        reveal(runChoice, in: app)
        runChoice.tap()

        attachScreenshot(app, name: "Onboarding starting point")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Build around your week"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["Monday"].tap()
        app.buttons["Wednesday"].tap()
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
        app.buttons["60 min"].tap()
        XCTAssertTrue(app.buttons["Continue"].isEnabled)

        attachScreenshot(app, name: "Onboarding schedule")
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Your first week"].waitForExistence(timeout: 5))
        let start = app.buttons["Start My Plan"]
        XCTAssertTrue(start.isEnabled)

        attachScreenshot(app, name: "Onboarding first week")
        start.tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testOnboardingCanChooseEventDistanceAndOptionalDate() throws {
        let app = onboardingApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Where are you starting?"].waitForExistence(timeout: 10))
        app.buttons["startingPoint.running"].tap()
        reveal(app.buttons["10 min"], in: app)
        app.buttons["10 min"].tap()
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.staticTexts["Build around your week"].waitForExistence(timeout: 5))

        let eventObjective = app.buttons["objective.event"]
        reveal(eventObjective, in: app)
        eventObjective.tap()

        let tenK = app.buttons["event.distance.run10K"]
        reveal(tenK, in: app)
        tenK.tap()

        let dateToggle = app.buttons["event.date.toggle"]
        reveal(dateToggle, in: app)
        dateToggle.tap()
        XCTAssertTrue(app.datePickers["event.date.picker"].waitForExistence(timeout: 5))

        reveal(app.buttons["Monday"], in: app)
        app.buttons["Monday"].tap()
        app.buttons["Wednesday"].tap()
        reveal(app.buttons["60 min"], in: app)
        app.buttons["60 min"].tap()

        XCTAssertTrue(app.buttons["Continue"].isEnabled)
        attachScreenshot(app, name: "Onboarding event objective")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Your first week"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTrainingProfileCanEditRaceDistance() throws {
        let app = eventProfileApp()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        let profile = app.buttons["Training profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()

        let goal = app.buttons["profile.goal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        goal.tap()

        let tenK = app.buttons["event.distance.run10K"]
        reveal(tenK, in: app)
        tenK.tap()

        app.navigationBars["Goal"].buttons.firstMatch.tap()

        XCTAssertTrue(app.staticTexts["10K Run"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Profile edited event")
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

    /// Plan renders the selected workout in place; management actions stay on
    /// that workout rather than behind a second detail screen.
    @MainActor
    func testPlanShowsInlineWorkoutOptions() throws {
        let app = densityApp()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Plan"].tap()

        XCTAssertFalse(app.buttons["View workout"].exists)

        let options = app.buttons["Workout options"]
        reveal(options, in: app)
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Plan inline workout")

        options.tap()
        let moveWorkout = app.buttons["Move Workout"]
        XCTAssertTrue(moveWorkout.waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Plan workout options")
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
    private func eventProfileApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--event-profile-ui-tests",
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
