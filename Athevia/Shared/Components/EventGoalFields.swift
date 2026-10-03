import SwiftUI

/// Compact structured event editor shared by onboarding and Training Profile.
///
/// It edits domain values only. Validation stays in TrainingObjectiveValidator,
/// and no training decision is made in the view.
struct EventGoalFields: View {
    let objective: TrainingObjective
    let selectedSports: [Sport]
    var minimumDate: Date = Calendar.current.startOfDay(for: .now)
    var showsTargetIntent = true
    let onChange: (TrainingObjective) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var event: AthleteEventGoal {
        var resolved = objective.event ?? AthleteEventGoal(
            sport: defaultEventSport,
            distance: EventDistance.defaultForSport(defaultEventSport)
        )
        if let onlySport = lockedEventSport, resolved.sport != onlySport {
            resolved.sport = onlySport
            resolved.distance = EventDistance.defaultForSport(onlySport)
        }
        return resolved
    }

    private var lockedEventSport: EventSport? {
        guard selectedSports.count == 1,
              let selected = selectedSports.first else { return nil }
        return EventSport(trainingSport: selected)
    }

    private var defaultEventSport: EventSport {
        if selectedSports.count == Sport.allCases.count { return .triathlon }
        if let first = selectedSports.first, let sport = EventSport(trainingSport: first) {
            return sport
        }
        return .running
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(title: "What are you preparing for?") {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(EventSport.allCases, id: \.self) { sport in
                        AtheviaChoiceChip(
                            title: sport.displayName,
                            isSelected: event.sport == sport,
                            tint: tint(for: sport)
                        ) {
                            select(sport)
                        }
                        .accessibilityIdentifier("event.sport.\(sport.rawValue)")
                        .disabled(lockedEventSport != nil && lockedEventSport != sport)
                        .opacity(lockedEventSport != nil && lockedEventSport != sport ? 0.35 : 1)
                        .frame(minHeight: 44)
                    }
                }
            }

            section(title: "Which distance?") {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(EventDistanceKind.choices(for: event.sport), id: \.self) { kind in
                        AtheviaChoiceChip(
                            title: kind.displayName,
                            isSelected: event.distance?.kind == kind,
                            tint: tint(for: event.sport)
                        ) {
                            updateEvent { current in
                                current.distance = EventDistance(kind: kind)
                            }
                        }
                        .accessibilityIdentifier("event.distance.\(kind.rawValue)")
                        .frame(minHeight: 44)
                    }
                }

