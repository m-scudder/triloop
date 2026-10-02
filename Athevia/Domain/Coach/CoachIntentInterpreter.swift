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

        if isRPEDefinitionQuestion(text) {
            return .intent(.explainRPE)
        }

        if isWeekPlanQuestion(text) {
            return .intent(.describeWeek(offset: text.contains("next week") ? 1 : 0))
        }

        if isWorkoutMetricsQuestion(text) {
            guard let date = targetDate(in: text, plan: plan, now: now) else {
                return .clarification("Which workout date should I use?")
            }
            return .intent(.workoutMetrics(date: date))
        }

        if text.contains("5k") || text.contains("5 km") || text.contains("5000m") {
            return .intent(.prepareFor5K(eventDate: explicitISODate(in: text)))
        }

        if text.contains("skip") {
            guard let date = targetDate(in: text, plan: plan, now: now) else {
                return .clarification("Which workout day should I skip?")
            }
            return .intent(.skipSession(date: date))
        }

        if text.contains("move") || text.contains("reschedule") {
            let dates = mentionedDates(in: text, plan: plan, now: now)
            guard dates.count >= 2 else {
                return .clarification("Which workout day should move, and what day should it move to?")
            }
            return .intent(.moveSession(from: dates[0], to: dates[1]))
        }

        if (text.contains("unavailable") || text.contains("not available") || text.contains("week off") || text.contains("time off")) {
            let dates = mentionedDates(in: text, plan: plan, now: now)
            if dates.count >= 2 {
                return .intent(.unavailableRange(start: dates[0], end: dates[1]))
            }
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

    private func isRPEDefinitionQuestion(_ text: String) -> Bool {
        let asksMeaning = text.contains("what is")
            || text.contains("what does")
            || text.contains("meaning")
            || text.contains("define")
            || text.contains("explain")
        return text.contains("rpe") && asksMeaning
    }

    private func isWeekPlanQuestion(_ text: String) -> Bool {
        let asksPlan = text.contains("workout plan")
            || text.contains("training plan")
            || text.contains("week's workout")
            || text.contains("week workout")
            || text.contains("week plan")
        let targetWeek = text.contains("next week")
            || text.contains("this week")
            || text.contains("current week")
        let asksDetails = text.contains("detail")
            || text.contains("show")
            || text.contains("what")
            || text.contains("give")
            || text.contains("plan")
        return asksPlan && targetWeek && asksDetails
    }

    private func isWorkoutMetricsQuestion(_ text: String) -> Bool {
        let asksMetrics = text.contains("metric")
            || text.contains("stats")
            || text.contains("statistics")
            || text.contains("pace")
            || text.contains("speed")
            || text.contains("heart rate")
            || text.contains("distance")
            || text.contains("duration")
            || text.contains("how far")
            || text.contains("how long")
        let referencesWorkout = text.contains("workout")
            || text.contains("run")
            || text.contains("ride")
            || text.contains("cycle")
            || text.contains("swim")
            || text.contains("session")
        return asksMetrics && referencesWorkout
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

    private func explicitNaturalDate(in text: String, now: Date) -> Date? {
        let monthMap: [String: Int] = [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ]

        let patterns = [
            #"\b(\d{1,2})\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)(?:\s+(20\d{2}))?\b"#,
            #"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:,?\s+(20\d{2}))?\b"#
        ]

        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range) else { continue }

            let dayGroup = index == 0 ? 1 : 2
            let monthGroup = index == 0 ? 2 : 1
            guard let dayRange = Range(match.range(at: dayGroup), in: text),
                  let monthRange = Range(match.range(at: monthGroup), in: text),
                  let day = Int(text[dayRange]),
                  let month = monthMap[String(text[monthRange]).lowercased()] else {
                continue
            }

            let year: Int
            if match.numberOfRanges > 3,
               match.range(at: 3).location != NSNotFound,
               let yearRange = Range(match.range(at: 3), in: text),
               let parsedYear = Int(text[yearRange]) {
                year = parsedYear
            } else {
                year = calendar.component(.year, from: now)
            }

            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = year
            components.month = month
            components.day = day
            if let date = calendar.date(from: components) {
                return calendar.startOfDay(for: date)
            }
        }

        return nil
    }

    private func mentionedDates(
        in text: String,
        plan: WeeklyPlan,
        now: Date
    ) -> [Date] {
        var matches: [(offset: Int, date: Date)] = []
        let nsText = text as NSString

        if let regex = try? NSRegularExpression(
            pattern: #"\b(20\d{2}-\d{2}-\d{2})\b"#,
            options: []
        ) {
            let range = NSRange(location: 0, length: nsText.length)
            for match in regex.matches(in: text, range: range) {
                guard let dateRange = Range(match.range(at: 1), in: text) else { continue }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = calendar
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: String(text[dateRange])) {
                    matches.append((match.range.location, calendar.startOfDay(for: date)))
                }
            }
        }

        let today = calendar.startOfDay(for: now)
        for (token, date) in [
            ("today", today),
            ("tomorrow", calendar.date(byAdding: .day, value: 1, to: today))
        ] {
            guard let date else { continue }
            var search = NSRange(location: 0, length: nsText.length)
            while true {
                let found = nsText.range(of: token, options: .caseInsensitive, range: search)
                guard found.location != NSNotFound else { break }
                matches.append((found.location, date))
                let next = found.location + found.length
                search = NSRange(location: next, length: max(nsText.length - next, 0))
            }
        }

        for weekday in Weekday.trainingWeek {
            let token = weekday.displayName.lowercased()
            var search = NSRange(location: 0, length: nsText.length)
            while true {
                let found = nsText.range(of: token, options: .caseInsensitive, range: search)
                guard found.location != NSNotFound else { break }
                if let date = date(for: weekday, in: plan, notBefore: today) {
                    matches.append((found.location, date))
                }
                let next = found.location + found.length
                search = NSRange(location: next, length: max(nsText.length - next, 0))
            }
        }

        var seen: Set<Date> = []
        return matches
            .sorted { $0.offset < $1.offset }
            .map(\.date)
            .filter { seen.insert($0).inserted }
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
        if let natural = explicitNaturalDate(in: text, now: now) {
            return natural
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
