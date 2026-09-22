import Foundation
import SwiftData

/// Drives onboarding: holds the answers, persists progress, and hands the
/// finished assessment to the domain layer.
///
/// Deliberately thin. It collects and saves; `StartingParameterResolver` and
/// `FirstWeekBuilder` decide what the answers mean. No view in this flow
/// computes a training value.
@MainActor
@Observable
final class OnboardingModel {
    private let context: ModelContext
    private let builder: FirstWeekBuilder
    private let calendar: Calendar

    /// The answers so far. Written back to the profile at every step so an
    /// interrupted setup resumes rather than restarts.
    private(set) var setup: AthleteSetup
    private(set) var poolLengthMeters: Double
    /// Surfaced rather than swallowed: a setup that cannot be saved must not
    /// look like one that was.
    private(set) var failure: String?
    private(set) var preview: WeeklyPlan?
    private(set) var isWorking = false

    /// Populated when the athlete already has training history, which changes
    /// the flow from "set up" to "finish setting up".
    let isUpgrade: Bool

    private var profile: AthleteProfile?

    init(
        context: ModelContext,
        builder: FirstWeekBuilder = FirstWeekBuilder(),
        calendar: Calendar = .current
    ) {
        self.context = context
        self.builder = builder
        self.calendar = calendar

        let existing = try? context.fetch(FetchDescriptor<AthleteProfile>()).first
        profile = existing
        setup = existing?.setup ?? AthleteSetup()
        poolLengthMeters = existing?.poolLengthMeters ?? 25

        let plans = (try? context.fetchCount(FetchDescriptor<WeeklyPlan>())) ?? 0
        isUpgrade = existing != nil && plans > 0

        // Older saved onboarding states could arrive at the schedule screen
        // before sport selection existed. Preserve a usable resume path.
        if stage == .days, setup.preferences.isEmpty {
            setup.preferences = SportPreference.defaults(for: setup.baseline)
        }
    }

    var stage: AthleteSetup.Stage { setup.stage.consolidated }

    var selectedSports: [Sport] {
        Sport.allCases.filter(isSportSelected)
    }

    var minimumTrainingDays: Int {
        max(2, selectedSports.count)
    }

