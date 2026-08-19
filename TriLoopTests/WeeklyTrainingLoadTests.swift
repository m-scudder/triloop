import Foundation
import Testing
@testable import TriLoop

@Suite("Weekly training load")
struct WeeklyTrainingLoadTests {

    private let monday = Date(timeIntervalSince1970: 1_760_000_000)

    private func session(_ sport: Sport, _ value: Double?, dayOffset: Int = 0) -> LoadedSession {
        LoadedSession(
            date: monday.addingTimeInterval(Double(dayOffset) * 86_400),
            sport: sport,
            load: value.map { SessionLoad(value: $0, provenance: .reportedEffort) }
        )
    }

    private func week(_ number: Int, _ sessions: [LoadedSession]) -> PlanWeekSessions {
        PlanWeekSessions(
            weekNumber: number,
            startDate: monday.addingTimeInterval(Double(number - 1) * 7 * 86_400),
            sessions: sessions
        )
    }

    @Test("A week totals the loads it measured")
    func weekTotal() throws {
        let load = try #require(
            WeeklyTrainingLoad.load(for: week(1, [
                session(.running, 120),
                session(.swimming, 90, dayOffset: 2),
                session(.cycling, 150, dayOffset: 4)
            ])).value
        )
        #expect(load.total == 360)
        #expect(load.measured == 3)
        #expect(!load.isPartial)
    }

    @Test("Load is broken down by sport")
    func loadBySport() throws {
        let load = try #require(
            WeeklyTrainingLoad.load(for: week(1, [
                session(.running, 100),
                session(.running, 80, dayOffset: 3),
                session(.cycling, 120, dayOffset: 5)
            ])).value
        )
        #expect(load.bySport[.running] == 180)
        #expect(load.bySport[.cycling] == 120)
        #expect(load.bySport[.swimming] == nil)
    }

    @Test("Unmeasured sessions are counted, not silently dropped")
    func partialWeek() throws {
        let load = try #require(
            WeeklyTrainingLoad.load(for: week(1, [
                session(.running, 120),
                session(.swimming, nil, dayOffset: 2)
            ])).value
        )
        // The total is honest about what it covers rather than implying the
        // swim contributed nothing.
        #expect(load.total == 120)
        #expect(load.measured == 1)
        #expect(load.unmeasured == 1)
        #expect(load.isPartial)
    }

    @Test("A week with nothing measured has no total rather than zero")
    func nothingMeasured() {
        let result = WeeklyTrainingLoad.load(for: week(1, [
            session(.running, nil),
            session(.swimming, nil, dayOffset: 2)
        ]))
        #expect(result == .unavailable)
        #expect(result.value?.total != 0)
    }

    @Test("An empty week has no total")
    func emptyWeek() {
        #expect(WeeklyTrainingLoad.load(for: week(1, [])) == .unavailable)
    }

    // MARK: - Rolling average

    private func loaded(_ totals: [Double]) -> [WeeklyLoad] {
        totals.enumerated().map { index, total in
            WeeklyLoad(
                weekNumber: index + 1,
                startDate: monday.addingTimeInterval(Double(index) * 7 * 86_400),
                total: total,
                bySport: [.running: total],
                measured: 3,
                unmeasured: 0
            )
        }
    }

    @Test("The four-week average needs four weeks")
    func averageNeedsFullWindow() {
        #expect(
            WeeklyTrainingLoad.rollingAverage(of: loaded([400, 420, 440]))
                == .insufficientHistory(found: 3, required: 4)
        )
    }

    @Test("The average covers the most recent four weeks")
    func averageUsesMostRecent() {
        // The first week is outside the window and must not pull it down.
        #expect(
            WeeklyTrainingLoad.rollingAverage(of: loaded([100, 400, 400, 400, 400]))
                == .available(400)
        )
    }

    // MARK: - Change

    @Test("Week-on-week change is a fraction of the previous week")
    func weekOnWeekChange() throws {
        let weeks = loaded([400, 500])
        let change = try #require(WeeklyTrainingLoad.change(from: weeks[0], to: weeks[1]))
        #expect(abs(change - 0.25) < 0.0001)
    }

    @Test("A rise from nothing is not expressed as a percentage")
    func changeFromZero() {
        let weeks = loaded([0, 500])
        #expect(WeeklyTrainingLoad.change(from: weeks[0], to: weeks[1]) == nil)
        #expect(WeeklyTrainingLoad.change(from: nil, to: weeks[1]) == nil)
    }

    // MARK: - Balance

    @Test("Sport balance is expressed as shares of the week")
    func sportBalance() throws {
        let load = try #require(
            WeeklyTrainingLoad.load(for: week(1, [
                session(.running, 300),
                session(.cycling, 100, dayOffset: 3)
            ])).value
        )
        let balance = WeeklyTrainingLoad.balance(of: load)
        #expect(abs((balance[.running] ?? 0) - 0.75) < 0.0001)
        #expect(abs((balance[.cycling] ?? 0) - 0.25) < 0.0001)
    }
}
