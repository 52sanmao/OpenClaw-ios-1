import Foundation

struct CronJob: Sendable, Identifiable {
    let id: String
    let name: String
    var enabled: Bool
    let scheduleExpr: String  // cron expr or "every Xm/Xs" for interval jobs
    let scheduleKind: String
    let timeZone: String?
    let nextRun: Date?
    let lastRun: Date?
    let status: RunStatus
    let consecutiveErrors: Int
    let configuredModel: String?
    let taskDescription: String?

    enum RunStatus: Sendable {
        case succeeded, failed, unknown, never
    }

    var nextRunFormatted: String {
        guard let nextRun else { return "\u{2014}" }
        return Formatters.relativeString(for: nextRun)
    }

    var lastRunFormatted: String {
        guard let lastRun else { return "\u{2014}" }
        return Formatters.relativeString(for: lastRun)
    }

    /// Human-readable schedule description from cron expression.
    var scheduleDescription: String {
        // Interval-based jobs (kind: "every") already have readable expr
        if scheduleKind == "every" {
            return scheduleExpr.capitalized
        }

        let parts = scheduleExpr.split(separator: " ")
        guard parts.count >= 5 else { return scheduleExpr }

        let minute = String(parts[0])
        let hour = String(parts[1])
        let dom = String(parts[2])
        let dow = String(parts[4])

        // Every minute
        if minute == "*" && hour == "*" && dom == "*" && dow == "*" {
            return "Every minute"
        }

        // Every N minutes
        if minute.hasPrefix("*/"), hour == "*", dom == "*" {
            let n = minute.dropFirst(2)
            return "Every \(n) min"
        }

        // Every N hours
        if minute != "*", hour.hasPrefix("*/"), dom == "*" {
            let n = hour.dropFirst(2)
            return "Every \(n) hr"
        }

        // Hourly at :MM
        if let m = Int(minute), hour == "*", dom == "*", dow == "*" {
            if m == 0 { return "Every hour" }
            return "Hourly at :\(String(format: "%02d", m))"
        }

        // Daily at HH:MM
        if let h = Int(hour), let m = Int(minute), dom == "*", dow == "*" {
            return "Daily at \(String(format: "%02d:%02d", h, m))"
        }

        // Multiple specific hours (e.g. 0 7,9,11 * * *)
        if minute != "*", hour.contains(","), dom == "*", dow == "*" {
            let hours = hour.split(separator: ",")
            let count = hours.count
            if let first = hours.first, let last = hours.last {
                let m = minute.padding(toLength: 2, withPad: "0", startingAt: 0)
                return "\(count)x daily (\(first):\(m)\u{2013}\(last):\(m))"
            }
        }

        // Specific weekdays
        if dom == "*" && dow != "*" {
            let dayNames = parseDaysOfWeek(dow)
            if let h = Int(hour), let m = Int(minute) {
                return "\(dayNames) at \(String(format: "%02d:%02d", h, m))"
            }
            return dayNames
        }

        return scheduleExpr
    }

