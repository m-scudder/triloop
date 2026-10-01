import Foundation

/// On-device fallback for the first production slice.
///
/// It recognizes only supported requests and converts them to typed intents.
/// Imported notes and model-generated prose are never fed back through this
/// parser, which prevents data content from becoming executable instructions.
struct DeterministicCoachIntentInterpreter: CoachConversationInterpreting {
    var calendar: Calendar = .current
    var maximumRequestCharacters = 600

    func interpret(
        request: String,
        context: AthleteContextSnapshot,
        plan: WeeklyPlan,
        now: Date
    ) async -> CoachIntentInterpretation {
        interpret(request: request, plan: plan, now: now)
    }

    func interpret(
        request: String,
        plan: WeeklyPlan,
        now: Date = .now
    ) -> CoachIntentInterpretation {
        let input = String(
            request
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumRequestCharacters)
        )
        let text = input.lowercased()

        guard !text.isEmpty else {
            return .clarification("What would you like to understand or change about your training?")
        }

        if text.contains("5k") || text.contains("5 km") || text.contains("5000m") {
            return .intent(.prepareFor5K(eventDate: explicitISODate(in: text)))
        }

        if isRecentTrainingQuestion(text) {
            return .intent(.summarizeRecentTraining(weeks: weekCount(in: text) ?? 4))
        }

        if let minutes = minuteLimit(in: text) {
            guard let date = targetDate(in: text, plan: plan, now: now) else {
                return .clarification("Which day should have the \(minutes)-minute limit?")
            }
            guard (10...240).contains(minutes) else {
                return .clarification("Give me a session limit between 10 and 240 minutes.")
            }
            return .intent(.limitSession(date: date, maxMinutes: minutes))
        }

        if text.contains("cannot train")
            || text.contains("can't train")
            || text.contains("cant train")
            || text.contains("unavailable")
            || text.contains("not available") {
            guard let date = targetDate(in: text, plan: plan, now: now) else {
                return .clarification("Which day are you unable to train?")
            }
            return .intent(.unavailable(date: date))
        }

        if text.contains("easier")
            || text.contains("tired")
            || text.contains("fatigue")
            || text.contains("slept badly")
            || text.contains("poor sleep")
            || text.contains("bad sleep") {
            let reason: CoachEaseReason
            if text.contains("sleep") || text.contains("slept") {
                reason = .poorSleep
            } else if text.contains("tired") || text.contains("fatigue") {
                reason = .tired
            } else {
                reason = .general
            }
            let date = targetDate(in: text, plan: plan, now: now)
                ?? calendar.startOfDay(for: now)
            return .intent(.easeSession(date: date, reason: reason))
        }

        if (text.contains("why") || text.contains("explain"))
            && (text.contains("workout") || text.contains("planned") || text.contains("today")) {
            let date = targetDate(in: text, plan: plan, now: now)
                ?? calendar.startOfDay(for: now)
            return .intent(.explainWorkout(date: date))
        }

        return .unsupported(
            "I can explain planned workouts, summarize recent training, shorten a session, make a future day unavailable, make today's session easier, or help frame a 5K goal."
        )
    }

    private func isRecentTrainingQuestion(_ text: String) -> Bool {
        (text.contains("what changed") || text.contains("training change") || text.contains("recent training"))
            && (text.contains("week") || text.contains("month") || text.contains("recent"))
    }

    private func minuteLimit(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\d{1,3})\s*(?:min|mins|minute|minutes)\b"#,
            options: []
        ) else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let numberRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[numberRange])
    }

    private func weekCount(in text: String) -> Int? {
        let wordNumbers: [(String, Int)] = [
            ("one", 1), ("two", 2), ("three", 3), ("four", 4),
            ("five", 5), ("six", 6), ("seven", 7), ("eight", 8)
        ]
        for (word, number) in wordNumbers where text.contains("\(word) week") {
            return number
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"(\d{1,2})\s*weeks?"#,
            options: []
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let numberRange = Range(match.range(at: 1), in: text),
              let value = Int(text[numberRange]) else {
            return nil
        }
        return min(max(value, 1), 8)
    }

    private func explicitISODate(in text: String) -> Date? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(20\d{2}-\d{2}-\d{2})\b"#,
            options: []
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let dateRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text[dateRange])).map {
            calendar.startOfDay(for: $0)
        }
    }

    private func targetDate(in text: String, plan: WeeklyPlan, now: Date) -> Date? {
        let today = calendar.startOfDay(for: now)
        if text.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        if text.contains("today") {
            return today
        }
        if let explicit = explicitISODate(in: text) {
            return explicit
        }

        for weekday in Weekday.trainingWeek where text.contains(weekday.displayName.lowercased()) {
            return date(for: weekday, in: plan, notBefore: today)
        }
        return nil
    }

    private func date(
        for weekday: Weekday,
        in plan: WeeklyPlan,
        notBefore boundary: Date
    ) -> Date? {
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: plan.startDate) else {
                continue
            }
            let day = calendar.startOfDay(for: date)
            guard day >= boundary, plan.contains(day, calendar: calendar) else { continue }
            if Weekday(date: day, calendar: calendar) == weekday {
                return day
            }
        }
        return nil
    }
}
