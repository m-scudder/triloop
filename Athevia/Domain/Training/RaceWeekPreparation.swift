import Foundation

struct RaceWeekPreparationItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case registration
        case routeAndStart
        case clothing
        case hydration
        case nutrition
        case arrival
        case swimGear
        case bikeCheck
        case helmet
        case shoes
        case transitionLayout
        case waveStart
    }

    var kind: Kind
    var title: String
    var detail: String
    var id: Kind { kind }
}

/// Compact, event-specific race-week guidance. These are preparation prompts,
/// not another persisted checklist system.
struct RaceWeekPreparationBuilder: Sendable {
    func items(for event: AthleteEventGoal) -> [RaceWeekPreparationItem] {
        var items: [RaceWeekPreparationItem] = [
            .init(
                kind: .routeAndStart,
                title: "Route & start time",
                detail: "Confirm where you need to be and when your event starts."
            ),
            .init(
                kind: .arrival,
                title: "Arrival plan",
                detail: "Know your travel, parking or check-in timing before race morning."
            )
        ]

        switch event.sport {
        case .running:
            items.insert(.init(
                kind: .registration,
                title: "Bib / registration",
                detail: "Confirm bib collection or digital registration details."
            ), at: 0)
            items.append(.init(
                kind: .clothing,
                title: "Race-day clothing",
                detail: "Use familiar shoes and clothing you have already trained in."
            ))
            if needsFuelPlanning(event) {
                items.append(.init(
                    kind: .nutrition,
                    title: "Nutrition",
                    detail: "Use the fuel approach you have already practised."
                ))
            }
            items.append(.init(
                kind: .hydration,
                title: "Hydration",
                detail: "Know what will be available and keep the plan familiar."
            ))

        case .cycling:
            items.insert(.init(
                kind: .registration,
                title: "Registration",
                detail: "Confirm check-in and event documents."
            ), at: 0)
            items.append(.init(
                kind: .bikeCheck,
                title: "Bike readiness",
                detail: "Check tyres, brakes, drivetrain and charged electronics."
            ))
            items.append(.init(
                kind: .helmet,
                title: "Helmet",
                detail: "Set out your helmet and familiar riding kit."
            ))
            items.append(.init(
                kind: .hydration,
                title: "Hydration",
                detail: "Prepare the bottles and hydration approach you have practised."
            ))
            if needsFuelPlanning(event) {
                items.append(.init(
                    kind: .nutrition,
                    title: "Nutrition",
                    detail: "Prepare familiar on-bike fuel; do not introduce something new."
                ))
            }

        case .swimming:
            items.insert(.init(
                kind: .registration,
                title: "Registration",
                detail: "Confirm check-in and event start details."
            ), at: 0)
            items.append(.init(
                kind: .swimGear,
                title: "Swim equipment",
                detail: "Set out the goggles, cap and permitted equipment you have already used."
            ))
            items.append(.init(
                kind: .waveStart,
                title: "Start / wave",
                detail: "Confirm your wave, briefing and water-entry procedure."
            ))

        case .triathlon:
            items.insert(.init(
                kind: .registration,
                title: "Bib / registration",
                detail: "Confirm registration, race numbers and check-in requirements."
            ), at: 0)
            items.append(contentsOf: [
                .init(
                    kind: .swimGear,
                    title: "Swim gear",
                    detail: "Set out goggles, cap and familiar permitted swim equipment."
                ),
                .init(
                    kind: .bikeCheck,
                    title: "Bike check",
                    detail: "Check tyres, brakes, drivetrain and charged electronics."
                ),
                .init(
                    kind: .helmet,
                    title: "Helmet",
                    detail: "Set out your helmet with the bike equipment you have practised."
                ),
                .init(
                    kind: .shoes,
                    title: "Shoes",
                    detail: "Prepare familiar bike and run shoes."
                ),
                .init(
                    kind: .transitionLayout,
                    title: "Transition setup",
                    detail: "Rehearse a simple layout and the order you will use."
                ),
                .init(
                    kind: .nutrition,
                    title: "Nutrition & hydration",
                    detail: "Use the race-fuelling approach you have already practised."
                ),
                .init(
                    kind: .waveStart,
                    title: "Race start / wave",
                    detail: "Confirm your wave, briefing and start procedure."
                )
            ])
        }

        return items
    }

    private func needsFuelPlanning(_ event: AthleteEventGoal) -> Bool {
        switch event.distance?.kind {
        case .runHalfMarathon, .runMarathon,
             .cycling50K, .cycling100K,
             .triathlonOlympic, .triathlon703:
            true
        default:
            false
        }
    }
}