    /// Compute all scheduled run times for a given day from the cron expression.
    func scheduledTimes(for date: Date) -> [Date] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)

        // Interval-based: "every Xh", "every Xm"
        if scheduleKind == "every" {
            return intervalTimes(dayStart: dayStart, cal: cal)
        }

        let parts = scheduleExpr.split(separator: " ").map(String.init)
        guard parts.count >= 5 else { return [] }

        let minuteExpr = parts[0]
        let hourExpr = parts[1]

        let minutes = parseCronField(minuteExpr, range: 0...59)
        let hours = parseCronField(hourExpr, range: 0...23)

        var times: [Date] = []
        for h in hours {
            for m in minutes {
                if let t = cal.date(bySettingHour: h, minute: m, second: 0, of: dayStart) {
                    times.append(t)
                }
            }
        }
        return times.sorted()
    }

    private func intervalTimes(dayStart: Date, cal: Calendar) -> [Date] {
        // Parse "every Xh", "every Xm", "every Xs"
        let expr = scheduleExpr.lowercased()
        var intervalSeconds: Int?
        if expr.hasSuffix("h"), let n = Int(expr.dropFirst(6).dropLast()) {
            intervalSeconds = n * 3600
        } else if expr.hasSuffix("m"), let n = Int(expr.dropFirst(6).dropLast()) {
            intervalSeconds = n * 60
        } else if expr.hasSuffix("s"), let n = Int(expr.dropFirst(6).dropLast()) {
            intervalSeconds = n
        }
        guard let interval = intervalSeconds, interval > 0 else { return [] }

        var times: [Date] = []
        var t = dayStart
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        while t < dayEnd {
            times.append(t)
            t = t.addingTimeInterval(Double(interval))
        }
        return times
    }

    let lastError: String?

    init(dto: CronJobDTO) {
        id = dto.id
        name = dto.name
        enabled = dto.enabled
        scheduleKind = dto.schedule.kind
        lastError = dto.state.lastError

        // "every" jobs have everyMs instead of expr
        if let expr = dto.schedule.expr {
            scheduleExpr = expr
        } else if let ms = dto.schedule.everyMs {
            let seconds = ms / 1000
            if seconds >= 3600 {
                scheduleExpr = "every \(seconds / 3600)h"
            } else if seconds >= 60 {
                scheduleExpr = "every \(seconds / 60)m"
            } else {
                scheduleExpr = "every \(seconds)s"
            }
        } else {
            scheduleExpr = dto.schedule.kind
        }
        timeZone = dto.schedule.tz
        nextRun = dto.state.nextRunAtMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        lastRun = dto.state.lastRunAtMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        consecutiveErrors = dto.state.consecutiveErrors ?? 0

        switch dto.state.lastRunStatus {
        case "ok":    status = .succeeded
        case "error": status = .failed
        case .some:   status = .unknown
        case nil:     status = .never
        }

        configuredModel = dto.payload?.model
        taskDescription = dto.payload?.message?.split(separator: "\n").first.map(String.init)
    }

    init(dto: RoutineJobDTO) {
        id = dto.id
        name = dto.name
        enabled = dto.enabled ?? true
        scheduleKind = dto.triggerType ?? "routine"
        lastError = nil
        scheduleExpr = dto.triggerSummary ?? dto.triggerRaw ?? dto.description ?? dto.name
        timeZone = nil
        nextRun = dto.nextFireAt.flatMap(Self.date(from:))
        lastRun = dto.lastRunAt.flatMap(Self.date(from:))
        consecutiveErrors = dto.consecutiveFailures ?? 0

        switch dto.status?.lowercased() {
        case "ok", "success", "succeeded":
            status = .succeeded
        case "error", "failed", "failure":
            status = .failed
        case .some:
            status = .unknown
        case nil:
            status = .never
        }

        configuredModel = nil
        taskDescription = dto.description
    }

    private static func date(from value: String) -> Date? {
        if let numeric = Double(value) {
            if numeric > 10_000_000_000 {
                return Date(timeIntervalSince1970: numeric / 1000)
            }
            return Date(timeIntervalSince1970: numeric)
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

/// Parse a cron field into a set of integer values.
/// Supports: `*`, `*/N`, `N`, `N,M`, `N-M`
private func parseCronField(_ field: String, range: ClosedRange<Int>) -> [Int] {
    if field == "*" {
        return Array(range)
    }
    if field.hasPrefix("*/"), let step = Int(field.dropFirst(2)), step > 0 {
        return stride(from: range.lowerBound, through: range.upperBound, by: step).map { $0 }
    }
    // Comma-separated: "1,5,9"
    if field.contains(",") {
        return field.split(separator: ",").compactMap { Int($0) }.filter { range.contains($0) }
    }
    // Range: "1-5"
    if field.contains("-") {
        let parts = field.split(separator: "-").compactMap { Int($0) }
        if parts.count == 2 { return Array(parts[0]...parts[1]).filter { range.contains($0) } }
    }
    // Single value
    if let n = Int(field), range.contains(n) { return [n] }
    return []
}

private func parseDaysOfWeek(_ expr: String) -> String {
    let map = ["0": "Sun", "1": "Mon", "2": "Tue", "3": "Wed", "4": "Thu", "5": "Fri", "6": "Sat", "7": "Sun"]
    let days = expr.split(separator: ",").compactMap { map[String($0)] }
    if days.isEmpty { return expr }
    return days.joined(separator: ", ")
}
