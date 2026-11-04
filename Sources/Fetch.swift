// Network data: weather (wttr.in for location, MET Norway for conditions), market quotes
// (Yahoo Finance) and the aurora forecast (NOAA). Everything is cached in the data folder.

import Foundation

// MARK: - HTTP, cache and JSON helpers

final class DataBox: @unchecked Sendable { var data: Data? }

/// Blocking GET. nil unless the server answers 200.
func httpGet(_ url: URL, userAgent: String = "Mozilla/5.0") -> Data? {
    var req = URLRequest(url: url, timeoutInterval: 12)
    req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    let box = DataBox(), sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { d, r, _ in
        if (r as? HTTPURLResponse)?.statusCode == 200 { box.data = d }
        sem.signal()
    }.resume()
    sem.wait()
    return box.data
}

func modified(_ file: URL) -> Date? { (try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date }

/// A copy younger than `maxAge` from the data folder, else a fresh download, else the old copy.
/// `valid` rejects downloads (and cached copies) that can't be used.
func cached(_ name: String, maxAge: TimeInterval, valid: (Data) -> Bool = { _ in true },
            download: () -> Data?) -> Data? {
    let file = appDir.appendingPathComponent(name)
    let old = (try? Data(contentsOf: file)).flatMap { valid($0) ? $0 : nil }
    if let old, let mod = modified(file), Date().timeIntervalSince(mod) < maxAge { return old }
    if let new = download(), valid(new) {
        try? new.write(to: file)
        return new
    }
    if old != nil { log("\(name): download failed, using the cached copy") }
    return old
}

func json(_ data: Data?) -> Any? { data.flatMap { try? JSONSerialization.jsonObject(with: $0) } }

/// Walks nested JSON, e.g. `dig(root, "chart", "result", 0, "meta")`.
func dig(_ value: Any?, _ path: Any...) -> Any? {
    path.reduce(value) { cur, key in
        if let k = key as? String { return (cur as? [String: Any])?[k] }
        guard let i = key as? Int, let a = cur as? [Any], a.indices.contains(i) else { return nil }
        return a[i]
    }
}

// MARK: - Weather

struct Weather {
    var tempC: Int?
    var feelsC: Int?
    var desc = ""
    var category = "clear"  // clear | partly | cloudy | rain | snow | fog | storm
    var area = ""
    var lat = 59.91, lon = 10.75  // Oslo until we know better
}

/// wttr.in turns DAYWALL_LOCATION (or your IP) into coordinates and a place name; MET Norway
/// (api.met.no, the data behind yr.no) gives the conditions. wttr's own conditions are the fallback.
func fetchWeather() -> Weather? {
    let loc = location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    let data = cached("weather.json", maxAge: 1800, valid: { json($0) != nil }) {
        URL(string: "https://wttr.in/\(loc)?format=j1").flatMap { try? Data(contentsOf: $0) }
    }
    guard let root = json(data) else { return nil }

    var w = Weather()
    if let cur = dig(root, "current_condition", 0) {
        w.tempC = (dig(cur, "temp_C") as? String).flatMap { Int($0) }
        w.feelsC = (dig(cur, "FeelsLikeC") as? String).flatMap { Int($0) }
        w.category = wttrCategory((dig(cur, "weatherCode") as? String).flatMap { Int($0) } ?? 113)
        w.desc = (dig(cur, "weatherDesc", 0, "value") as? String ?? "").trimmingCharacters(in: .whitespaces)
    }
    w.area = dig(root, "nearest_area", 0, "areaName", 0, "value") as? String ?? ""
    if let la = (dig(root, "nearest_area", 0, "latitude") as? String).flatMap({ Double($0) }),
       let lo = (dig(root, "nearest_area", 0, "longitude") as? String).flatMap({ Double($0) }) {
        w.lat = la; w.lon = lo
    }
    if let met = fetchMET(lat: w.lat, lon: w.lon) {
        w.tempC = met.temp; w.feelsC = met.feels; w.desc = met.desc; w.category = met.category
    }
    return w
}

/// Current conditions from MET Norway's locationforecast.
private func fetchMET(lat: Double, lon: Double) -> (temp: Int, feels: Int, desc: String, category: String)? {
    let la = (lat * 10000).rounded() / 10000, lo = (lon * 10000).rounded() / 10000  // MET wants ≤ 4 decimals
    let data = cached("met.json", maxAge: 1800, valid: { d in
        guard let c = dig(json(d), "geometry", "coordinates") as? [Double], c.count >= 2 else { return false }
        return abs(c[0] - lo) < 0.01 && abs(c[1] - la) < 0.01
    }) {
        URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=\(la)&lon=\(lo)")
            .flatMap { httpGet($0, userAgent: "daywall/1.0 github.com/bjornarvikhagen/daywall") }
    }
    guard let series = dig(json(data), "properties", "timeseries") as? [[String: Any]] else {
        log("no MET data, using wttr.in conditions")
        return nil
    }

    // Latest entry at or before now (normally the first one, for the current hour).
    let iso = ISO8601DateFormatter()
    let entry = series.last { (iso.date(from: $0["time"] as? String ?? "") ?? .distantFuture) <= Date() } ?? series.first
    guard let t = dig(entry, "data", "instant", "details", "air_temperature") as? Double else { return nil }
    let symbol = (dig(entry, "data", "next_1_hours", "summary", "symbol_code") as? String)
        ?? (dig(entry, "data", "next_6_hours", "summary", "symbol_code") as? String) ?? "cloudy"

    // Wind chill (Environment Canada / JAG-TI), valid at ≤ 10 °C and > 4.8 km/h.
    let windKmh = (dig(entry, "data", "instant", "details", "wind_speed") as? Double ?? 0) * 3.6
    var feels = t
    if t <= 10 && windKmh > 4.8 {
        let v = pow(windKmh, 0.16)
        feels = 13.12 + 0.6215 * t - 11.37 * v + 0.3965 * t * v
    }
    let base = symbol.replacingOccurrences(of: "_day", with: "").replacingOccurrences(of: "_night", with: "")
        .replacingOccurrences(of: "_polartwilight", with: "")
    return (Int(t.rounded()), Int(feels.rounded()), metDescription(base), metCategory(base))
}

private func metCategory(_ s: String) -> String {
    if s.contains("thunder") { return "storm" }
    if s.contains("snow") || s.contains("sleet") { return "snow" }
    if s.contains("rain") { return "rain" }
    switch s {
    case "clearsky", "fair": return "clear"
    case "partlycloudy": return "partly"
    case "fog": return "fog"
    default: return "cloudy"
    }
}

private let metNorwegian: [String: String] = [
    "clearsky": "Klarvær", "fair": "Lettskyet", "partlycloudy": "Delvis skyet", "cloudy": "Skyet", "fog": "Tåke",
    "rain": "Regn", "lightrain": "Lett regn", "heavyrain": "Kraftig regn",
    "rainshowers": "Regnbyger", "lightrainshowers": "Lette regnbyger", "heavyrainshowers": "Kraftige regnbyger",
    "sleet": "Sludd", "lightsleet": "Lett sludd", "heavysleet": "Kraftig sludd",
    "sleetshowers": "Sluddbyger", "lightsleetshowers": "Lette sluddbyger", "heavysleetshowers": "Kraftige sluddbyger",
    "snow": "Snø", "lightsnow": "Lett snø", "heavysnow": "Kraftig snø",
    "snowshowers": "Snøbyger", "lightsnowshowers": "Lette snøbyger", "heavysnowshowers": "Kraftige snøbyger",
]

/// "lightrainshowersandthunder" → "Light rain showers and thunder" (or the Norwegian name).
private func metDescription(_ s: String) -> String {
    if nb {
        let thunder = s.hasSuffix("andthunder")
        let core = thunder ? String(s.dropLast("andthunder".count)) : s
        if let n = metNorwegian[core] { return thunder ? n + " og torden" : n }
    }
    let fixed = ["clearsky": "Clear sky", "fair": "Fair", "partlycloudy": "Partly cloudy", "cloudy": "Cloudy", "fog": "Fog"]
    if let f = fixed[s] { return f }
    let d = s.replacingOccurrences(of: "andthunder", with: " and thunder")
        .replacingOccurrences(of: "showers", with: " showers")
        .replacingOccurrences(of: "light", with: "light ")
        .replacingOccurrences(of: "heavy", with: "heavy ")
        .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    return capFirst(d)
}

/// wttr.in / WorldWeatherOnline condition codes, only used when MET is unavailable.
private func wttrCategory(_ code: Int) -> String {
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

/// Streak/flake density for the weather texture.
func precipitationIntensity(_ desc: String) -> CGFloat {
    let d = desc.lowercased()
    if d.contains("heavy") || d.contains("kraftig") { return 1.6 }
    if d.contains("light") || d.contains("lett") { return 0.6 }
    return 1
}

// MARK: - Market quotes (Yahoo Finance chart API, cached 10 min)

struct Quote: Codable {
    let label: String
    let symbol: String
    let price: Double
    let prev: Double
    let currency: String
    var change: Double { prev > 0 ? (price / prev - 1) * 100 : 0 }

    var priceText: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = price >= 1000 ? 0 : 2
        f.minimumFractionDigits = price >= 1000 ? 0 : 2
        let n = f.string(from: NSNumber(value: price)) ?? "\(price)"
        return (currency == "USD" && !symbol.hasPrefix("^")) ? "$" + n : n
    }

    var changeText: String { (change >= 0 ? "+" : "−") + String(format: "%.1f%%", abs(change)) }
}

/// Each symbol falls back to its cached quote on its own if its download fails.
func fetchQuotes() -> [Quote] {
    let file = appDir.appendingPathComponent("quotes.json")
    let old = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Quote].self, from: $0) } ?? []
    if let mod = modified(file), Date().timeIntervalSince(mod) < 600, old.map(\.symbol) == tickers.map(\.symbol) {
        return old
    }
    let quotes = tickers.compactMap { t -> Quote? in
        let enc = t.symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-."))) ?? t.symbol
        let meta = dig(json(URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?range=1d&interval=1d")
            .flatMap { httpGet($0) }), "chart", "result", 0, "meta")
        if let price = dig(meta, "regularMarketPrice") as? Double {
            return Quote(label: t.label, symbol: t.symbol, price: price,
                         prev: dig(meta, "chartPreviousClose") as? Double ?? price, currency: dig(meta, "currency") as? String ?? "")
        }
        log("quote fetch failed for \(t.symbol), using cached")
        return old.first { $0.symbol == t.symbol }
    }
    if let d = try? JSONEncoder().encode(quotes) { try? d.write(to: file) }
    return quotes
}

// MARK: - Aurora (NOAA SWPC planetary Kp forecast, cached 1 h)

/// Highest forecast Kp from 3 hours ago to 12 hours ahead.
func fetchKp() -> Double? {
    let data = cached("kp.json", maxAge: 3600) {
        URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json").flatMap { httpGet($0) }
    }
    guard let rows = json(data) as? [[String: Any]] else { return nil }
    let f = formatter("yyyy-MM-dd'T'HH:mm:ss", utc: true)
    let from = now.addingTimeInterval(-3 * 3600), to = now.addingTimeInterval(12 * 3600)
    return rows.compactMap { r -> Double? in
        guard let t = f.date(from: r["time_tag"] as? String ?? ""), t >= from, t <= to else { return nil }
        return (r["kp"] as? NSNumber)?.doubleValue
    }.max()
}

/// 0 = nothing, 1 = possible, 2 = likely. The Kp needed depends on latitude (Oslo ≈ Kp 4 for "possible").
func auroraLevel(kp: Double?, lat: Double) -> Int {
    guard let kp, abs(lat) >= 45 else { return 0 }
    let needed = max(1, (67 - abs(lat)) / 1.75)
    return kp >= needed + 1 ? 2 : kp >= needed ? 1 : 0
}
