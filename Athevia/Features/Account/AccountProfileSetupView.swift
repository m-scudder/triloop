import SwiftData
import SwiftUI

/// One-time account details collected after authentication and before training
/// onboarding. Name is prefilled from Apple when Apple supplies it; date of
/// birth is collected directly so age never becomes a stale stored number.
struct AccountProfileSetupView: View {
    let initialName: String
    let initialBirthDate: Date?
    let isSaving: Bool
    let errorMessage: String?
    let confirm: (String, Date) -> Void

    @State private var name: String
    @State private var birthDate: Date

    init(
        initialName: String,
        initialBirthDate: Date?,
        isSaving: Bool = false,
        errorMessage: String? = nil,
        confirm: @escaping (String, Date) -> Void
    ) {
        self.initialName = initialName
        self.initialBirthDate = initialBirthDate
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.confirm = confirm

        _name = State(initialValue: initialName)
        _birthDate = State(
            initialValue: initialBirthDate
                ?? Calendar.current.date(
                    byAdding: .year,
                    value: -30,
                    to: .now
                )
                ?? .now
        )
    }

    private var validName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var birthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let oldest = calendar.date(
            byAdding: .year,
            value: -100,
            to: .now
        ) ?? .now
        let youngest = calendar.date(
            byAdding: .year,
            value: -10,
            to: .now
        ) ?? .now
        return oldest...youngest
    }

    private var age: Int {
        Calendar.current.dateComponents(
            [.year],
            from: birthDate,
            to: .now
        ).year ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A little about you")
                        .font(.largeTitle.bold())

                    Text(
                        "Confirm your name and age before we build your training plan."
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        AtheviaAdaptiveStyle(
                            .secondary,
                            gaming: .secondaryText
                        )
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Name")
                        .font(.subheadline.weight(.semibold))

                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(
                            AtheviaAdaptiveStyle(
                                Color(uiColor: .secondarySystemBackground),
                                gaming: .surface
                            ),
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Date of birth")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Text("Age \(age)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                AtheviaAdaptiveStyle(
                                    .secondary,
                                    gaming: .secondaryText
                                )
                            )
                    }

                    AtheviaDatePicker(
                        title: "Date of birth",
                        selection: $birthDate,
                        minimumDate: birthDateRange.lowerBound,
                        maximumDate: birthDateRange.upperBound,,
                        showsTitle: false
                    )

                    Text(
                        "We use your age for age-based training guidance such as heart-rate zones."
                    )
                    .font(.caption)
                    .foregroundStyle(
                        AtheviaAdaptiveStyle(
                            .secondary,
                            gaming: .secondaryText
                        )
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(
                            AtheviaAdaptiveStyle(
                                .red,
                                gaming: .danger
                            )
                        )
                }

                Button {
                    confirm(validName, birthDate)
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(validName.isEmpty || isSaving)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .atheviaScreen()
    }
}

@MainActor
enum AccountProfileDetailsStore {
    static func requiresConfirmation(
        in context: ModelContext
    ) -> Bool {
        guard let profile = try? context.fetch(
            FetchDescriptor<AthleteProfile>()
        ).first else {
            return true
        }

        return profile.name
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
            || profile.setup?.birthDate == nil
    }

    static func initialName(
        session: AccountSession,
        in context: ModelContext
    ) -> String {
        if let profile = try? context.fetch(
            FetchDescriptor<AthleteProfile>()
        ).first {
            let existing = profile.name
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            if !existing.isEmpty {
                return existing
            }
        }

        return session.suggestedName?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
    }

    static func initialBirthDate(
        in context: ModelContext
    ) -> Date? {
        guard let profile = try? context.fetch(
            FetchDescriptor<AthleteProfile>()
        ).first else {
            return nil
        }
        return profile.setup?.birthDate
    }

    static func makeDetails(
        accountID: String,
        name: String,
        birthDate: Date
    ) throws -> AccountProfileDetails {
        let normalizedName = name
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !normalizedName.isEmpty else {
            throw AccountProfileDetailsError.missingName
        }

        return AccountProfileDetails(
            accountID: accountID,
            name: normalizedName,
            birthDate: birthDate
        )
    }

    static func details(
        accountID: String,
        in context: ModelContext
    ) -> AccountProfileDetails? {
        guard let profile = try? context.fetch(
            FetchDescriptor<AthleteProfile>()
        ).first,
        let birthDate = profile.setup?.birthDate else {
            return nil
        }

        let name = profile.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !name.isEmpty else {
            return nil
        }

        return AccountProfileDetails(
            accountID: accountID,
            name: name,
            birthDate: birthDate
        )
    }

    static func apply(
        _ details: AccountProfileDetails,
        in context: ModelContext
    ) throws {
        if let profile = try context.fetch(
            FetchDescriptor<AthleteProfile>()
        ).first {
            profile.name = details.name
            var setup = profile.setup ?? AthleteSetup()
            setup.birthDate = details.birthDate
            profile.setup = setup
        } else {
            var setup = AthleteSetup()
            setup.birthDate = details.birthDate

            context.insert(
                AthleteProfile(
                    name: details.name,
                    trainingStartDate: .now,
                    setup: setup
                )
            )
        }

        try context.save()
    }

    static func save(
        name: String,
        birthDate: Date,
        in context: ModelContext
    ) throws {
        let temporaryAccountID = UUID().uuidString
        let details = try makeDetails(
            accountID: temporaryAccountID,
            name: name,
            birthDate: birthDate
        )
        try apply(details, in: context)
    }
}

enum AccountProfileDetailsError: LocalizedError {
    case missingName

    var errorDescription: String? {
        switch self {
        case .missingName:
            "Enter your name to continue."
        }
    }
}
