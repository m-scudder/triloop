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
    }

    var stage: AthleteSetup.Stage { setup.stage }

    var canAdvance: Bool {
        switch stage {
        case .days: setup.schedule.isUsable
        case .commitment: setup.preferences.contains(where: \.isTrained)
        case .pool: PoolLength.isValid(poolLengthMeters)
        default: true
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
        persist()
    }

    func choose(swimming: SwimmingBaseline) {
        setup.baseline.swimming = swimming
        persist()
    }

    func choose(stroke: SwimStroke) {
        setup.baseline.stroke = stroke
        persist()
    }

    func choose(cycling: CyclingBaseline) {
        setup.baseline.cycling = cycling
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

    func setSessions(_ count: Int, for sport: Sport) {
        update(sport) { $0.sessionsPerWeek = min(max(count, 0), SportPreference.permittedSessions.upperBound) }
    }

    func setTypicalMinutes(_ minutes: Int, for sport: Sport) {
        update(sport) { $0.typicalMinutes = minutes }
    }

    private func update(_ sport: Sport, _ change: (inout SportPreference) -> Void) {
        guard let index = setup.preferences.firstIndex(where: { $0.sport == sport }) else { return }
        change(&setup.preferences[index])
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

        // Seeded from the baselines the moment the athlete reaches the step, so
        // they adjust a sensible starting position rather than three zeroes.
        if setup.stage == .commitment, setup.preferences.isEmpty {
            setup.preferences = SportPreference.defaults(for: setup.baseline)
        }

        persist()

        if setup.stage == .preview { buildPreview() }
    }

    func goBack() {
        setup.stage = stage.previous
        persist()
    }

    func jump(to stage: AthleteSetup.Stage) {
        setup.stage = stage
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

    /// Offered only when starting today leaves enough of the week to be worth
    /// planning. Late in the week there is nothing meaningful to fit.
    var canStartNow: Bool {
        guard latestPlan() == nil else { return false }
        let weekday = Weekday(date: .now, calendar: calendar) ?? .monday
        return weekday.offsetFromMonday <= 3
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
            failure = "Pick at least two days you can train on, and a sport for each."
        } catch FirstWeekBuilder.BuildFailure.noSessionsFit {
            failure = "None of your sessions fit the time you have available. Try allowing more time on a day, or adding another day."
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
    }

    private func latestPlan() -> WeeklyPlan? {
        let descriptor = FetchDescriptor<WeeklyPlan>(sortBy: [SortDescriptor(\.startDate)])
        return (try? context.fetch(descriptor))?.last
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
