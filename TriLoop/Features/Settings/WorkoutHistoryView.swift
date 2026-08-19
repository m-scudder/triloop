#if DEBUG
import SwiftUI

/// Read-only view of the athlete's real HealthKit workout history.
///
/// Shows everything, including activities TriLoop does not train, because the
/// question this answers is "what is actually in Health?" — and the importer's
/// filtering is exactly what hides the answer. Nothing here is saved, matched to
/// a plan, or fed to the training engine.
struct WorkoutHistoryView: View {
    @Environment(\.healthProvider) private var provider

    @State private var range: HistoryRange = .sixMonths
    @State private var state: LoadState = .idle
    @State private var query = ""
    @State private var sportFilter: SportFilter = .all

    enum SportFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case running = "Run"
        case swimming = "Swim"
        case cycling = "Bike"
        case other = "Other"

        var id: Self { self }

        func matches(_ record: HealthWorkoutRecord) -> Bool {
            switch self {
            case .all: true
            case .running: record.sport == .running
            case .swimming: record.sport == .swimming
            case .cycling: record.sport == .cycling
            case .other: record.sport == nil
            }
        }
    }

    enum HistoryRange: String, CaseIterable, Identifiable {
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case everything = "All"

        var id: Self { self }

        /// `All` reaches back to `distantPast` rather than a large month count.
        /// Date arithmetic that far back can fail, and falling back to the end
        /// date would silently produce an empty range that reads as "no data".
        func startDate(endingAt end: Date, calendar: Calendar = .current) -> Date {
            switch self {
            case .threeMonths, .sixMonths, .oneYear:
                calendar.date(byAdding: .month, value: -months, to: end) ?? .distantPast
            case .everything:
                .distantPast
            }
        }

        var months: Int {
            switch self {
            case .threeMonths: 3
            case .sixMonths: 6
            case .oneYear: 12
            case .everything: 0
            }
        }
    }

    enum LoadState {
        case idle
        case loading
        case loaded([HealthWorkoutRecord])
        case unsupported
        case failed(String)
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Sport", selection: $sportFilter) {
                    ForEach(SportFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Read-only. Nothing on this screen is imported, matched to a plan, or used for training.")
            }

            Section {
                Button("Request Health access again") {
                    Task {
                        try? await provider.requestAuthorization()
                        await load(force: true)
                    }
                }
            } footer: {
                // A denied read returns no samples rather than an error, so an
                // ungranted type is indistinguishable from one the device never
                // recorded. Re-requesting is the only way to tell them apart.
                Text("Metric types added after you first connected Health are not granted retroactively. Re-request, then enable everything under Settings → Health → Data Access.")
            }

            content
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Activity name"
        )
        .task(id: range) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading Health…")
                        .foregroundStyle(.secondary)
                }
            }

        case .unsupported:
            Section {
                Text("This provider has no workout history to read.")
                    .foregroundStyle(.secondary)
            }

        case .failed(let reason):
            Section("Query failed") {
                Text(reason)
                    .foregroundStyle(.secondary)
            }

        case .loaded(let records) where records.isEmpty:
            Section {
                Text("No workouts in this range.")
                    .foregroundStyle(.secondary)
                Text("If you expected some, Health may not have granted read access — a denied read returns no samples rather than an error.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .loaded(let records):
            let matching = matches(in: records)

            if matching.isEmpty {
                Section {
                    Text(emptyReason(total: records.count))
                        .foregroundStyle(.secondary)
                }
            } else {
                summary(matching)
                coverage(matching)
                breakdown(matching)
                months(matching)
            }
        }
    }

    /// §18: what this device actually recorded, so simulation-only verification
    /// can be told apart from real verification.
    private func coverage(_ records: [HealthWorkoutRecord]) -> some View {
        Section {
            ForEach(HistoricalMetricCoverage.report(for: records)) { metric in
                HStack {
                    Text(metric.name)
                    Spacer()
                    Text(metric.summary)
                        .foregroundStyle(metric.isEntirelyAbsent ? .secondary : .primary)
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        } header: {
            Text("Metric coverage")
        } footer: {
            Text("How many workouts carried each metric. Zero usually means the hardware never recorded it, not that import failed.")
        }
    }

    /// Counts and groupings follow the search, so the summary always describes
    /// what is on screen rather than the unfiltered history.
    private func matches(in records: [HealthWorkoutRecord]) -> [HealthWorkoutRecord] {
        let term = query.trimmingCharacters(in: .whitespaces)
        let bySport = records.filter(sportFilter.matches)
        guard !term.isEmpty else { return bySport }
        return bySport.filter { $0.activityName.localizedCaseInsensitiveContains(term) }
    }

    private func summary(_ records: [HealthWorkoutRecord]) -> some View {
        Section("Summary") {
            LabeledContent("Workouts", value: "\(records.count)")
            LabeledContent("TriLoop sports", value: "\(records.count(where: \.isTrainedByTriLoop))")
            LabeledContent("Other activities", value: "\(records.count(where: { !$0.isTrainedByTriLoop }))")

            if let earliest = records.map(\.start).min() {
                LabeledContent("Earliest", value: earliest.formatted(date: .abbreviated, time: .omitted))
            }

            let withHeartRate = records.count(where: { $0.averageHeartRate != nil })
            LabeledContent("With heart rate", value: withHeartRate == 0 ? "None recorded" : "\(withHeartRate)")
        }
    }

    private func breakdown(_ records: [HealthWorkoutRecord]) -> some View {
        let counts = Dictionary(grouping: records, by: \.activityName)
            .map { (name: $0.key, count: $0.value.count, trained: $0.value[0].isTrainedByTriLoop) }
            .sorted { $0.count > $1.count }

        return Section("By activity") {
            ForEach(counts, id: \.name) { entry in
                HStack {
                    Text(entry.name)
                    if entry.trained {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Trained by TriLoop")
                    }
                    Spacer()
                    Text("\(entry.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func months(_ records: [HealthWorkoutRecord]) -> some View {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { record in
            calendar.date(from: calendar.dateComponents([.year, .month], from: record.start)) ?? record.start
        }

        ForEach(grouped.keys.sorted(by: >), id: \.self) { month in
            Section(month.formatted(.dateTime.month(.wide).year())) {
                ForEach(grouped[month] ?? []) { record in
                    NavigationLink {
                        HealthWorkoutDetailView(record: record)
                    } label: {
                        HistoryRow(record: record)
                    }
                }
            }
        }
    }

    /// Names whichever filter emptied the list, so an absent sport is never
    /// mistaken for a failed search.
    private func emptyReason(total: Int) -> String {
        let term = query.trimmingCharacters(in: .whitespaces)

        if !term.isEmpty {
            return "No activity matches “\(term)”."
        }
        if sportFilter == .other {
            return "Health holds no activities outside running, swimming and cycling in this range. All \(total) workouts here are sports TriLoop trains."
        }
        return "No \(sportFilter.rawValue) workouts in this range, out of \(total) total."
    }

    private func load(force: Bool = false) async {
        guard let reader = provider as? any HealthHistoryReading else {
            state = .unsupported
            return
        }

        if force { state = .idle }
        state = .loading
        let end = Date.now
        let start = range.startDate(endingAt: end)

        do {
            state = .loaded(try await reader.workoutHistory(from: start, to: end))
        } catch {
            state = .failed(String(describing: error))
        }
    }
}

private struct HistoryRow: View {
    let record: HealthWorkoutRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(record.activityName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(record.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let source = record.sourceName {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Absent values say so rather than showing zero.
    private var detail: String {
        var parts = [Duration.seconds(record.duration).formatted(.time(pattern: .hourMinute))]

        if let metres = record.distanceMeters {
            parts.append(metres >= 1_000
                ? String(format: "%.2f km", metres / 1_000)
                : String(format: "%.0f m", metres))
        } else {
            parts.append("No distance")
        }

        if let heartRate = record.averageHeartRate {
            parts.append("\(Int(heartRate.rounded())) bpm")
        } else {
            parts.append("No HR")
        }

        if let lengths = record.swimmingLengths, lengths > 0 {
            parts.append("\(lengths) lengths")
        }

        return parts.joined(separator: " · ")
    }
}
#endif
