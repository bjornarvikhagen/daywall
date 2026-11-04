// Daywall — calendar wallpaper whose colour follows the day and the weather.
//
// Usage: daywall [--force] [--preview DIR] [--size WxH] [--date yyyy-MM-dd]
//                [--weather clear|partly|cloudy|rain|snow|fog|storm] [--night|--day]
//                [--location "Bergen"] [--hero digit|daylight|moon|next|year]
// Env:   DAYWALL_LOCATION  wttr.in location; empty = locate by IP
//        DAYWALL_TICKERS   "Label=YahooSymbol,..." (default Bitcoin + Nasdaq 100)
//        DAYWALL_HERO      what fills the second column (default: digit)
//        DAYWALL_ICS       calendar ICS URL (otherwise read from <data dir>/calendar-url)
//        DAYWALL_DIR       data directory (default ~/Library/Application Support/Daywall)

import AppKit
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Args & paths

let fm = FileManager.default
let appDir = ProcessInfo.processInfo.environment["DAYWALL_DIR"].map { URL(fileURLWithPath: $0) }
    ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Daywall")
try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)

let argv = CommandLine.arguments
func arg(_ name: String) -> String? {
    guard let i = argv.firstIndex(of: name), i + 1 < argv.count else { return nil }
    return argv[i + 1]
}
let force = argv.contains("--force")
let previewDir = arg("--preview")

let now = Date()
var date = now
if let d = arg("--date") {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
    if let parsed = f.date(from: d) { date = parsed.addingTimeInterval(12 * 3600) }
}
let location = arg("--location") ?? ProcessInfo.processInfo.environment["DAYWALL_LOCATION"] ?? ""

func log(_ s: String) {
    FileHandle.standardError.write("[\(ISO8601DateFormatter().string(from: Date()))] \(s)\n".data(using: .utf8)!)
}

// MARK: - Palettes

struct Palette {
    let name: String
    let hex: String
    let words: String
    let base: String
    let blobs: [String]
    let tags: Set<String>
}

let palettes: [Palette] = [
    // Clear
    Palette(name: "Golden Straw", hex: "#E6C16E", words: "Light, abundance, transition",
            base: "#D4B544", blobs: ["#7E2F4F", "#D46A9A", "#E0956A", "#F6F0EE", "#C9B030", "#E2C25A"], tags: ["clear", "partly"]),
    Palette(name: "Apricot Haze", hex: "#F2A97E", words: "Warmth, ease, open sky",
            base: "#F2A97E", blobs: ["#E8664F", "#F7D9A8", "#B8C7E8", "#FDF3E6", "#F08A6C"], tags: ["clear", "partly"]),
    Palette(name: "Clear Cerulean", hex: "#7FB7E0", words: "Clarity, distance, calm",
            base: "#8FC0E6", blobs: ["#2F6FB5", "#F4D9C6", "#CFE6F5", "#F7C8A0", "#5E97CF"], tags: ["clear"]),
    Palette(name: "Citrus Bloom", hex: "#F3D34A", words: "Brightness, zest, momentum",
            base: "#F0D24A", blobs: ["#F39A3A", "#F8F1D0", "#9FD3A8", "#E86F5A", "#F5C33B"], tags: ["clear"]),
    Palette(name: "Coral Noon", hex: "#F08A6C", words: "Energy, heat, presence",
            base: "#F08A6C", blobs: ["#C43D5A", "#FBD4A0", "#F6B8C8", "#FFE9D6", "#E9715E"], tags: ["clear", "partly"]),
    // Cloudy
    Palette(name: "Pewter Mist", hex: "#A7A9B4", words: "Quiet, depth, patience",
            base: "#B4B5BF", blobs: ["#6F7488", "#E6E2DF", "#C9B8C6", "#8D9AA8", "#D8D2CE"], tags: ["cloudy", "partly"]),
    Palette(name: "Lavender Overcast", hex: "#B9AFCF", words: "Softness, reflection, hush",
            base: "#BDB3D3", blobs: ["#7D6FA5", "#ECE6F0", "#D9B6C8", "#9FB3D1", "#C7BCDB"], tags: ["cloudy", "partly"]),
    Palette(name: "Sage Cloud", hex: "#A9B8A2", words: "Calm, growth, stillness",
            base: "#AEBCA7", blobs: ["#6F8A74", "#E9ECE0", "#C8C3A6", "#8EA7A8", "#BFCBB5"], tags: ["cloudy"]),
    Palette(name: "Dove Rose", hex: "#C9A9A6", words: "Tenderness, memory, grace",
            base: "#CBAAA7", blobs: ["#8F5F6A", "#F1E5DF", "#B9B0C9", "#D9B98F", "#D7B7B3"], tags: ["cloudy"]),
    // Rain
    Palette(name: "Storm Teal", hex: "#4F7C82", words: "Depth, renewal, rhythm",
            base: "#557F86", blobs: ["#23414F", "#6F9C9C", "#7C8FA8", "#5F8A8E", "#3E6A72"], tags: ["rain"]),
    Palette(name: "Slate Indigo", hex: "#5B6A9A", words: "Focus, introspection, flow",
            base: "#5F6D9C", blobs: ["#2B2F5A", "#7E8FC0", "#8A6F9E", "#6E7DAE", "#4A578A"], tags: ["rain"]),
    Palette(name: "Wet Moss", hex: "#6E8A6A", words: "Grounded, fresh, patient",
            base: "#708C6C", blobs: ["#2F4A3A", "#B5C9A3", "#8AA3A8", "#D6DCC8", "#5C7A5A"], tags: ["rain"]),
    Palette(name: "Puddle Blue", hex: "#7D98B3", words: "Reflection, softness, cadence",
            base: "#7F9AB5", blobs: ["#3D5A7A", "#D2DDE6", "#9E8FB0", "#B8C9C4", "#6A88A8"], tags: ["rain"]),
    // Snow
    Palette(name: "Frost White", hex: "#E8EDF2", words: "Purity, silence, space",
            base: "#E6EBF1", blobs: ["#B8C8DC", "#FFFFFF", "#D9D2E6", "#C5DBE0", "#A9BCD6"], tags: ["snow"]),
    Palette(name: "Glacier Blue", hex: "#BFD7E6", words: "Crisp, clean, still",
            base: "#C2D8E7", blobs: ["#7FA6C9", "#F6F9FB", "#D6CDE8", "#A9CFD0", "#E8F0F6"], tags: ["snow"]),
    Palette(name: "Icy Lilac", hex: "#D6D0E8", words: "Hush, wonder, light",
            base: "#D8D2E9", blobs: ["#9F93C7", "#F7F4FB", "#BCD4EA", "#E8C9D8", "#C3BBDF"], tags: ["snow"]),
    // Fog
    Palette(name: "Fog Linen", hex: "#D9D4CC", words: "Softness, hush, mystery",
            base: "#D9D4CC", blobs: ["#A59E95", "#F2EFEA", "#C2C6C9", "#CDBFB0", "#E6E2DB"], tags: ["fog"]),
    Palette(name: "Haze Grey", hex: "#C4C7CC", words: "Ambiguity, calm, drift",
            base: "#C5C8CD", blobs: ["#8D939C", "#EEF0F1", "#B9B3AE", "#A9B5B8", "#D6D8DB"], tags: ["fog"]),
    // Storm
    Palette(name: "Thunder Plum", hex: "#5A3F5E", words: "Intensity, charge, drama",
            base: "#5C405F", blobs: ["#241A33", "#A35D7A", "#4F5F8A", "#C08A7A", "#3A2A48"], tags: ["storm"]),
    Palette(name: "Charcoal Surge", hex: "#3E4650", words: "Power, weight, tension",
            base: "#3F4751", blobs: ["#15191F", "#6C7F94", "#8A6A5A", "#A0A8B0", "#2A3038"], tags: ["storm"]),
    // Night
    Palette(name: "Midnight Ink", hex: "#1F2A44", words: "Rest, depth, dreaming",
            base: "#1F2A44", blobs: ["#0C1020", "#3E4F8A", "#6A3F6E", "#2E5A6A", "#141B30"], tags: ["night"]),
    Palette(name: "Aurora Night", hex: "#1E3B3A", words: "Wonder, glow, the north",
            base: "#1B3236", blobs: ["#0A141A", "#2F8F6F", "#4B3F8A", "#1F5F6A", "#0F2226"], tags: ["night"]),
    Palette(name: "Velvet Dusk", hex: "#3A2A4A", words: "Calm, closure, warmth",
            base: "#3A2A4A", blobs: ["#15101F", "#8A4A6A", "#3A4A7A", "#C2706A", "#241A30"], tags: ["night"]),
    Palette(name: "Deep Harbor", hex: "#18323F", words: "Quiet, distance, harbour lights",
            base: "#18323F", blobs: ["#081419", "#2F5F7A", "#A07A4A", "#1F4450", "#0E222B"], tags: ["night"]),
]

