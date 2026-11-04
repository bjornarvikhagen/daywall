// Command line, environment, data folder, language and a few shared helpers.

import Foundation

let fm = FileManager.default
let env = ProcessInfo.processInfo.environment
let argv = CommandLine.arguments

func arg(_ name: String) -> String? {
    guard let i = argv.firstIndex(of: name), i + 1 < argv.count else { return nil }
    return argv[i + 1]
}

func flag(_ name: String) -> Bool { argv.contains(name) }

/// Caches, renders and the private calendar link live here.
let appDir: URL = {
    let dir = env["DAYWALL_DIR"].map { URL(fileURLWithPath: $0) }
        ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Daywall")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

func formatter(_ format: String, locale: Locale = Locale(identifier: "en_US_POSIX"), utc: Bool = false) -> DateFormatter {
    let f = DateFormatter()
    f.locale = locale
    f.dateFormat = format
    if utc { f.timeZone = TimeZone(identifier: "UTC") }
    return f
}

/// The moment being drawn: now, or `--at "yyyy-MM-dd HH:mm"` for previews.
let now: Date = arg("--at").flatMap { formatter("yyyy-MM-dd HH:mm").date(from: $0) } ?? Date()

/// The day being drawn: today, or `--date yyyy-MM-dd` (at noon).
let date: Date = arg("--date").flatMap { formatter("yyyy-MM-dd").date(from: $0) }?.addingTimeInterval(12 * 3600) ?? now

// MARK: - Settings

let force = flag("--force")
let previewDir = arg("--preview")
let location = arg("--location") ?? env["DAYWALL_LOCATION"] ?? ""

/// What fills the second column: digit (default) | daylight | moon | next | year
let hero = arg("--hero") ?? env["DAYWALL_HERO"] ?? "digit"

/// DAYWALL_TICKERS="Bitcoin=BTC-USD,Nasdaq 100=^NDX" (label=Yahoo symbol, comma separated)
let tickers: [(label: String, symbol: String)] = (env["DAYWALL_TICKERS"] ?? "Bitcoin=BTC-USD,Nasdaq 100=^NDX")
    .split(separator: ",").compactMap {
        let kv = $0.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return kv.count == 2 ? (kv[0], kv[1]) : nil
    }

/// DAYWALL_DARK_MODE=1 follows sunset/sunrise with the system appearance.
let darkModeSync = ["1", "true", "yes", "auto"].contains((env["DAYWALL_DARK_MODE"] ?? "").lowercased())

// MARK: - Language (DAYWALL_LANG=nb for Norwegian, default English)

let nb = (arg("--lang") ?? env["DAYWALL_LANG"] ?? "en").lowercased().hasPrefix("n")
let uiLocale = Locale(identifier: nb ? "nb_NO" : "en_US")

private let norwegian: [String: String] = [
    "Week": "Uke", "Markets": "Marked", "Feels like": "Føles som", "No meetings": "Ingen møter",
    "All day": "Hele dagen", "Untitled": "Uten tittel", "This week": "Denne uken", "Next week": "Neste uke",
    "now": "nå", "in": "om", "Daylight": "Dagslys", "min since yesterday": "min siden i går",
    "New moon": "Nymåne", "Waxing crescent": "Voksende månesigd", "First quarter": "Første kvarter",
    "Waxing gibbous": "Voksende måne", "Full moon": "Fullmåne", "Waning gibbous": "Avtagende måne",
    "Last quarter": "Siste kvarter", "Waning crescent": "Avtagende månesigd", "illuminated": "opplyst",
    "Full moon tonight": "Fullmåne i kveld", "Next meeting": "Neste møte", "Tomorrow": "I morgen",
    "No more meetings": "Ingen flere møter", "Free": "Ledig",
    "Aurora possible tonight": "Mulig nordlys i kveld", "Aurora likely tonight": "Nordlys sannsynlig i kveld",
]

/// Localised UI string (English is the key).
func L(_ en: String) -> String { nb ? (norwegian[en] ?? en) : en }

func capFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

func log(_ s: String) {
    FileHandle.standardError.write("[\(ISO8601DateFormatter().string(from: Date()))] \(s)\n".data(using: .utf8)!)
}
