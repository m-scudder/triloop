import Foundation
import Supabase

struct AccountProfileDetails: Equatable, Sendable {
    let accountID: String
    let name: String
    let birthDate: Date
}

protocol AccountProfileRepository: Sendable {
    func profile(
        for accountID: String
    ) async throws -> AccountProfileDetails?

    func upsert(
        _ profile: AccountProfileDetails
    ) async throws
}

actor SupabaseAccountProfileRepository: AccountProfileRepository {
    private let client: SupabaseClient
    private let calendar: Calendar

    init(
        client: SupabaseClient = SupabaseConfiguration.client,
        calendar: Calendar = .current
    ) {
        self.client = client
        self.calendar = calendar
    }

    func profile(
        for accountID: String
    ) async throws -> AccountProfileDetails? {
        guard let userID = UUID(uuidString: accountID) else {
            throw AccountProfileRepositoryError.invalidAccountID
        }

        let rows: [SupabaseAccountProfileRow] = try await client
            .from("account_profiles")
            .select()
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else {
            return nil
        }

        return try row.details(calendar: calendar)
    }

    func upsert(
        _ profile: AccountProfileDetails
    ) async throws {
        let row = try SupabaseAccountProfileRow(
            profile,
            calendar: calendar
        )

        try await client
            .from("account_profiles")
            .upsert(
                row,
                onConflict: "user_id"
            )
            .execute()
    }
}

enum AccountProfileRepositoryError: LocalizedError, Equatable {
    case invalidAccountID
    case invalidBirthDate

    var errorDescription: String? {
        switch self {
        case .invalidAccountID:
            "The signed-in account identifier is invalid."
        case .invalidBirthDate:
            "The saved date of birth is invalid."
        }
    }
}

struct SupabaseAccountProfileRow: Codable, Sendable {
    let userID: UUID
    let displayName: String
    let birthDate: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case birthDate = "birth_date"
        case updatedAt = "updated_at"
    }

    init(
        _ details: AccountProfileDetails,
        calendar: Calendar
    ) throws {
        guard let userID = UUID(
            uuidString: details.accountID
        ) else {
            throw AccountProfileRepositoryError
                .invalidAccountID
        }

        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: details.birthDate
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            throw AccountProfileRepositoryError
                .invalidBirthDate
        }

        self.userID = userID
        displayName = details.name
        updatedAt = .now
        birthDate = String(
            format: "%04d-%02d-%02d",
            year,
            month,
            day
        )
    }

    func details(
        calendar: Calendar
    ) throws -> AccountProfileDetails {
        let parts = birthDate.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let date = calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day
                )
              ) else {
            throw AccountProfileRepositoryError
                .invalidBirthDate
        }

        return AccountProfileDetails(
            accountID: userID.uuidString,
            name: displayName,
            birthDate: date
        )
    }
}