// MARK: - Weather (wttr.in, cached 30 min)

struct Weather {
    var tempC: Int?
    var feelsC: Int?
    var desc: String = ""
    var code: Int = 113
    var area: String = ""
    var sunrise: Date?
    var sunset: Date?
    var lat: Double = 59.91  // Oslo fallback
    var lon: Double = 10.75
}

// MARK: - Sun & moon (computed locally)

/// Sunrise/sunset via the standard sunrise equation. nil = polar day/night.
func sunTimes(on day: Date, lat: Double, lon: Double) -> (rise: Date, set: Date)? {
    let rad = Double.pi / 180
    let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
    let jd = noon.timeIntervalSince1970 / 86400 + 2440587.5
    let n = (jd - 2451545.0 + 0.0008).rounded()
    let jStar = n - lon / 360
    let m = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
    let c = 1.9148 * sin(m * rad) + 0.02 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad)
    let l = (m + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
    let transit = 2451545.0 + jStar + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * l * rad)
    let decl = asin(sin(l * rad) * sin(23.4397 * rad))
    let cosW = (sin(-0.833 * rad) - sin(lat * rad) * sin(decl)) / (cos(lat * rad) * cos(decl))
    guard abs(cosW) <= 1 else { return nil }
    let w = acos(cosW) / rad
    func toDate(_ j: Double) -> Date { Date(timeIntervalSince1970: (j - 2440587.5) * 86400) }
    return (toDate(transit - w / 360), toDate(transit + w / 360))
}

let synodic = 29.530588853
/// Fraction of the lunar cycle, 0 = new, 0.5 = full.
func moonPhase(_ d: Date) -> Double {
    let ref = Date(timeIntervalSince1970: 947182440)  // new moon 2000-01-06 18:14 UTC
    let days = d.timeIntervalSince(ref) / 86400
    let p = days.truncatingRemainder(dividingBy: synodic) / synodic
    return p < 0 ? p + 1 : p
}

func moonName(_ p: Double) -> String {
    switch p {
    case ..<0.0339: return "New moon"
    case ..<0.216: return "Waxing crescent"
    case ..<0.284: return "First quarter"
    case ..<0.466: return "Waxing gibbous"
    case ..<0.534: return "Full moon"
    case ..<0.716: return "Waning gibbous"
    case ..<0.784: return "Last quarter"
    case ..<0.966: return "Waning crescent"
    default: return "New moon"
    }
}

