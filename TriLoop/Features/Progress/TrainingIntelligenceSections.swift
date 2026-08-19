import Charts
import SwiftUI

/// Training load across recent weeks (§37).
struct TrainingLoadSection: View {
    let weeks: [WeeklyLoad]
    let average: IntelligenceValue<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Training load")

            if weeks.isEmpty {
                UnavailableNote(text: "No sessions with enough detail to measure load yet.")
            } else {
                chart

                HStack(alignment: .top, spacing: 24) {
                    figure(
                        value: weeks.last.map { "\(Int($0.total.rounded()))" } ?? "—",
                        caption: "This week"
                    )

                    switch average {
                    case .available(let value):
                        figure(value: "\(Int(value.rounded()))", caption: "4-week average")
                    case .insufficientHistory(let found, let required):
                        figure(value: "—", caption: "\(found) of \(required) weeks")
                    case .unavailable, .queryFailure:
                        EmptyView()
                    }

                    if let change {
                        figure(
                            value: "\(change > 0 ? "+" : "")\(Int((change * 100).rounded()))%",
                            caption: "vs last week"
                        )
                    }
                }

                if weeks.contains(where: \.isPartial) {
                    Text("Some sessions had no heart rate or report, so they are not counted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var change: Double? {
        guard weeks.count >= 2 else { return nil }
        return WeeklyTrainingLoad.change(from: weeks[weeks.count - 2], to: weeks[weeks.count - 1])
    }

    private var chart: some View {
        Chart(weeks, id: \.startDate) { week in
            BarMark(
                x: .value("Week", week.startDate, unit: .weekOfYear),
                y: .value("Load", week.total)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(3)
        }
        .frame(height: 140)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }

    private func figure(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Easy, moderate and hard as shares of training time (§38).
struct IntensityDistributionSection: View {
    let distribution: IntelligenceValue<IntensityDistribution>
    let sports: [Sport]
    @Binding var selectedSport: Sport?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Intensity")

            if sports.count > 1 {
                Picker("Sport", selection: $selectedSport) {
                    Text("All").tag(Sport?.none)
                    ForEach(sports, id: \.self) { sport in
                        Text(sport.displayName).tag(Sport?.some(sport))
                    }
                }
                .pickerStyle(.segmented)
            }

            switch distribution {
            case .available(let split):
                VStack(spacing: 6) {
                    ForEach(WorkoutIntensity.allCases, id: \.self) { intensity in
                        row(intensity, share: split.share(intensity))
                    }
                }

                if split.isPartial {
                    Text("\(split.unmeasured) session\(split.unmeasured == 1 ? "" : "s") could not be classified.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .insufficientHistory, .unavailable, .queryFailure:
                UnavailableNote(text: "Not enough classified sessions yet.")
            }
        }
    }

    private func row(_ intensity: WorkoutIntensity, share: Double) -> some View {
        HStack(spacing: 10) {
            Text(intensity.displayName)
                .font(.subheadline)
                .frame(width: 74, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(tint(for: intensity))
                        .frame(width: max(proxy.size.width * share, share > 0 ? 3 : 0))
                }
            }
            .frame(height: 10)

            Text("\(Int((share * 100).rounded()))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func tint(for intensity: WorkoutIntensity) -> Color {
        switch intensity {
        case .easy: Color(red: 0.20, green: 0.80, blue: 0.55)
        case .moderate: Color(red: 0.95, green: 0.77, blue: 0.20)
        case .hard: Color(red: 0.95, green: 0.26, blue: 0.21)
        }
    }
}

/// Where training time and load went (§39).
struct SportBalanceSection: View {
    let balance: IntelligenceValue<SportBalance>
    let comparisons: [SportBalanceComparison]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Sport balance")

            switch balance {
            case .available(let split):
                if comparisons.isEmpty {
                    ForEach(Sport.allCases, id: \.self) { sport in
                        if split.secondsBySport[sport] != nil {
                            HStack {
                                Text(sport.displayName)
                                Spacer()
                                Text("\(Int((split.timeShare(sport) * 100).rounded()))%")
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                } else {
                    comparisonTable
                }

            case .insufficientHistory, .unavailable, .queryFailure:
                UnavailableNote(text: "No training recorded in this period.")
            }
        }
    }

    private var comparisonTable: some View {
        VStack(spacing: 6) {
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text("Planned").frame(width: 70, alignment: .trailing)
                Text("Actual").frame(width: 70, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(comparisons, id: \.sport) { comparison in
                HStack {
                    Text(comparison.sport.displayName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Int((comparison.plannedShare * 100).rounded()))%")
                        .frame(width: 70, alignment: .trailing)
                    Text("\(Int((comparison.actualShare * 100).rounded()))%")
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.subheadline)
                .monospacedDigit()
            }
        }
    }
}

/// A consistent way to say a thing is missing, rather than showing a zero.
struct UnavailableNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
