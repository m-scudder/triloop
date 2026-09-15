import Foundation

enum WorkoutEvidencePresentation {
    static func source(_ evidence: IntensityEvidence) -> String {
        switch evidence {
        case .heartRateZones: "Heart rate"
        case .reportedEffort: "Reported effort"
        case .healthKitEffort: "Apple effort"
        case .hybrid: "Sources agree"
        case .conflicting: "Sources disagree"
        }
    }

    static func reason(_ evidence: IntensityEvidence) -> String {
        switch evidence {
        case .heartRateZones: "Based on available heart-rate evidence."
        case .reportedEffort: "Based on your reported effort; heart-rate evidence was not used."
        case .healthKitEffort: "Based on Apple's effort score; heart-rate evidence was not used."
        case .hybrid: "Heart-rate and effort evidence agree."
        case .conflicting: "Heart-rate and effort evidence disagree; the harder reading is shown."
        }
    }

    static func intensity(_ reading: WorkoutIntensityReading) -> DecisionExplanation {
        DecisionExplanation(
            title: "Why intensity is \(reading.intensity.displayName.lowercased())",
            evidence: [.init(label: "Source", value: source(reading.evidence))],
            reasons: [reason(reading.evidence)], change: nil
        )
    }

    static func source(_ provenance: LoadProvenance) -> String {
        switch provenance {
        case .heartRate: "Heart rate"
        case .reportedEffort: "Duration and RPE"
        case .healthKitEffort: "Duration and Apple effort"
        case .hybrid: "Heart rate and effort"
        }
    }

    static func provenance(_ origin: WorkoutOrigin) -> String? {
        switch origin {
        case .generated: nil
        case .library: "Added from Workout Library"
        case .custom: "Added by you"
        case .imported: "Imported workout"
        }
    }
}