func fetchWeather() -> Weather? {
    let cache = appDir.appendingPathComponent("weather.json")
    var data: Data?
    if let mod = (try? fm.attributesOfItem(atPath: cache.path))?[.modificationDate] as? Date,
       Date().timeIntervalSince(mod) < 1800 {
        data = try? Data(contentsOf: cache)
    }
    if data == nil {
        let loc = location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if let url = URL(string: "https://wttr.in/\(loc)?format=j1"),
           let d = try? Data(contentsOf: url),
           (try? JSONSerialization.jsonObject(with: d)) != nil {
            data = d
            try? d.write(to: cache)
        } else {
            log("weather fetch failed, using stale cache if any")
            data = try? Data(contentsOf: cache)
        }
    }
    guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

    var w = Weather()
    if let cur = (root["current_condition"] as? [[String: Any]])?.first {
        w.tempC = Int(cur["temp_C"] as? String ?? "")
        w.feelsC = Int(cur["FeelsLikeC"] as? String ?? "")
        w.code = Int(cur["weatherCode"] as? String ?? "") ?? 113
        w.desc = ((cur["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
    }
    if let area = (root["nearest_area"] as? [[String: Any]])?.first {
        w.area = (area["areaName"] as? [[String: Any]])?.first?["value"] as? String ?? ""
        if let la = Double(area["latitude"] as? String ?? ""), let lo = Double(area["longitude"] as? String ?? "") {
            w.lat = la; w.lon = lo
        }
    }
    if let astro = ((root["weather"] as? [[String: Any]])?.first?["astronomy"] as? [[String: Any]])?.first {
        let tf = DateFormatter(); tf.locale = Locale(identifier: "en_US_POSIX"); tf.dateFormat = "yyyy-MM-dd hh:mm a"
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let day = df.string(from: Date())
        if let s = astro["sunrise"] as? String { w.sunrise = tf.date(from: "\(day) \(s)") }
        if let s = astro["sunset"] as? String { w.sunset = tf.date(from: "\(day) \(s)") }
    }
    return w
}

// MARK: - Market quotes (Yahoo Finance chart API, cached 10 min)

struct Quote: Codable {
    let label: String
    let symbol: String
    let price: Double
    let prev: Double
    let currency: String
    var change: Double { prev > 0 ? (price / prev - 1) * 100 : 0 }
}

final class DataBox: @unchecked Sendable { var data: Data? }

func httpGet(_ url: URL) -> Data? {
    var req = URLRequest(url: url, timeoutInterval: 12)
    req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    let box = DataBox(), sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { d, r, _ in
        if (r as? HTTPURLResponse)?.statusCode == 200 { box.data = d }
        sem.signal()
    }.resume()
    sem.wait()
    return box.data
}

/// DAYWALL_TICKERS="Bitcoin=BTC-USD,Nasdaq 100=^NDX" (label=Yahoo symbol, comma separated)
let tickers: [(String, String)] = (ProcessInfo.processInfo.environment["DAYWALL_TICKERS"]
    ?? "Bitcoin=BTC-USD,Nasdaq 100=^NDX")
    .split(separator: ",").compactMap {
        let kv = $0.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return kv.count == 2 ? (kv[0], kv[1]) : nil
    }

func fetchQuotes() -> [Quote] {
    let cache = appDir.appendingPathComponent("quotes.json")
    let cached = (try? Data(contentsOf: cache)).flatMap { try? JSONDecoder().decode([Quote].self, from: $0) } ?? []
    if let mod = (try? fm.attributesOfItem(atPath: cache.path))?[.modificationDate] as? Date,
       Date().timeIntervalSince(mod) < 600, cached.map(\.symbol) == tickers.map(\.1) {
        return cached
    }
    var out: [Quote] = []
    for (label, symbol) in tickers {
        let enc = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-."))) ?? symbol
        if let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?range=1d&interval=1d"),
           let d = httpGet(url),
           let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let meta = (((root["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first)?["meta"] as? [String: Any],
           let price = meta["regularMarketPrice"] as? Double {
            out.append(Quote(label: label, symbol: symbol, price: price,
                             prev: meta["chartPreviousClose"] as? Double ?? price,
                             currency: meta["currency"] as? String ?? ""))
        } else if let old = cached.first(where: { $0.symbol == symbol }) {
            log("quote fetch failed for \(symbol), using cached")
            out.append(old)
        }
    }
    if let d = try? JSONEncoder().encode(out) { try? d.write(to: cache) }
    return out
}

func formatPrice(_ q: Quote) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US")
    f.maximumFractionDigits = q.price >= 1000 ? 0 : 2
    f.minimumFractionDigits = q.price >= 1000 ? 0 : 2
    let n = f.string(from: NSNumber(value: q.price)) ?? "\(q.price)"
    return (q.currency == "USD" && !q.symbol.hasPrefix("^")) ? "$" + n : n
}

func formatChange(_ q: Quote) -> String {
    let c = q.change
    return (c >= 0 ? "+" : "−") + String(format: "%.1f%%", abs(c))
}

// MARK: - Calendar (published Outlook ICS, cached 15 min)

struct Meeting {
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let free: Bool
}

private struct VEvent {
    var uid = "", summary = "", busy = ""
    var start: Date?, end: Date?
    var allDay = false
    var tz = TimeZone.current
    var rrule: [String: String]?
    var exdates: Set<Int> = []
    var recurrenceId: Int?
}

let windowsZones: [String: String] = [
    "W. Europe Standard Time": "Europe/Oslo", "GMT Standard Time": "Europe/London",
    "Romance Standard Time": "Europe/Paris", "Central Europe Standard Time": "Europe/Budapest",
    "Central European Standard Time": "Europe/Warsaw", "FLE Standard Time": "Europe/Helsinki",
    "E. Europe Standard Time": "Europe/Bucharest", "Eastern Standard Time": "America/New_York",
    "Central Standard Time": "America/Chicago", "Pacific Standard Time": "America/Los_Angeles",
    "Singapore Standard Time": "Asia/Singapore", "China Standard Time": "Asia/Shanghai",
    "India Standard Time": "Asia/Kolkata", "Tokyo Standard Time": "Asia/Tokyo", "UTC": "UTC",
]

func zone(_ tzid: String?) -> TimeZone {
    guard var id = tzid else { return .current }
    id = id.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return TimeZone(identifier: windowsZones[id] ?? id) ?? .current
}

/// Parses an ICS date value. Returns (date, isDateOnly).
func icsDate(_ value: String, tz: TimeZone) -> (Date, Bool)? {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
    if value.count == 8 {
        f.dateFormat = "yyyyMMdd"; f.timeZone = .current
        return f.date(from: value).map { ($0, true) }
    }
    if value.hasSuffix("Z") {
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; f.timeZone = TimeZone(identifier: "UTC")
    } else {
        f.dateFormat = "yyyyMMdd'T'HHmmss"; f.timeZone = tz
    }
    return f.date(from: value).map { ($0, false) }
}

func fetchICS() -> String? {
    let urlStr = ProcessInfo.processInfo.environment["DAYWALL_ICS"]
        ?? (try? String(contentsOf: appDir.appendingPathComponent("calendar-url"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let urlStr, !urlStr.isEmpty, let url = URL(string: urlStr) else { return nil }
    let cache = appDir.appendingPathComponent("calendar.ics")
    if let mod = (try? fm.attributesOfItem(atPath: cache.path))?[.modificationDate] as? Date,
       Date().timeIntervalSince(mod) < 900, let s = try? String(contentsOf: cache, encoding: .utf8) {
        return s
    }
    if let d = httpGet(url), let s = String(data: d, encoding: .utf8), s.contains("BEGIN:VCALENDAR") {
        try? d.write(to: cache, options: .completeFileProtection)
        return s
    }
    log("calendar fetch failed, using stale cache if any")
    return try? String(contentsOf: cache, encoding: .utf8)
}

func meetings(from ics: String, in window: DateInterval) -> [Meeting] {
    let lines = ics.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
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
            cur = nil; continue
        }
        guard cur != nil, let colon = line.firstIndex(of: ":") else { continue }
        let head = line[..<colon], value = String(line[line.index(after: colon)...])
        let parts = head.split(separator: ";").map(String.init)
        let name = parts[0]
        let params = Dictionary(parts.dropFirst().compactMap { p -> (String, String)? in
            let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
            return kv.count == 2 ? (kv[0], kv[1]) : nil
        }, uniquingKeysWith: { a, _ in a })
        switch name {
        case "UID": cur!.uid = value
        case "SUMMARY":
            cur!.summary = value.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\,", with: ",")
                .replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
        case "X-MICROSOFT-CDO-BUSYSTATUS": cur!.busy = value
        case "DTSTART":
            cur!.tz = zone(params["TZID"])
            if let (d, dateOnly) = icsDate(value, tz: cur!.tz) { cur!.start = d; cur!.allDay = dateOnly }
        case "DTEND": pendingEnd = (value, params["TZID"])
        case "RRULE":
            cur!.rrule = Dictionary(value.split(separator: ";").compactMap { p -> (String, String)? in
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.count == 2 ? (kv[0], kv[1]) : nil
            }, uniquingKeysWith: { a, _ in a })
        case "EXDATE":
            for v in value.split(separator: ",") {
                if let d = icsDate(String(v), tz: zone(params["TZID"]))?.0 { cur!.exdates.insert(Int(d.timeIntervalSince1970)) }
            }
        case "RECURRENCE-ID":
            if let d = icsDate(value, tz: zone(params["TZID"]))?.0 { cur!.recurrenceId = Int(d.timeIntervalSince1970) }
        default: break
        }
    }

    // Moved / edited single occurrences, keyed by series UID + original start.
    var overridden: [String: Set<Int>] = [:]
    for e in events where e.recurrenceId != nil { overridden[e.uid, default: []].insert(e.recurrenceId!) }

    var out: [Meeting] = []
    func add(_ e: VEvent, _ s: Date, _ en: Date) {
        guard s < window.end, en > window.start || (en == s && s >= window.start) else { return }
        var t = e.summary.trimmingCharacters(in: .whitespaces)
        if t.rangeOfCharacter(from: .alphanumerics) == nil { t = "Untitled" }
        if t.hasPrefix("Canceled:") || t.hasPrefix("Cancelled:") || t.hasPrefix("Avlyst:") { return }
        out.append(Meeting(title: t, start: s, end: en, allDay: e.allDay, free: e.busy == "FREE"))
    }

    for e in events {
        guard let s = e.start, let en = e.end else { continue }
        guard let rule = e.rrule else { add(e, s, en); continue }

        let dur = en.timeIntervalSince(s)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = e.tz; cal.firstWeekday = 2
        let interval = max(1, Int(rule["INTERVAL"] ?? "1") ?? 1)
        let until = rule["UNTIL"].flatMap { icsDate($0, tz: e.tz)?.0 }
        let count = rule["COUNT"].flatMap { Int($0) }
        let time = cal.dateComponents([.hour, .minute, .second], from: s)
        let skip = e.exdates.union(overridden[e.uid] ?? [])
        var produced = 0

        func emit(_ occ: Date) -> Bool {  // returns false to stop
            if let until, occ > until { return false }
            if let count, produced >= count { return false }
            if occ > window.end { return false }
            produced += 1
            if !skip.contains(Int(occ.timeIntervalSince1970)) { add(e, occ, occ.addingTimeInterval(dur)) }
            return true
        }

        switch rule["FREQ"] {
        case "WEEKLY":
            let codes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
            let days = (rule["BYDAY"]?.split(separator: ",").compactMap { codes[String($0.suffix(2))] }
                ?? [cal.component(.weekday, from: s)]).sorted { (($0 + 5) % 7) < (($1 + 5) % 7) }
            var weekStart = cal.dateInterval(of: .weekOfYear, for: s)!.start
            loop: while !days.isEmpty {
                for wd in days {
                    let offset = (wd + 5) % 7  // Monday = 0
                    var dc = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: offset, to: weekStart)!)
                    dc.hour = time.hour; dc.minute = time.minute; dc.second = time.second
                    guard let occ = cal.date(from: dc), occ >= s else { continue }
                    if !emit(occ) { break loop }
                }
                weekStart = cal.date(byAdding: .weekOfYear, value: interval, to: weekStart)!
            }
        case "DAILY", "MONTHLY", "YEARLY":
            let unit: Calendar.Component = rule["FREQ"] == "DAILY" ? .day : rule["FREQ"] == "MONTHLY" ? .month : .year
            var i = 0
            while let occ = cal.date(byAdding: unit, value: i * interval, to: s), emit(occ) { i += 1 }
        default:
            add(e, s, en)
        }
    }
    return out.sorted { $0.start < $1.start }
}

func category(_ code: Int) -> String {
    switch code {
    case 113: return "clear"
    case 116: return "partly"
    case 119, 122: return "cloudy"
    case 143, 248, 260: return "fog"
    case 200, 386, 389, 392, 395: return "storm"
    case 179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377:
        return "snow"
    default: return "rain"
    }
}

// MARK: - Colour helpers

func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
    var s = hex.trimmingCharacters(in: .whitespaces); if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16) ?? 0
    return (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
}
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func ciColor(_ hex: String, _ a: CGFloat = 1) -> CIColor {
    let (r, g, b) = rgb(hex); return CIColor(red: r, green: g, blue: b, alpha: a, colorSpace: sRGB)!
}
func cgColor(_ hex: String, _ a: CGFloat = 1) -> CGColor {
    let (r, g, b) = rgb(hex); return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func luminance(_ hex: String) -> CGFloat {
    let (r, g, b) = rgb(hex)
    func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }
}

// MARK: - Background

let ciContext = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])

func renderBackground(_ p: Palette, w: Int, h: Int, seed: UInt64) -> CGImage {
    let extent = CGRect(x: 0, y: 0, width: w, height: h)
    let W = CGFloat(w), H = CGFloat(h)
    let diag = (W * W + H * H).squareRoot()
    var img = CIImage(color: ciColor(p.base)).cropped(to: extent)
    var rng = SplitMix(state: seed)

    // Soft colour fields: a few large Gaussian blobs at day-seeded positions.
    let order = p.blobs.indices.sorted { _, _ in rng.unit() < 0.5 }
    for (k, i) in order.enumerated() {
        let c = p.blobs[i]
        // spread blobs across the width so the whole screen gets variation
        let slot = (CGFloat(k) + rng.range(0.1, 0.9)) / CGFloat(order.count)
        let x = (slot * 1.3 - 0.15) * W
        let y = rng.range(-0.15, 1.15) * H
        let r = rng.range(0.22, 0.40) * diag
        let g = CIFilter(name: "CIGaussianGradient", parameters: [
            "inputCenter": CIVector(x: x, y: y),
            "inputColor0": ciColor(c, 0.92),
            "inputColor1": ciColor(c, 0),
            "inputRadius": r,
        ])!.outputImage!.cropped(to: extent)
        img = g.composited(over: img)
    }
    img = img.clampedToExtent().applyingGaussianBlur(sigma: Double(min(W, H)) * 0.04).cropped(to: extent)

    // Fine film grain via soft-light so it does not wash colours out.
    let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: extent).settingAlphaOne(in: extent)
        .applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.10, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0.10, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0.10, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0.45, y: 0.45, z: 0.45, w: 1),
        ]).cropped(to: extent)
    img = noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img])
    return ciContext.createCGImage(img, from: extent, format: .RGBA8, colorSpace: sRGB)!
}

