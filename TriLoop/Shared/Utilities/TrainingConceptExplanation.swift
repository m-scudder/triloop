import Foundation

enum TrainingConceptExplanation: String, CaseIterable, Identifiable {
    case rpe, trainingLoad, intensity, adherence, hrv, restingHeartRate, recovery, sportBalance, plannedVsActual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rpe: "Perceived Effort"
        case .trainingLoad: "Training Load"
        case .intensity: "Intensity"
        case .adherence: "Adherence"
        case .hrv: "Heart Rate Variability"
        case .restingHeartRate: "Resting Heart Rate"
        case .recovery: "Recovery"
        case .sportBalance: "Sport Balance"
        case .plannedVsActual: "Planned vs Actual"
        }
    }

    var definition: String {
        switch self {
        case .rpe: "RPE is your perceived effort on a scale from 1 to 10, from very easy to maximal."
        case .trainingLoad: "Training load combines workout duration and intensity to describe training stress."
        case .intensity: "Intensity describes how hard you trained. Reported effort and available heart-rate evidence describe different parts of the session."
        case .adherence: "Adherence compares completed training with the prescription. It is not a fitness score."
        case .hrv: "HRV measures variation in the time between heartbeats. Your own trend is more useful than comparison with another athlete."
        case .restingHeartRate: "Resting heart rate is the number of heartbeats per minute while at rest."
        case .recovery: "Recovery describes how you are responding to recent training, using the signals available."
        case .sportBalance: "Sport balance shows how training is distributed across running, swimming and cycling."
        case .plannedVsActual: "This compares the prescribed session with recorded activity and your report."
        }
    }

    var usage: String {
        switch self {
        case .rpe: "TriLoop uses your report with completion, pain and recovery to assess the session."
        case .trainingLoad: "Compare sessions and weeks using the same load method. Missing evidence is not zero load."
        case .intensity: "The result identifies its evidence source. Without heart-rate data, TriLoop cannot confirm heart-rate intensity."
        case .adherence: "Check the displayed period and evidence source. Unmatched activity and missing reports can limit the comparison."
        case .hrv, .restingHeartRate: "TriLoop compares available readings with your history. Missing readings do not establish normal recovery."
        case .recovery: "Review symptoms and your check-in alongside recorded signals. A metric does not override a pain or recovery warning."
        case .sportBalance: "Use the displayed duration or session counts to compare sports within the selected period."
        case .plannedVsActual: "Matched recordings supply measured values. A manual report does not provide heart-rate or measured distance evidence."
        }
    }

    var accessibilityLabel: String { "More information about \(title.lowercased())" }
}