    /// One shared availability cap is applied to every day. A nil value means
    /// the athlete has not answered the time question yet, or is resuming a
    /// legacy schedule with mixed per-day limits.
    var sharedTrainingMinutes: Int? {
        let values = setup.schedule.days.compactMap(\.maxDurationMinutes)
        guard values.count == setup.schedule.days.count,
              let first = values.first,
              values.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    var canAdvance: Bool {
        switch stage {
        case .running:
            guard !selectedSports.isEmpty else { return false }
            return !isSportSelected(.swimming) || PoolLength.isValid(poolLengthMeters)

        case .days:
            return setup.canGeneratePlan
                && sharedTrainingMinutes != nil
                && setup.schedule.availableDays.count >= minimumTrainingDays

        default:
            return true
        }
    }

    // MARK: - Answers

    func choose(goal: TrainingGoal) {
        setup.goal = goal
        persist()
    }

    func setBirthDate(_ date: Date?) {
        setup.birthDate = date
        persist()
    }

    func choose(running: RunningBaseline) {
        setup.baseline.running = running
        refreshSelectedPreference(for: .running)
        persist()
    }

    func choose(swimming: SwimmingBaseline) {
        setup.baseline.swimming = swimming
        refreshSelectedPreference(for: .swimming)
        persist()
    }

    func choose(stroke: SwimStroke) {
        setup.baseline.stroke = stroke
        persist()
    }

    func choose(cycling: CyclingBaseline) {
        setup.baseline.cycling = cycling
        refreshSelectedPreference(for: .cycling)
        persist()
    }

    func isSportSelected(_ sport: Sport) -> Bool {
        setup.preferences.first(where: { $0.sport == sport })?.isTrained == true
    }

    func toggleSport(_ sport: Sport) {
        let index = preferenceIndex(for: sport)

        if setup.preferences[index].isTrained {
            setup.preferences[index].sessionsPerWeek = 0
        } else {
            let opening = openingPreference(for: sport)
            setup.preferences[index].sessionsPerWeek = 1
            setup.preferences[index].typicalMinutes = opening.typicalMinutes
        }

        persist()
    }

    func toggleDay(_ weekday: Weekday) {
        var days = setup.schedule.days
        guard let index = days.firstIndex(where: { $0.weekday == weekday }) else { return }

        days[index].isAvailable.toggle()
        setup.schedule = AthleteSchedule(days: days)
        persist()
    }

    func setMaxDuration(_ minutes: Int?, on weekday: Weekday) {
        var days = setup.schedule.days
        guard let index = days.firstIndex(where: { $0.weekday == weekday }) else { return }

        days[index].maxDurationMinutes = minutes
        setup.schedule = AthleteSchedule(days: days)
        persist()
    }

    func setSharedMaxDuration(_ minutes: Int) {
        var days = setup.schedule.days
        for index in days.indices {
            days[index].maxDurationMinutes = minutes
        }
        setup.schedule = AthleteSchedule(days: days)
        persist()
    }

    func setSessions(_ count: Int, for sport: Sport) {
        let index = preferenceIndex(for: sport)
        setup.preferences[index].sessionsPerWeek = min(
            max(count, 0),
            SportPreference.permittedSessions.upperBound
        )
        persist()
    }

    func setTypicalMinutes(_ minutes: Int, for sport: Sport) {
        let index = preferenceIndex(for: sport)
        setup.preferences[index].typicalMinutes = minutes
        persist()
    }

    func setPoolLength(_ meters: Double) {
        poolLengthMeters = meters
        persist()
    }

    // MARK: - Navigation

    func advance() {
        guard canAdvance else { return }

        setup.stage = stage.next
        persist()

        if setup.stage == .preview { buildPreview() }
    }

    func goBack() {
        setup.stage = stage.previous
        persist()
    }

    func jump(to stage: AthleteSetup.Stage) {
        setup.stage = stage.consolidated
        preview = nil

        if setup.stage == .days, setup.preferences.isEmpty {
            setup.preferences = SportPreference.defaults(for: setup.baseline)
        }

        persist()
    }

    // MARK: - Plan

    /// When the athlete wants to begin.
    enum StartChoice: Equatable, Identifiable {
        /// Today, giving a short first week that still ends on the Sunday.
        case now
        /// The Monday coming, giving a full week.
        case nextMonday

        var id: Self { self }
    }

    private(set) var startChoice: StartChoice = .now

    /// Offered while the athlete still has a day they can train on this week.
    ///
    /// Counted from their own availability rather than from the calendar: an
    /// athlete who rests at weekends has Friday as their last training day, and
    /// that is exactly the day a weekday-number rule would throw away.
    static func hasTrainingDayLeft(
        in schedule: AthleteSchedule,
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let today = Weekday(date: date, calendar: calendar) else { return false }
        return schedule.availableDays.contains { $0.weekday >= today }
    }

    var canStartNow: Bool {
        guard latestPlan() == nil else { return false }
        return Self.hasTrainingDayLeft(in: setup.schedule, on: .now, calendar: calendar)
    }

    func choose(start: StartChoice) {
        startChoice = start
        buildPreview()
    }

    /// Built but not saved. The athlete sees the week before it becomes theirs.
    func buildPreview() {
        preview = nil
        failure = nil

        let existing = latestPlan()
        let number = (existing?.weekNumber ?? 0) + 1

        do {
            preview = try builder.build(
                setup: setup,
                poolLengthMeters: poolLengthMeters,
                startDate: startDate(after: existing),
                weekNumber: number
            )
            preview?.generationReasonCode = existing == nil ? .initialAssessment : .profileChanged
        } catch FirstWeekBuilder.BuildFailure.scheduleUnusable {
            failure = "Pick at least two days you can train and at least one sport."
        } catch FirstWeekBuilder.BuildFailure.noSessionsFit {
            failure = "The selected sessions do not fit your available time. Choose a longer training window or another day."
        } catch {
            failure = "Could not build your first week: \(error.localizedDescription)"
        }
    }

    /// An athlete with history always continues the day after their last week.
    /// Only a new athlete gets to choose, and only while the week has room left.
    private func startDate(after existing: WeeklyPlan?) -> Date {
        if let existing {
            return calendar.date(byAdding: .day, value: 1, to: existing.endDate) ?? existing.endDate
        }

        let today = calendar.startOfDay(for: .now)
        guard startChoice == .nextMonday || !canStartNow else { return today }

        let weekday = Weekday(date: today, calendar: calendar) ?? .monday
        guard weekday != .monday else { return today }
        return calendar.date(byAdding: .day, value: 7 - weekday.offsetFromMonday, to: today) ?? today
    }

    /// Commits the plan and marks setup finished. Every previous week is kept;
    /// this only adds the next one.
    func start() {
        guard let preview else { return }
        isWorking = true
        defer { isWorking = false }

        setup.stage = .complete
        setup.completedAt = .now

        context.insert(preview)
        persist()

        if failure == nil {
            TrainingResetBoundary.completeFreshStart()
        }
    }

    private func latestPlan() -> WeeklyPlan? {
        let descriptor = FetchDescriptor<WeeklyPlan>(sortBy: [SortDescriptor(\.startDate)])
        return (try? context.fetch(descriptor))?.last
    }

    // MARK: - Sport selection

    /// Frequency is derived later from the selected sports and available days.
    /// A positive stored value only marks that the sport is selected.
    private func preferenceIndex(for sport: Sport) -> Int {
        if let index = setup.preferences.firstIndex(where: { $0.sport == sport }) {
            return index
        }

        setup.preferences.append(
            SportPreference(
                sport: sport,
                sessionsPerWeek: 0,
                typicalMinutes: openingPreference(for: sport).typicalMinutes
            )
        )
        return setup.preferences.count - 1
    }

    private func openingPreference(for sport: Sport) -> SportPreference {
        SportPreference.defaults(for: setup.baseline)
            .first(where: { $0.sport == sport })
            ?? SportPreference(sport: sport, sessionsPerWeek: 1, typicalMinutes: 45)
    }

    private func refreshSelectedPreference(for sport: Sport) {
        guard let index = setup.preferences.firstIndex(where: { $0.sport == sport }),
              setup.preferences[index].isTrained else {
            return
        }

        setup.preferences[index].typicalMinutes = openingPreference(for: sport).typicalMinutes
    }

    // MARK: - Persistence

    private func persist() {
        let profile = profile ?? makeProfile()
        profile.setup = setup
        profile.poolLengthMeters = poolLengthMeters

        do {
            try context.save()
            failure = nil
        } catch {
            failure = "Could not save your setup: \(error.localizedDescription)"
        }
    }

    private func makeProfile() -> AthleteProfile {
        let created = AthleteProfile(name: "", trainingStartDate: .now)
        context.insert(created)
        profile = created
        return created
    }
}