// MARK: - Text

func ctFont(_ name: String, _ size: CGFloat) -> CTFont { CTFontCreateWithName(name as CFString, size, nil) }

enum Align { case left, center, right }

func makeLine(_ s: String, _ f: CTFont, _ color: CGColor, kern: CGFloat = 0) -> CTLine {
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): f,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTKernAttributeName as String): kern,
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
}

func lineWidth(_ l: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)) }

/// Draw so the top of capitals sits at `capTop` (measured from the top of the image).
func draw(_ ctx: CGContext, _ s: String, font f: CTFont, color: CGColor, x: CGFloat, capTop: CGFloat,
          H: CGFloat, align: Align = .left, kern: CGFloat = 0) {
    let l = makeLine(s, f, color, kern: kern)
    let px = align == .center ? x - lineWidth(l) / 2 : align == .right ? x - lineWidth(l) : x
    ctx.textPosition = CGPoint(x: px, y: H - (capTop + CTFontGetCapHeight(f)))
    CTLineDraw(l, ctx)
}

// MARK: - Compose

func render(_ p: Palette, weather: Weather?, w: Int, h: Int) -> CGImage {
    let W = CGFloat(w), H = CGFloat(h)
    let cal = Calendar(identifier: .gregorian)
    let comps = cal.dateComponents([.year, .month, .day], from: date)
    let seed = UInt64(comps.year! * 10000 + comps.month! * 100 + comps.day!) &* 2654435761 &+ UInt64(p.name.hashValue & 0xFFFF)
    let bg = renderBackground(p, w: w, h: h, seed: seed)

    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(bg, in: CGRect(x: 0, y: 0, width: W, height: H))
    ctx.setShouldSmoothFonts(false)

    let dark = luminance(p.base) < 0.2
    let ink = dark ? "#F3F0EA" : "#121212"
    let inkC = cgColor(ink)
    func inkA(_ a: CGFloat) -> CGColor { cgColor(ink, a) }

    // Grid: 5 hairlines → 4 columns.
    let xs = (0..<5).map { W * (1.0 / 12 + CGFloat($0) * 5 / 24) }
    let colW = W * 5 / 24
    let top = H * 0.172, bottom = H * 0.83
    let hair = max(1, (H / 650).rounded())
    ctx.setFillColor(inkA(0.9))
    for x in xs { ctx.fill(CGRect(x: (x - hair / 2).rounded(), y: H - bottom, width: hair, height: bottom - top)) }

    let pad = colW * 0.072
    let small = H * 0.0135
    let fMed = ctFont("HelveticaNeue-Medium", small)
    let fBold = ctFont("HelveticaNeue-Bold", small)
    let lead = small * 1.22
    let capSmall = CTFontGetCapHeight(fMed)
    let textTop = top + small * 0.15

    // Column A — year + month grid
    draw(ctx, String(comps.year!), font: fMed, color: inkC, x: xs[0] + pad, capTop: textTop, H: H)

    let range = cal.range(of: .day, in: .month, for: date)!
    let first = cal.date(from: DateComponents(year: comps.year, month: comps.month, day: 1))!
    let offset = (cal.component(.weekday, from: first) + 5) % 7  // Monday = 0
    let rows = Int(ceil(Double(offset + range.count) / 7))
    let cs = min(H * 0.0449, (colW - 2 * pad) / 7.1)
    let rs = H * 0.0385
    func rowTop(_ r: Int) -> CGFloat { bottom - capSmall - CGFloat(rows - r) * rs }
    for (j, d) in ["M", "T", "W", "T", "F", "S", "S"].enumerated() {
        draw(ctx, d, font: fMed, color: inkC, x: xs[0] + pad + CGFloat(j) * cs, capTop: rowTop(0), H: H)
    }
    let isToday = cal.isDate(date, inSameDayAs: now) || arg("--date") != nil
    for day in range {
        let idx = offset + day - 1
        let r = idx / 7 + 1, c = idx % 7
        let x = xs[0] + pad + CGFloat(c) * cs
        if day == comps.day! && isToday {
            draw(ctx, "\(day)", font: fBold, color: inkC, x: x, capTop: rowTop(r), H: H)
            // small superscript dot marking today, like "4•"
            let w = lineWidth(makeLine("\(day)", fBold, inkC))
            let dotR = small * 0.13
            ctx.setFillColor(inkC)
            ctx.fillEllipse(in: CGRect(x: x + w + small * 0.16, y: H - rowTop(r) - dotR * 2 - small * 0.02,
                                       width: dotR * 2, height: dotR * 2))
        } else {
            draw(ctx, "\(day)", font: fMed, color: inkA(day < comps.day! ? 0.45 : 0.9), x: x, capTop: rowTop(r), H: H)
        }
    }

    // Column B — ISO week + giant day number
    let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: date)
    draw(ctx, "Week \(week)", font: fMed, color: inkC, x: xs[1] + pad, capTop: textTop, H: H)

    // Column B hero. Returns the cap-top (down coords) of the big text.
    @discardableResult
    func bigText(_ s: String) -> CGFloat {
        let probe = ctFont("HelveticaNeue-Light", 100)
        let capRatio = CTFontGetCapHeight(probe) / 100
        let probeW = lineWidth(makeLine(s, probe, inkC, kern: -3)) / 100
        let size = min(H * 0.382 / capRatio, colW * 0.88 / probeW)
        let f = ctFont("HelveticaNeue-Light", size)
        let l = makeLine(s, f, inkC, kern: -size * 0.03)
        ctx.textPosition = CGPoint(x: xs[1] + colW / 2 - lineWidth(l) / 2, y: H - bottom)
        CTLineDraw(l, ctx)
        return bottom - CTFontGetCapHeight(f)
    }
    func caption(_ lines: [String]) {
        for (i, s) in lines.enumerated() {
            let full = makeLine(s, fMed, inkC)
            let l = CTLineCreateTruncatedLine(full, Double(colW - 2 * pad), .end, makeLine("…", fMed, inkC)) ?? full
            ctx.textPosition = CGPoint(x: xs[1] + pad, y: H - (textTop + CGFloat(i + 1) * lead + capSmall))
            CTLineDraw(l, ctx)
        }
    }
    let captionBottom = { (n: Int) in textTop + CGFloat(n) * lead + capSmall }
    let cx = xs[1] + colW / 2
    let hm = DateFormatter(); hm.dateFormat = "HH:mm"

    switch hero {
    case "daylight":
        let lat = weather?.lat ?? 59.91, lon = weather?.lon ?? 10.75
        let today = sunTimes(on: date, lat: lat, lon: lon)
        let yesterday = sunTimes(on: date.addingTimeInterval(-86400), lat: lat, lon: lon)
        let len = today.map { $0.set.timeIntervalSince($0.rise) } ?? 0
        let delta = Int(((len - (yesterday.map { $0.set.timeIntervalSince($0.rise) } ?? len)) / 60).rounded())
        let mins = Int((len / 60).rounded())
        let bigTop = bigText("\(mins / 60):" + String(format: "%02d", mins % 60))
        caption(["Daylight", "\(delta >= 0 ? "+" : "−")\(abs(delta)) min since yesterday"])

        if let t = today {
            let horizon = bigTop - H * 0.07
            let r = min(colW * 0.36, horizon - captionBottom(2) - H * 0.06)
            let hUp = H - horizon
            ctx.setStrokeColor(inkA(0.45)); ctx.setLineWidth(hair)
            ctx.move(to: CGPoint(x: cx - r * 1.18, y: hUp)); ctx.addLine(to: CGPoint(x: cx + r * 1.18, y: hUp)); ctx.strokePath()
            ctx.setStrokeColor(inkA(0.9))
            ctx.addArc(center: CGPoint(x: cx, y: hUp), radius: r, startAngle: .pi, endAngle: 0, clockwise: true); ctx.strokePath()
            let f = CGFloat(now.timeIntervalSince(t.rise) / t.set.timeIntervalSince(t.rise))
            if f > 0 && f < 1 {
                let a = CGFloat.pi * (1 - f)
                ctx.setLineWidth(hair * 3)
                ctx.addArc(center: CGPoint(x: cx, y: hUp), radius: r, startAngle: .pi, endAngle: a, clockwise: true); ctx.strokePath()
                let sr = small * 0.5
                ctx.setFillColor(inkC)
                ctx.fillEllipse(in: CGRect(x: cx + r * cos(a) - sr, y: hUp + r * sin(a) - sr, width: sr * 2, height: sr * 2))
            }
            draw(ctx, hm.string(from: t.rise), font: fMed, color: inkC, x: cx - r, capTop: horizon + small * 0.9, H: H, align: .center)
            draw(ctx, hm.string(from: t.set), font: fMed, color: inkC, x: cx + r, capTop: horizon + small * 0.9, H: H, align: .center)
        }

    case "moon":
        let p = moonPhase(now)
        let illum = Int(((1 - cos(2 * .pi * p)) / 2 * 100).rounded())
        let daysToFull = Int(((0.5 - p + (p > 0.5 ? 1 : 0)) * synodic).rounded())
        let fullF = DateFormatter(); fullF.locale = Locale(identifier: "en_US"); fullF.dateFormat = "MMM d"
        caption([moonName(p), "\(illum)% illuminated",
                 daysToFull == 0 ? "Full moon tonight" : "Full moon \(fullF.string(from: now.addingTimeInterval(Double(daysToFull) * 86400)))"])
        let r = min(colW * 0.40, (bottom - captionBottom(3) - H * 0.08) / 2)
        let c = CGPoint(x: cx, y: H - (bottom - r))
        ctx.setFillColor(inkA(0.07)); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.setStrokeColor(inkA(0.9)); ctx.setLineWidth(hair)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        let k = CGFloat(cos(2 * .pi * p))
        let waxing = p < 0.5
        let path = CGMutablePath()
        if waxing {
            path.addArc(center: c, radius: r, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        } else {
            path.addArc(center: c, radius: r, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
        }
        for i in 0...120 {
            let th = -CGFloat.pi / 2 + .pi * CGFloat(i) / 120
            let x = waxing ? c.x + r * k * cos(th) : c.x - r * k * cos(th)
            path.addLine(to: CGPoint(x: x, y: c.y + r * sin(th)))
        }
        path.closeSubpath()
        ctx.setFillColor(inkC); ctx.addPath(path); ctx.fillPath()

    case "next":
        let upcoming = agenda?.meetings.first { $0.start > now && !$0.allDay }
        if let m = upcoming {
            bigText(hm.string(from: m.start))
            let cal = Calendar.current
            let mins = Int(m.start.timeIntervalSince(now) / 60)
            let when: String
            if cal.isDateInToday(m.start) {
                when = mins < 60 ? "In \(mins) min" : "In \(mins / 60) h \(mins % 60) min"
            } else if cal.isDateInTomorrow(m.start) {
                when = "Tomorrow"
            } else {
                let wf = DateFormatter(); wf.locale = Locale(identifier: "en_US"); wf.dateFormat = "EEEE"
                when = wf.string(from: m.start)
            }
            caption(["Next meeting · \(when)", m.title])
        } else {
            bigText("Free")
            caption(["No more meetings", agenda?.heading.lowercased() ?? "this week"])
        }

    case "year":
        let cal = Calendar.current
        let doy = cal.ordinality(of: .day, in: .year, for: date)!
        let total = cal.range(of: .day, in: .year, for: date)!.count
        bigText("\(Int((Double(doy) / Double(total) * 100).rounded()))%")
        caption(["of \(comps.year!) has passed", "Day \(doy) of \(total) · \(total - doy) left"])

    default:
        // Day number with the weekday spelled out beneath it, left-aligned on the column's bottom line.
        let wf = DateFormatter(); wf.locale = Locale(identifier: "en_US"); wf.dateFormat = "EEEE"
        let fDay = ctFont("HelveticaNeue-Light", H * 0.043)
        let dayCap = CTFontGetCapHeight(fDay)
        draw(ctx, wf.string(from: date), font: fDay, color: inkC, x: xs[1] + pad, capTop: bottom - dayCap, H: H,
             kern: -H * 0.0004)
        let s = String(comps.day!)
        let probe = ctFont("HelveticaNeue-Light", 100)
        let probeW = lineWidth(makeLine(s, probe, inkC, kern: -3)) / 100
        let size = min(H * 0.23 / (CTFontGetCapHeight(probe) / 100), (colW - 2 * pad) / probeW)
        let f = ctFont("HelveticaNeue-Light", size)
        let l = makeLine(s, f, inkC, kern: -size * 0.03)
        ctx.textPosition = .zero
        let inkLeft = CTLineGetImageBounds(l, ctx).minX  // optical align: stroke edge, not side bearing
        ctx.textPosition = CGPoint(x: xs[1] + pad - inkLeft, y: H - (bottom - dayCap - H * 0.045))
        CTLineDraw(l, ctx)
    }

    // Column C — colour of the day
    for (i, s) in [p.name, p.hex, p.words].enumerated() {
        draw(ctx, s, font: fMed, color: inkC, x: xs[2] + pad, capTop: textTop + CGFloat(i) * lead, H: H)
    }

    // Column C bottom — markets, bottom-aligned like the calendar
    if !quotes.isEmpty {
        let left = xs[2] + pad, right = xs[3] - pad
        let valueRight = left + (right - left) * 0.68
        func rTop(_ r: Int) -> CGFloat { bottom - capSmall - CGFloat(quotes.count - r) * rs }
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        draw(ctx, "Markets", font: fMed, color: inkC, x: left, capTop: rTop(0), H: H)
        draw(ctx, tf.string(from: now), font: fMed, color: inkA(0.55), x: right, capTop: rTop(0), H: H, align: .right)
        for (i, q) in quotes.enumerated() {
            let y = rTop(i + 1)
            draw(ctx, q.label, font: fMed, color: inkC, x: left, capTop: y, H: H)
            draw(ctx, formatPrice(q), font: fMed, color: inkC, x: valueRight, capTop: y, H: H, align: .right)
            draw(ctx, formatChange(q), font: fMed, color: inkA(0.75), x: right, capTop: y, H: H, align: .right)
        }
    }

    // Column D — weather, month, weekday
    if let wx = weather, let t = wx.tempC {
        var lines = ["\(t)°  \(wx.desc)"]
        if let f = wx.feelsC, f != t { lines.append("Feels like \(f)°") }
        if !wx.area.isEmpty { lines.append(wx.area) }
        for (i, s) in lines.enumerated() {
            draw(ctx, s, font: fMed, color: inkC, x: xs[3] + pad, capTop: textTop + CGFloat(i) * lead, H: H)
        }
    }
    let monthF = DateFormatter(); monthF.locale = Locale(identifier: "en_US"); monthF.dateFormat = "MMMM"
    let dayF = DateFormatter(); dayF.locale = Locale(identifier: "en_US"); dayF.dateFormat = "EEEE"
    let fMonth = ctFont("HelveticaNeue-Light", H * 0.043)
    draw(ctx, monthF.string(from: date), font: fMonth, color: inkC, x: xs[3] + pad, capTop: H * 0.382, H: H,
         kern: -H * 0.0004)
    _ = dayF  // weekday now lives under the day number in column B
    let weekdayTop = H * 0.382 + CTFontGetCapHeight(fMonth) + H * 0.022

    // Column D bottom — the week's meetings, bottom-aligned with the calendar
    if let agenda {
        enum Row { case title(String), day(String, Bool), item(String, String, CGFloat, Bool) }
        var rows: [Row] = [.title(agenda.heading)]
        let cal = Calendar.current
        let dayLabel = DateFormatter(); dayLabel.locale = Locale(identifier: "en_US"); dayLabel.dateFormat = "EEEE d"
        let hm = DateFormatter(); hm.dateFormat = "HH:mm"
        let nextIdx = agenda.meetings.firstIndex { $0.end > now && !$0.allDay }
        var lastDay: Date?
        for (i, m) in agenda.meetings.enumerated() {
            let d = cal.startOfDay(for: m.start)
            if d != lastDay { rows.append(.day(dayLabel.string(from: d), cal.isDate(d, inSameDayAs: now))); lastDay = d }
            let alpha: CGFloat = m.end <= now ? 0.4 : (m.free ? 0.6 : 1)
            rows.append(.item(m.allDay ? "All day" : hm.string(from: m.start), m.title, alpha, i == nextIdx))
        }
        if agenda.meetings.isEmpty { rows.append(.item("", "No meetings", 0.6, false)) }

        let lead = small * 1.6, dayGap = small * 1.2
        func height(_ r: Row, first: Bool) -> CGFloat {
            if first { return 0 }
            if case .day = r { return lead + dayGap }
            return lead
        }
        let maxHeight = bottom - capSmall - (weekdayTop + capSmall + H * 0.06)
        func total() -> CGFloat { rows.enumerated().reduce(0) { $0 + height($1.element, first: $1.offset == 0) } }
        while total() > maxHeight, rows.count > 2 { rows.remove(at: 1) }  // drop earliest rows first

        let left = xs[3] + pad, right = xs[4] - pad
        let timeW = lineWidth(makeLine("00:00", fMed, inkC)) + small * 1.1
        var y = bottom - capSmall - total()
        for (i, r) in rows.enumerated() {
            y += height(r, first: i == 0)
            switch r {
            case .title(let s):
                draw(ctx, s, font: fMed, color: inkC, x: left, capTop: y, H: H)
            case .day(let s, let today):
                draw(ctx, s, font: today ? fBold : fMed, color: inkA(today ? 1 : 0.8), x: left, capTop: y, H: H)
            case .item(let t, let title, let a, let bold):
                let f = bold ? fBold : fMed
                draw(ctx, t, font: f, color: inkA(a), x: left, capTop: y, H: H)
                let full = makeLine(title, f, inkA(a))
                let line = CTLineCreateTruncatedLine(full, Double(right - left - timeW), .end,
                                                     makeLine("…", f, inkA(a))) ?? full
                ctx.textPosition = CGPoint(x: left + timeW, y: H - (y + CTFontGetCapHeight(f)))
                CTLineDraw(line, ctx)
            }
        }
    }

    return ctx.makeImage()!
}

func writeJPEG(_ img: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.93] as CFDictionary)
    return CGImageDestinationFinalize(dest)
}

