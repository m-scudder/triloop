import Charts
import SwiftUI

/// Steps beyond today: the last week and the last month, one bar per day.
///
/// Read straight from HealthKit on each appearance. TriLoop stores none of it,
/// because steps are context for the athlete rather than an input to the plan.
struct ActivityDetailView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"

        var id: Self { self }

        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            }
        }
    }

    @State private var range: Range = .week
    @State private var points: [SamplePoint] = []
    @State private var failure: String?
    @State private var isLoading = false
    @Environment(\.healthProvider) private var health

    private var total: Double { points.reduce(0) { $0 + $1.value } }

    /// Averaged over days that actually recorded something, so a part-way month
    /// is not dragged down by days that have not happened yet.
    private var average: Double {
        let recorded = points.filter { $0.value > 0 }
        guard !recorded.isEmpty else { return 0 }
        return total / Double(recorded.count)
    }

    private var best: SamplePoint? {
        points.max { $0.value < $1.value }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if let failure {
                    ContentUnavailableView(
                        "No step data",
                        systemImage: "figure.walk",
                        description: Text(failure)
                    )
                } else if points.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    chart
                    summary
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle("Steps")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: range) { await load() }
    }

    private var chart: some View {
        Card {
            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Steps", point.value)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)

                if average > 0 {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) {
                    AxisValueLabel(
                        format: range == .week
                            ? .dateTime.weekday(.narrow)
                            : .dateTime.day().month(.narrow)
                    )
                }
            }
            .accessibilityLabel("Steps per day over the last \(range.days) days")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Summary")
            Card {
                HStack(alignment: .top, spacing: 8) {
                    StatTile(value: Int(total).formatted(.number), label: "Total")
                    StatTile(value: Int(average).formatted(.number), label: "Daily average")
                    if let best, best.value > 0 {
                        StatTile(
                            value: best.date.formatted(.dateTime.weekday(.abbreviated).day()),
                            label: "Best day"
                        )
                    }
                }
            }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        switch await health.authorizationStatus {
        case .unavailable:
            failure = "Health data isn't available on this device."
            return
        case .notDetermined, .denied:
            failure = "Connect Apple Health in Settings to see your step history."
            return
        case .authorized:
            break
        }

        let calendar = Calendar.current
        let end = Date.now
        let start = calendar.date(byAdding: .day, value: -(range.days - 1), to: end) ?? end

        do {
            points = try await health.dailySteps(from: start, to: end)
            failure = points.isEmpty ? "No steps recorded in this period." : nil
        } catch {
            failure = "Could not read your steps: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        ActivityDetailView()
    }
}
