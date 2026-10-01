import Foundation

/// Only fixed product vocabulary can enter analytics. Never accept a model,
/// free-form string, date, error description, workout ID or health measurement.
enum AnalyticsScreen: String, Codable, CaseIterable {
    case home, plan, progress, settings
    case trainingProfile = "training_profile"
    case workoutHistory = "workout_history"
    case workoutDetail = "workout_detail"
    case nextWeekPreview = "next_week_preview"
    case goalSetup = "goal_setup"
    case explanation
}

enum AnalyticsOnboardingStep: String, Codable, CaseIterable {
    case welcome, startingPoint = "starting_point", schedule, preview
}

enum AnalyticsAction: String, Codable, CaseIterable {
    case importWorkouts = "import_workouts"
    case moveWorkout = "move_workout"
    case skipWorkout = "skip_workout"
    case changeAvailability = "change_availability"
    case updatePlan = "update_plan"
    case createNextWeek = "create_next_week"
    case sendToWatch = "send_to_watch"
    case startWorkout = "start_workout"
}

enum AnalyticsOutcome: String, Codable, CaseIterable {
    case requested, succeeded, failed, cancelled
}

enum AnalyticsEvent: Equatable {
    case appOpened
    case screenViewed(AnalyticsScreen)
    case onboardingStepViewed(AnalyticsOnboardingStep)
    case onboardingCompleted
    case onboardingFailed
    case action(AnalyticsAction, AnalyticsOutcome)
    case whyTapped
    case infoTapped
    case calendarOpened

    var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .screenViewed: "$screen"
        case .onboardingStepViewed: "onboarding_step_viewed"
        case .onboardingCompleted: "onboarding_completed"
        case .onboardingFailed: "onboarding_failed"
        case .action(let action, let outcome): "\(action.rawValue)_\(outcome.rawValue)"
        case .whyTapped: "why_tapped"
        case .infoTapped: "info_tapped"
        case .calendarOpened: "calendar_opened"
        }
    }

    var properties: [String: String] {
        switch self {
        case .screenViewed(let screen): ["$screen_name": screen.rawValue]
        case .onboardingStepViewed(let step): ["step": step.rawValue]
        default: [:]
        }
    }

    /// Also validates disk records so a stale queue cannot bypass the schema.
    static func isAllowed(name: String, properties: [String: String]) -> Bool {
        if name == "$screen" {
            return properties.count == 1
                && properties["$screen_name"].flatMap(AnalyticsScreen.init(rawValue:)) != nil
        }
        if name == "onboarding_step_viewed" {
            return properties.count == 1
                && properties["step"].flatMap(AnalyticsOnboardingStep.init(rawValue:)) != nil
        }
        guard properties.isEmpty else { return false }
        let simple: [AnalyticsEvent] = [.appOpened, .onboardingCompleted, .onboardingFailed,
                                       .whyTapped, .infoTapped, .calendarOpened]
        return simple.contains { $0.name == name } || AnalyticsAction.allCases.contains { action in
            AnalyticsOutcome.allCases.contains { name == AnalyticsEvent.action(action, $0).name }
        }
    }
}