// MARK: - Main

let weather = fetchWeather()
let quotes = fetchQuotes()
/// What fills column B: digit (default) | daylight | moon | next | year
let hero = arg("--hero") ?? ProcessInfo.processInfo.environment["DAYWALL_HERO"] ?? "digit"

// This week's meetings (Mon–Sun); on weekends show next week instead.
let agenda: (heading: String, meetings: [Meeting])? = {
    guard let ics = fetchICS() else { return nil }
    var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
    let weekend = [1, 7].contains(Calendar.current.component(.weekday, from: date))
    let base = weekend ? cal.date(byAdding: .day, value: 2, to: date)! : date
    guard let week = cal.dateInterval(of: .weekOfYear, for: base) else { return nil }
    return (weekend ? "Next week" : "This week", meetings(from: ics, in: week))
}()
var cat = arg("--weather") ?? weather.map { category($0.code) } ?? "clear"
var night: Bool = {
    if argv.contains("--night") { return true }
    if argv.contains("--day") { return false }
    if let sr = weather?.sunrise, let ss = weather?.sunset { return now < sr || now > ss }
    let h = Calendar.current.component(.hour, from: now); return h < 7 || h >= 19
}()
let tag = night ? "night" : cat
var candidates = palettes.filter { $0.tags.contains(tag) }
if candidates.isEmpty { candidates = palettes.filter { $0.tags.contains("clear") } }
let dayNumber = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
let palette = candidates[dayNumber % candidates.count]

