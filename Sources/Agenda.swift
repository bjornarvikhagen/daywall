// The week agenda: a published ICS feed (Outlook/Teams, Google, iCloud) parsed and expanded locally.

import Foundation

struct Meeting {
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let free: Bool
}

struct Agenda {
    let heading: String
    let meetings: [Meeting]
}

/// This week's meetings (Mon–Sun); on weekends, next week's.
func loadAgenda() -> Agenda? {
    guard let ics = fetchICS() else { return nil }
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = .current
    let weekend = [1, 7].contains(Calendar.current.component(.weekday, from: date))
    let base = weekend ? cal.date(byAdding: .day, value: 2, to: date)! : date
    guard let week = cal.dateInterval(of: .weekOfYear, for: base) else { return nil }
    return Agenda(heading: weekend ? L("Next week") : L("This week"), meetings: meetings(from: ics, in: week))
}

/// The feed URL comes from DAYWALL_ICS or the private `calendar-url` file. Cached 15 min.
private func fetchICS() -> String? {
    let link = env["DAYWALL_ICS"]
        ?? (try? String(contentsOf: appDir.appendingPathComponent("calendar-url"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let link, !link.isEmpty, let url = URL(string: link) else { return nil }
    let data = cached("calendar.ics", maxAge: 900,
                      valid: { String(data: $0, encoding: .utf8)?.contains("BEGIN:VCALENDAR") == true }) { httpGet(url) }
    return data.flatMap { String(data: $0, encoding: .utf8) }
}

/// "in 10 min" / "now" for the next meeting once it's close. Rounded up to 5 min to match the refresh.
func reminderBadge(_ m: Meeting) -> String? {
    if m.allDay { return nil }
    if m.start <= now && now < m.end { return L("now") }
    let mins = Int(ceil(m.start.timeIntervalSince(now) / 60))
    guard mins > 0, mins <= 15 else { return nil }
    return "\(L("in")) \(Int(ceil(Double(mins) / 5)) * 5) min"
}

// MARK: - ICS parsing

private struct VEvent {
    var uid = "", summary = "", busy = ""
    var start: Date?, end: Date?
    var allDay = false
    var tz = TimeZone.current
    var rrule: [String: String]?
    var exdates: Set<Int> = []
    var recurrenceId: Int?
}

/// Outlook writes Windows time zone names.
private let windowsZones: [String: String] = [
    "W. Europe Standard Time": "Europe/Oslo", "GMT Standard Time": "Europe/London",
    "Romance Standard Time": "Europe/Paris", "Central Europe Standard Time": "Europe/Budapest",
    "Central European Standard Time": "Europe/Warsaw", "FLE Standard Time": "Europe/Helsinki",
    "E. Europe Standard Time": "Europe/Bucharest", "Eastern Standard Time": "America/New_York",
    "Central Standard Time": "America/Chicago", "Pacific Standard Time": "America/Los_Angeles",
    "Singapore Standard Time": "Asia/Singapore", "China Standard Time": "Asia/Shanghai",
    "India Standard Time": "Asia/Kolkata", "Tokyo Standard Time": "Asia/Tokyo", "UTC": "UTC",
]

private func zone(_ tzid: String?) -> TimeZone {
    guard let tzid else { return .current }
    let id = tzid.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return TimeZone(identifier: windowsZones[id] ?? id) ?? .current
}

/// An ICS date value and whether it was date-only (all day).
private func icsDate(_ value: String, tz: TimeZone) -> (Date, Bool)? {
    if value.count == 8 {
        let f = formatter("yyyyMMdd")
        f.timeZone = .current
        return f.date(from: value).map { ($0, true) }
    }
    let f = value.hasSuffix("Z") ? formatter("yyyyMMdd'T'HHmmss'Z'", utc: true) : formatter("yyyyMMdd'T'HHmmss")
    if !value.hasSuffix("Z") { f.timeZone = tz }
    return f.date(from: value).map { ($0, false) }
}

/// "A=1;B=2" → ["A": "1", "B": "2"]
private func pairs(_ items: [Substring]) -> [String: String] {
    Dictionary(items.compactMap { p -> (String, String)? in
        let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
        return kv.count == 2 ? (kv[0], kv[1]) : nil
    }, uniquingKeysWith: { a, _ in a })
}

private func parseEvents(_ ics: String) -> [VEvent] {
    let lines = ics.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")  // unfold
        .components(separatedBy: "\n")
    var events: [VEvent] = []
    var cur: VEvent?
    var pendingEnd: (String, String?)?
    for line in lines {
        if line == "BEGIN:VEVENT" { cur = VEvent(); pendingEnd = nil; continue }
        if line == "END:VEVENT" {
            if var e = cur, let s = e.start {
                if let (v, tzid) = pendingEnd { e.end = icsDate(v, tz: zone(tzid))?.0 }
                if e.end == nil { e.end = e.allDay ? s.addingTimeInterval(86400) : s }
                events.append(e)
            }
            cur = nil
            continue
        }
        guard cur != nil, let colon = line.firstIndex(of: ":") else { continue }
        let head = line[..<colon].split(separator: ";")
        let value = String(line[line.index(after: colon)...])
        let tz = zone(pairs(Array(head.dropFirst()))["TZID"])
        switch head[0] {
        case "UID": cur!.uid = value
        case "SUMMARY":
            cur!.summary = value.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\,", with: ",")
                .replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
        case "X-MICROSOFT-CDO-BUSYSTATUS": cur!.busy = value
        case "DTSTART":
            cur!.tz = tz
            if let (d, dateOnly) = icsDate(value, tz: tz) { cur!.start = d; cur!.allDay = dateOnly }
        case "DTEND": pendingEnd = (value, pairs(Array(head.dropFirst()))["TZID"])
        case "RRULE": cur!.rrule = pairs(value.split(separator: ";"))
        case "EXDATE":
            for v in value.split(separator: ",") {
                if let d = icsDate(String(v), tz: tz)?.0 { cur!.exdates.insert(Int(d.timeIntervalSince1970)) }
            }
        case "RECURRENCE-ID":
            if let d = icsDate(value, tz: tz)?.0 { cur!.recurrenceId = Int(d.timeIntervalSince1970) }
        default: break
        }
    }
    return events
}

// MARK: - Expanding into meetings

func meetings(from ics: String, in window: DateInterval) -> [Meeting] {
    let events = parseEvents(ics)

    // Single occurrences that were moved or edited, keyed by series UID + original start.
    var moved: [String: Set<Int>] = [:]
    for e in events { if let r = e.recurrenceId { moved[e.uid, default: []].insert(r) } }

    var out: [Meeting] = []
    func add(_ e: VEvent, _ s: Date, _ end: Date) {
        guard s < window.end, end > window.start || (end == s && s >= window.start) else { return }
        var t = e.summary.trimmingCharacters(in: .whitespaces)
        if t.rangeOfCharacter(from: .alphanumerics) == nil { t = L("Untitled") }
        if t.hasPrefix("Canceled:") || t.hasPrefix("Cancelled:") || t.hasPrefix("Avlyst:") { return }
        out.append(Meeting(title: t, start: s, end: end, allDay: e.allDay, free: e.busy == "FREE"))
    }

    for e in events {
        guard let s = e.start, let end = e.end else { continue }
        guard let rule = e.rrule, ["WEEKLY", "DAILY", "MONTHLY", "YEARLY"].contains(rule["FREQ"] ?? "") else {
            add(e, s, end)
            continue
        }
        let skip = e.exdates.union(moved[e.uid] ?? [])
        for occ in occurrences(rule, start: s, tz: e.tz, until: window.end)
        where !skip.contains(Int(occ.timeIntervalSince1970)) {
            add(e, occ, occ.addingTimeInterval(end.timeIntervalSince(s)))
        }
    }
    return out.sorted { $0.start < $1.start }
}

/// Start times of a recurring event up to `limit`. Supports FREQ=DAILY/WEEKLY/MONTHLY/YEARLY with
/// INTERVAL, UNTIL, COUNT, BYDAY (incl. ordinals like 2TU / -1FR), BYSETPOS, BYMONTHDAY and BYMONTH.
/// Excluded dates still count towards COUNT, so the caller filters them afterwards.
private func occurrences(_ rule: [String: String], start s: Date, tz: TimeZone, until limit: Date) -> [Date] {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    cal.firstWeekday = 2
    let interval = max(1, Int(rule["INTERVAL"] ?? "1") ?? 1)
    let until = rule["UNTIL"].flatMap { icsDate($0, tz: tz)?.0 }
    let count = rule["COUNT"].flatMap { Int($0) }
    let time = cal.dateComponents([.hour, .minute, .second], from: s)
    let codes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
    let weekdays = rule["BYDAY"]?.split(separator: ",").compactMap { codes[String($0.suffix(2))] }

    var out: [Date] = []
    /// Adds one occurrence; false once we're past UNTIL, COUNT or the window.
    func emit(_ occ: Date) -> Bool {
        if let until, occ > until { return false }
        if let count, out.count >= count { return false }
        if occ > limit { return false }
        out.append(occ)
        return true
    }
    /// That day at the event's start time.
    func at(_ day: Date) -> Date? {
        var dc = cal.dateComponents([.year, .month, .day], from: day)
        dc.hour = time.hour; dc.minute = time.minute; dc.second = time.second
        return cal.date(from: dc)
    }

    switch rule["FREQ"] {
    case "WEEKLY":
        let days = (weekdays ?? [cal.component(.weekday, from: s)]).sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
        var weekStart = cal.dateInterval(of: .weekOfYear, for: s)!.start
        loop: while !days.isEmpty {
            for wd in days {
                guard let occ = at(cal.date(byAdding: .day, value: (wd + 5) % 7, to: weekStart)!), occ >= s else { continue }
                if !emit(occ) { break loop }
            }
            weekStart = cal.date(byAdding: .weekOfYear, value: interval, to: weekStart)!
        }

    case "DAILY":  // with BYDAY=MO,TU,… only those weekdays count
        let allowed = weekdays.map(Set.init)
        var i = 0
        while let occ = cal.date(byAdding: .day, value: i * interval, to: s), occ <= limit {
            i += 1
            if let allowed, !allowed.contains(cal.component(.weekday, from: occ)) { continue }
            if !emit(occ) { break }
        }

    default:  // MONTHLY, YEARLY
        let yearly = rule["FREQ"] == "YEARLY"
        let byMonth = rule["BYMONTH"].map { Set($0.split(separator: ",").compactMap { Int($0) }) }
        let byMonthDay = rule["BYMONTHDAY"]?.split(separator: ",").compactMap { Int($0) }
        let setPos = rule["BYSETPOS"].flatMap { Int($0) }
        let byDay: [(ord: Int?, wd: Int)]? = rule["BYDAY"]?.split(separator: ",").compactMap { tok in
            guard let wd = codes[String(tok.suffix(2))] else { return nil }
            return (Int(tok.dropLast(2)) ?? setPos, wd)
        }
        let firstMonth = cal.date(from: cal.dateComponents([.year, .month], from: s))!
        let startDay = cal.component(.day, from: s), startMonth = cal.component(.month, from: s)
        var month = firstMonth
        var guardCount = 0
        loop: while month <= limit && guardCount < 2400 {
            guardCount += 1
            defer { month = cal.date(byAdding: .month, value: 1, to: month)! }
            let monthsIn = cal.dateComponents([.month], from: firstMonth, to: month).month ?? 0
            let m = cal.component(.month, from: month)
            if yearly {
                guard (monthsIn / 12) % interval == 0, byMonth?.contains(m) ?? (m == startMonth) else { continue }
            } else {
                guard monthsIn % interval == 0 else { continue }
            }
            let n = cal.range(of: .day, in: .month, for: month)!.count
            let days = (0..<n).map { cal.date(byAdding: .day, value: $0, to: month)! }
            var picks: [Date] = []
            if let byDay {
                for (ord, wd) in byDay {
                    let matches = days.filter { cal.component(.weekday, from: $0) == wd }
                    if let o = ord {
                        let idx = o > 0 ? o - 1 : matches.count + o
                        if matches.indices.contains(idx) { picks.append(matches[idx]) }
                    } else {
                        picks += matches
                    }
                }
            } else {
                for d in byMonthDay ?? [startDay] {
                    let idx = d > 0 ? d - 1 : n + d
                    if days.indices.contains(idx) { picks.append(days[idx]) }
                }
            }
            for day in picks.sorted() {
                guard let occ = at(day), occ >= s else { continue }
                if !emit(occ) { break loop }
            }
        }
    }
    return out
}