                if event.distance?.kind.isCustom == true {
                    customDistanceFields
                }
            }

            section(title: "When is it?") {
                HStack {
                    Text("Add event date")
                    Spacer(minLength: 12)
                    Toggle("", isOn: hasDate)
                        .labelsHidden()
                        .toggleStyle(AtheviaToggleStyle())
                        .accessibilityIdentifier("event.date.toggle")
                }
                .frame(minHeight: 44)

                if event.eventDate != nil {
                    AtheviaDatePicker(
                        title: "Event date",
                        selection: eventDate,
                        minimumDate: minimumDate,
                    )
                    .accessibilityIdentifier("event.date.picker")
                }
            }

            if showsTargetIntent {
                section(title: "Event goal") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(EventTargetIntent.allCases, id: \.self) { intent in
                            AtheviaChoiceChip(
                                title: intent.displayName,
                                isSelected: event.targetIntent == intent,
                                tint: tint(for: event.sport)
                            ) {
                                updateEvent { $0.targetIntent = intent }
                            }
                            .accessibilityIdentifier("event.intent.\(intent.rawValue)")
                            .frame(minHeight: 44)
                        }
                    }
                }
            }

            validationMessages
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: title)
            content()
        }
    }

    @ViewBuilder
    private var customDistanceFields: some View {
        switch event.sport {
        case .running:
            EventDistanceTextField(
                title: "Run",
                unit: "km",
                meters: event.distance?.components.runMeters,
                unitScale: 1_000
            ) { setCustom(runMeters: $0) }

        case .cycling:
            EventDistanceTextField(
                title: "Bike",
                unit: "km",
                meters: event.distance?.components.bikeMeters,
                unitScale: 1_000
            ) { setCustom(bikeMeters: $0) }

        case .swimming:
            EventDistanceTextField(
                title: "Swim",
                unit: "m",
                meters: event.distance?.components.swimMeters,
                unitScale: 1
            ) { setCustom(swimMeters: $0) }

        case .triathlon:
            EventDistanceTextField(
                title: "Swim",
                unit: "m",
                meters: event.distance?.components.swimMeters,
                unitScale: 1
            ) { setCustom(swimMeters: $0) }

            EventDistanceTextField(
                title: "Bike",
                unit: "km",
                meters: event.distance?.components.bikeMeters,
                unitScale: 1_000
            ) { setCustom(bikeMeters: $0) }

            EventDistanceTextField(
                title: "Run",
                unit: "km",
                meters: event.distance?.components.runMeters,
                unitScale: 1_000
            ) { setCustom(runMeters: $0) }
        }
    }

    @ViewBuilder
    private var validationMessages: some View {
        let issues = TrainingObjectiveValidator.issues(
            for: objective,
            selectedSports: selectedSports,
            asOf: minimumDate
        )

        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
            Label(issue.message, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(AtheviaAdaptiveStyle(.orange, gaming: .warning))
                .accessibilityLabel(issue.message)
        }
    }

    private var hasDate: Binding<Bool> {
        Binding(
            get: { event.eventDate != nil },
            set: { enabled in
                updateEvent { current in
                    if enabled {
                        current.eventDate = current.eventDate
                            ?? Calendar.current.date(byAdding: .weekOfYear, value: 8, to: minimumDate)
                            ?? minimumDate
                    } else {
                        current.eventDate = nil
                    }
                }
            }
        )
    }

    private var eventDate: Binding<Date> {
        Binding(
            get: { event.eventDate ?? minimumDate },
            set: { date in
                updateEvent {
                    $0.eventDate = max(
                        Calendar.current.startOfDay(for: date),
                        Calendar.current.startOfDay(for: minimumDate)
                    )
                }
            }
        )
    }

    private func select(_ sport: EventSport) {
        updateEvent { current in
            current.sport = sport
            if current.distance?.kind.sport != sport {
                current.distance = EventDistance.defaultForSport(sport)
            }
        }
    }

    private func setCustom(
        swimMeters: Double? = nil,
        bikeMeters: Double? = nil,
        runMeters: Double? = nil
    ) {
        updateEvent { current in
            var components = current.distance?.components ?? EventDistance.defaultForSport(current.sport).components
            if let swimMeters { components.swimMeters = swimMeters }
            if let bikeMeters { components.bikeMeters = bikeMeters }
            if let runMeters { components.runMeters = runMeters }
            current.distance = EventDistance(
                kind: customKind(for: current.sport),
                components: components
            )
        }
    }

    private func customKind(for sport: EventSport) -> EventDistanceKind {
        switch sport {
        case .running: .runCustom
        case .swimming: .swimmingCustom
        case .cycling: .cyclingCustom
        case .triathlon: .triathlonCustom
        }
    }

    private func updateEvent(_ change: (inout AthleteEventGoal) -> Void) {
        var updated = event
        change(&updated)
        onChange(TrainingObjective(kind: .event, event: updated))
    }

    private func tint(for sport: EventSport) -> Color {
        switch sport {
        case .running: Discipline.running.tint
        case .swimming: Discipline.swimming.tint
        case .cycling: Discipline.cycling.tint
        case .triathlon: .blue
        }
    }
}

private struct EventDistanceTextField: View {
    let title: String
    let unit: String
    let meters: Double?
    let unitScale: Double
    let onMetersChanged: (Double) -> Void

    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .frame(width: 44, alignment: .leading)

            TextField("Distance", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.done)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(title) distance")
                .onChange(of: text) { _, value in
                    let parsed = Double(value) ?? 0
                    onMetersChanged(parsed * unitScale)
                }

            Text(unit)
                .font(.subheadline)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        }
        .onAppear(perform: syncText)
        .frame(minHeight: 44)
        .onChange(of: meters) { _, _ in syncText() }
    }

    private func syncText() {
        let display = (meters ?? 0) / unitScale
        let rendered = display.formatted(.number.precision(.fractionLength(0...2)))
        if text != rendered { text = rendered }
    }
}