// Targets: real screens, or a single fake size for previews.
var targets: [(NSScreen?, Int, Int)] = []
if let size = arg("--size") {
    let parts = size.split(separator: "x").compactMap { Int($0) }
    targets = [(nil, parts[0], parts[1])]
} else {
    for s in NSScreen.screens {
        let sc = s.backingScaleFactor
        targets.append((s, Int(s.frame.width * sc), Int(s.frame.height * sc)))
    }
}

let dayKey = Calendar.current.dateComponents([.year, .month, .day], from: date)
let sigParts: [String] = [
    "\(dayKey.year!)-\(dayKey.month!)-\(dayKey.day!)",
    palette.name,
    "\(weather?.tempC ?? 0)/\(weather?.feelsC ?? 0)/\(weather?.desc ?? "")",
    quotes.map { formatPrice($0) + formatChange($0) }.joined(separator: ","),
    (agenda?.meetings ?? []).map { m -> String in "\(m.start.timeIntervalSince1970)\(m.title)\(m.end <= now)" }.joined(),
    targets.map { t -> String in "\(t.1)x\(t.2)" }.joined(separator: ","),
    // daylight (sun position) and next (countdown) change during the day
    hero + (["daylight", "next"].contains(hero) ? "\(Int(now.timeIntervalSince1970 / 900))" : ""),
]
let signature = sigParts.joined(separator: "|")
let stateFile = appDir.appendingPathComponent("last-signature")
if previewDir == nil, !force, (try? String(contentsOf: stateFile, encoding: .utf8)) == signature {
    exit(0)
}

