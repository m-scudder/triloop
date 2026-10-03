import Foundation
import Testing

@testable import Athevia

@Suite("Supabase account profile row")
struct SupabaseAccountProfileRepositoryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: "Asia/Kolkata"
        ) ?? .current
        return calendar
    }

    @Test("Birth date round-trips as a calendar date")
    func birthDateRoundTrip() throws {
        let birthDate = try #require(
            calendar.date(
                from: DateComponents(
                    year: 1996,
                    month: 5,
                    day: 17
                )
            )
        )
        let details = AccountProfileDetails(
            accountID:
                "11111111-2222-3333-4444-555555555555",
            name: "Mayank Agarwal",
            birthDate: birthDate
        )

        let row = try SupabaseAccountProfileRow(
            details,
            calendar: calendar
        )
        let restored = try row.details(
            calendar: calendar
        )

        #expect(row.birthDate == "1996-05-17")
        #expect(restored.accountID.lowercased()
            == details.accountID.lowercased())
        #expect(restored.name == details.name)
        #expect(
            calendar.isDate(
                restored.birthDate,
                inSameDayAs: birthDate
            )
        )
    }

    @Test("Invalid account id is rejected")
    func invalidAccountID() {
        let details = AccountProfileDetails(
            accountID: "not-a-uuid",
            name: "Athlete",
            birthDate: .now
        )

        #expect(throws: AccountProfileRepositoryError.invalidAccountID) {
            _ = try SupabaseAccountProfileRow(
                details,
                calendar: calendar
            )
        }
    }
}
