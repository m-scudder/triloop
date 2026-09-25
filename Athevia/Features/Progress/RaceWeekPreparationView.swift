import SwiftUI

struct RaceWeekPreparationView: View {
    let event: AthleteEventGoal

    private var items: [RaceWeekPreparationItem] {
        RaceWeekPreparationBuilder().items(for: event)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Race week")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items.prefix(7)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if item.id != items.prefix(7).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