let stamp = Int(now.timeIntervalSince1970)
var written: Set<String> = []
for (i, t) in targets.enumerated() {
    let img = render(palette, weather: weather, w: t.1, h: t.2)
    if let dir = previewDir {
        let url = URL(fileURLWithPath: dir).appendingPathComponent("daywall-\(t.1)x\(t.2)-\(tag)-\(hero).jpg")
        _ = writeJPEG(img, to: url)
        print(url.path)
        continue
    }
    let url = appDir.appendingPathComponent("wall-\(i)-\(stamp).jpg")
    guard writeJPEG(img, to: url), let screen = t.0 else { log("failed to write \(url.path)"); continue }
    written.insert(url.lastPathComponent)
    do {
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ])
    } catch {
        log("setDesktopImageURL failed: \(error)")
    }
}

if previewDir == nil {
    try? signature.write(to: stateFile, atomically: true, encoding: .utf8)
    // Clean up old renders (keep a day's worth so other Spaces don't lose their image abruptly).
    if let files = try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
        for f in files where f.lastPathComponent.hasPrefix("wall-") && !written.contains(f.lastPathComponent) {
            let mod = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(mod) > 6 * 3600 { try? fm.removeItem(at: f) }
        }
    }
    log("set \(palette.name) (\(tag)) on \(written.count) screen(s)")
}
