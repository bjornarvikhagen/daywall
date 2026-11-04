// daywall — a calendar wallpaper for macOS whose colour follows the day and the weather.
//
// Usage: daywall [--force] [--preview DIR] [--size WxH] [--date yyyy-MM-dd] [--at "yyyy-MM-dd HH:mm"]
//                [--weather clear|partly|cloudy|rain|snow|fog|storm] [--night|--day] [--kp N]
//                [--location "Bergen"] [--hero digit|daylight|moon|next|year] [--lang nb] [--dump-agenda]
//        daywall --watch     stay running: redraw every 5 min, after wake, on display/Space changes
//        daywall --reapply   put the latest images back on the current Space
// Env:   DAYWALL_LOCATION  wttr.in location; empty = locate by IP
//        DAYWALL_TICKERS   "Label=YahooSymbol,..." (default Bitcoin + Nasdaq 100)
//        DAYWALL_HERO      what fills the second column (default: digit)
//        DAYWALL_ICS       calendar ICS URL (otherwise read from <data dir>/calendar-url)
//        DAYWALL_LANG      nb = Norwegian labels (default English)
//        DAYWALL_DARK_MODE 1 = switch macOS to dark mode at sunset, light at sunrise
//        DAYWALL_DIR       data directory (default ~/Library/Application Support/Daywall)
//
// Files: Config (settings), Fetch (weather, quotes, aurora), Agenda (calendar), Astronomy (sun, moon),
//        Palettes (colours), Background, Layout (the columns), System (wallpaper, dark mode, watcher).

import AppKit

if flag("--watch") { runWatcher() }
if flag("--reapply") { reapplyLast(); exit(0) }

let weather = fetchWeather()
let quotes = fetchQuotes()
let agenda = loadAgenda()

if flag("--dump-agenda") {
    let f = formatter("EEE yyyy-MM-dd HH:mm")
    for m in agenda?.meetings ?? [] { print(f.string(from: m.start), m.allDay ? "(all day)" : "", m.title) }
    exit(0)
}

// Where the sun is decides night, the clear-sky colour and the dusk tint.
let category = arg("--weather") ?? weather?.category ?? "clear"
let lat = weather?.lat ?? 59.91, lon = weather?.lon ?? 10.75
let sun = sunPosition(at: now, lat: lat, lon: lon)
let elevation = flag("--day") ? max(sun.elevation, 20) : sun.elevation
let night = flag("--night") || (!flag("--day") && sun.elevation < -6)

let kp = arg("--kp").flatMap { Double($0) } ?? fetchKp()
let aurora = auroraLevel(kp: kp, lat: lat)
let auroraNote = aurora == 0 ? nil
    : "\(L(aurora == 2 ? "Aurora likely tonight" : "Aurora possible tonight")) · Kp \(Int(kp!.rounded()))"

let (palette, tag) = choosePalette(category: category, night: night, elevation: elevation,
                                   morning: sun.morning, auroraLikely: aurora == 2)
let scene = Scene(palette: palette, weather: weather, quotes: quotes, agenda: agenda, hero: hero,
                  fxKind: arg("--fx") ?? category, fxIntensity: precipitationIntensity(weather?.desc ?? ""),
                  auroraNote: auroraNote)

if previewDir == nil, darkModeSync {
    syncDarkMode(wantDark: flag("--night") || (!flag("--day") && sun.elevation < -0.833))
}

// One image per display, or a single fake size for previews.
let targets: [(screen: NSScreen?, w: Int, h: Int)] = arg("--size").map { size in
    let wh = size.split(separator: "x").compactMap { Int($0) }
    return [(nil, wh[0], wh[1])]
} ?? NSScreen.screens.map { s in
    (s, Int(s.frame.width * s.backingScaleFactor), Int(s.frame.height * s.backingScaleFactor))
}

// Skip the redraw when nothing on screen would change.
let meetingSoon = (agenda?.meetings ?? []).contains { reminderBadge($0) != nil }
let signature = [
    formatter("yyyy-M-d").string(from: date),
    palette.name + palette.base,
    "\(weather?.tempC ?? 0)/\(weather?.feelsC ?? 0)/\(weather?.desc ?? "")",
    quotes.map { $0.priceText + $0.changeText }.joined(separator: ","),
    (agenda?.meetings ?? []).map { "\($0.start.timeIntervalSince1970)\($0.title)\($0.end <= now)" }.joined(),
    targets.map { "\($0.w)x\($0.h)" }.joined(separator: ","),
    hero, auroraNote ?? "",
    "\(Int(now.timeIntervalSince1970 / 900))",  // slow drift + sky blend: redraw every 15 min
    meetingSoon ? "\(Int(now.timeIntervalSince1970 / 300))" : "",  // the reminder counts down in 5 min steps
].joined(separator: "|")
let stateFile = appDir.appendingPathComponent("last-signature")
if previewDir == nil, !force, (try? String(contentsOf: stateFile, encoding: .utf8)) == signature {
    exit(0)
}

var written: [String] = []
for (i, t) in targets.enumerated() {
    let img = render(scene, w: t.w, h: t.h)
    if let dir = previewDir {
        let url = URL(fileURLWithPath: dir)
            .appendingPathComponent("daywall-\(t.w)x\(t.h)-\(tag)-\(hero)-\(formatter("HHmm").string(from: now)).jpg")
        _ = writeJPEG(img, to: url)
        print(url.path)
        continue
    }
    let url = appDir.appendingPathComponent("wall-\(i)-\(Int(now.timeIntervalSince1970)).jpg")
    guard writeJPEG(img, to: url), let screen = t.screen else { log("failed to write \(url.path)"); written.append(""); continue }
    written.append(url.path)
    setWallpaper(url, on: screen)
}

if previewDir == nil {
    try? signature.write(to: stateFile, atomically: true, encoding: .utf8)
    try? written.joined(separator: "\n").write(to: appDir.appendingPathComponent("last-files"), atomically: true, encoding: .utf8)
    // Clean up old renders, keeping a few hours' worth.
    let keep = Set(written.map { URL(fileURLWithPath: $0).lastPathComponent })
    for f in (try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)) ?? []
    where f.lastPathComponent.hasPrefix("wall-") && !keep.contains(f.lastPathComponent) {
        if Date().timeIntervalSince(modified(f) ?? .distantPast) > 3 * 3600 { try? fm.removeItem(at: f) }
    }
    log("set \(palette.name) (\(tag), sun \(Int(sun.elevation.rounded()))°) on \(written.filter { !$0.isEmpty }.count) screen(s)")
}
