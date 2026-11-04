// The wallpaper layout: five hairlines, four columns, and everything written in them.
//
//   A: year + month grid      B: week + hero (date, daylight, moon, …)
//   C: colour of the day      D: weather, month, week agenda
//      + markets at the bottom

import CoreGraphics
import CoreText
import Foundation

/// Everything one wallpaper shows, worked out once in main.swift.
struct Scene {
    let palette: Palette
    let weather: Weather?
    let quotes: [Quote]
    let agenda: Agenda?
    let hero: String
    let fxKind: String
    let fxIntensity: CGFloat
    let auroraNote: String?
}

func render(_ scene: Scene, w: Int, h: Int) -> CGImage {
    let W = CGFloat(w), H = CGFloat(h)
    let p = scene.palette

    // Same layout all day (seeded by the date), drifting slowly with the time of day.
    let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
    let seed = UInt64(comps.year! * 10000 + comps.month! * 100 + comps.day!) &* 2654435761
    let drift = CGFloat(now.timeIntervalSince(Calendar.current.startOfDay(for: now)) / 86400)
    let bg = renderBackground(p, w: w, h: h, seed: seed, drift: drift, fog: scene.fxKind == "fog")

    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(bg, in: CGRect(x: 0, y: 0, width: W, height: H))
    ctx.setShouldSmoothFonts(false)
    drawPrecipitation(ctx, kind: scene.fxKind, intensity: scene.fxIntensity, light: luminance(p.base) > 0.5,
                      W: W, H: H, seed: seed ^ UInt64(Int(now.timeIntervalSince1970 / 900)))

    let c = Canvas(ctx: ctx, W: W, H: H, ink: luminance(p.base) < 0.2 ? "#F3F0EA" : "#121212")
    c.drawGrid()
    c.drawCalendar()
    c.drawHero(scene)
    c.drawColour(p)
    c.drawMarkets(scene.quotes)
    let agendaLimit = c.drawWeatherAndMonth(scene)
    if let agenda = scene.agenda { c.drawAgenda(agenda, below: agendaLimit) }
    return ctx.makeImage()!
}

// MARK: - Canvas

enum Align { case left, center, right }

func ctFont(_ name: String, _ size: CGFloat) -> CTFont { CTFontCreateWithName(name as CFString, size, nil) }

/// A drawing surface plus the grid every column is laid out on. Sizes scale with screen height.
struct Canvas {
    let ctx: CGContext
    let W: CGFloat, H: CGFloat
    let ink: String

    var xs: [CGFloat] { (0..<5).map { W * (1.0 / 12 + CGFloat($0) * 5 / 24) } }  // the five hairlines
    var colW: CGFloat { W * 5 / 24 }
    var top: CGFloat { H * 0.172 }
    var bottom: CGFloat { H * 0.83 }
    var hair: CGFloat { max(1, (H / 650).rounded()) }
    var pad: CGFloat { colW * 0.072 }
    var small: CGFloat { H * 0.0135 }  // small text size
    var lead: CGFloat { small * 1.22 }  // line spacing for small text
    var rowStep: CGFloat { H * 0.0385 }  // calendar / markets row spacing
    var fMed: CTFont { ctFont("HelveticaNeue-Medium", small) }
    var fBold: CTFont { ctFont("HelveticaNeue-Bold", small) }
    var capSmall: CGFloat { CTFontGetCapHeight(fMed) }
    var textTop: CGFloat { top + small * 0.15 }

    var inkC: CGColor { cgColor(ink) }
    func inkA(_ a: CGFloat) -> CGColor { cgColor(ink, a) }

    func line(_ s: String, _ f: CTFont, _ color: CGColor, kern: CGFloat = 0) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTKernAttributeName as String): kern,
        ]))
    }

    func width(_ l: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)) }

    /// Text with the top of its capitals at `capTop` (measured from the top of the screen).
    /// With `maxWidth` it's cut off with "…" to fit.
    func text(_ s: String, _ font: CTFont? = nil, color: CGColor? = nil, x: CGFloat, capTop: CGFloat,
              align: Align = .left, kern: CGFloat = 0, maxWidth: CGFloat? = nil) {
        let f = font ?? fMed, col = color ?? inkC
        var l = line(s, f, col, kern: kern)
        if let maxWidth {
            l = CTLineCreateTruncatedLine(l, Double(maxWidth), .end, line("…", f, col)) ?? l
        }
        let px = align == .center ? x - width(l) / 2 : align == .right ? x - width(l) : x
        ctx.textPosition = CGPoint(x: px, y: H - (capTop + CTFontGetCapHeight(f)))
        CTLineDraw(l, ctx)
    }

    func drawGrid() {
        ctx.setFillColor(inkA(0.9))
        for x in xs { ctx.fill(CGRect(x: (x - hair / 2).rounded(), y: H - bottom, width: hair, height: bottom - top)) }
    }
}

// MARK: - Column A: year and month grid

extension Canvas {
    func drawCalendar() {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        text(String(comps.year!), x: xs[0] + pad, capTop: textTop)

        let days = cal.range(of: .day, in: .month, for: date)!
        let first = cal.date(from: DateComponents(year: comps.year, month: comps.month, day: 1))!
        let offset = (cal.component(.weekday, from: first) + 5) % 7  // Monday = 0
        let rows = Int(ceil(Double(offset + days.count) / 7))
        let cs = min(H * 0.0449, (colW - 2 * pad) / 7.1)
        func rowTop(_ r: Int) -> CGFloat { bottom - capSmall - CGFloat(rows - r) * rowStep }

        for (j, d) in (nb ? ["M", "T", "O", "T", "F", "L", "S"] : ["M", "T", "W", "T", "F", "S", "S"]).enumerated() {
            text(d, x: xs[0] + pad + CGFloat(j) * cs, capTop: rowTop(0))
        }
        let markToday = cal.isDate(date, inSameDayAs: now) || arg("--date") != nil
        for day in days {
            let idx = offset + day - 1
            let x = xs[0] + pad + CGFloat(idx % 7) * cs, y = rowTop(idx / 7 + 1)
            if day == comps.day! && markToday {
                text("\(day)", fBold, x: x, capTop: y)
                // small superscript dot marking today, like "4•"
                let dotR = small * 0.13
                ctx.setFillColor(inkC)
                ctx.fillEllipse(in: CGRect(x: x + width(line("\(day)", fBold, inkC)) + small * 0.16,
                                           y: H - y - dotR * 2 - small * 0.02, width: dotR * 2, height: dotR * 2))
            } else {
                text("\(day)", color: inkA(day < comps.day! ? 0.45 : 0.9), x: x, capTop: y)
            }
        }
    }
}

// MARK: - Column B: week number and the hero

extension Canvas {
    func drawHero(_ scene: Scene) {
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: date)
        text("\(L("Week")) \(week)", x: xs[1] + pad, capTop: textTop)
        switch scene.hero {
        case "daylight": drawDaylight(lat: scene.weather?.lat ?? 59.91, lon: scene.weather?.lon ?? 10.75)
        case "moon": drawMoon()
        case "next": drawNextMeeting(scene.agenda)
        case "year": drawYearProgress()
        default: drawDayNumber()
        }
    }

    private var heroCentre: CGFloat { xs[1] + colW / 2 }

    /// Big centred text standing on the bottom line. Returns its cap top.
    @discardableResult
    private func bigText(_ s: String) -> CGFloat {
        let probe = ctFont("HelveticaNeue-Light", 100)
        let capRatio = CTFontGetCapHeight(probe) / 100
        let probeW = width(line(s, probe, inkC, kern: -3)) / 100
        let size = min(H * 0.382 / capRatio, colW * 0.88 / probeW)
        let f = ctFont("HelveticaNeue-Light", size)
        let l = line(s, f, inkC, kern: -size * 0.03)
        ctx.textPosition = CGPoint(x: heroCentre - width(l) / 2, y: H - bottom)
        CTLineDraw(l, ctx)
        return bottom - CTFontGetCapHeight(f)
    }

    /// Small lines under "Week 45".
    private func caption(_ lines: [String]) {
        for (i, s) in lines.enumerated() {
            text(s, x: xs[1] + pad, capTop: textTop + CGFloat(i + 1) * lead, maxWidth: colW - 2 * pad)
        }
    }

    private func captionBottom(_ n: Int) -> CGFloat { textTop + CGFloat(n) * lead + capSmall }

    /// The day number with the weekday spelled out beneath it, left-aligned on the bottom line.
    private func drawDayNumber() {
        let fDay = ctFont("HelveticaNeue-Light", H * 0.043)
        let dayCap = CTFontGetCapHeight(fDay)
        text(capFirst(formatter("EEEE", locale: uiLocale).string(from: date)), fDay, x: xs[1] + pad,
             capTop: bottom - dayCap, kern: -H * 0.0004)
        let s = String(Calendar(identifier: .gregorian).component(.day, from: date))
        let probe = ctFont("HelveticaNeue-Light", 100)
        let probeW = width(line(s, probe, inkC, kern: -3)) / 100
        let size = min(H * 0.23 / (CTFontGetCapHeight(probe) / 100), (colW - 2 * pad) / probeW)
        let f = ctFont("HelveticaNeue-Light", size)
        let l = line(s, f, inkC, kern: -size * 0.03)
        ctx.textPosition = .zero
        let inkLeft = CTLineGetImageBounds(l, ctx).minX  // optical alignment: the stroke, not the side bearing
        ctx.textPosition = CGPoint(x: xs[1] + pad - inkLeft, y: H - (bottom - dayCap - H * 0.045))
        CTLineDraw(l, ctx)
    }

    /// Hours of daylight, with an arc showing where the sun is between sunrise and sunset.
    private func drawDaylight(lat: Double, lon: Double) {
        let hm = formatter("HH:mm")
        let today = sunTimes(on: date, lat: lat, lon: lon)
        let yesterday = sunTimes(on: date.addingTimeInterval(-86400), lat: lat, lon: lon)
        let len = today.map { $0.set.timeIntervalSince($0.rise) } ?? 0
        let delta = Int(((len - (yesterday.map { $0.set.timeIntervalSince($0.rise) } ?? len)) / 60).rounded())
        let mins = Int((len / 60).rounded())
        let bigTop = bigText("\(mins / 60):" + String(format: "%02d", mins % 60))
        caption([L("Daylight"), "\(delta >= 0 ? "+" : "−")\(abs(delta)) \(L("min since yesterday"))"])
        guard let t = today else { return }

        let cx = heroCentre
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
        text(hm.string(from: t.rise), x: cx - r, capTop: horizon + small * 0.9, align: .center)
        text(hm.string(from: t.set), x: cx + r, capTop: horizon + small * 0.9, align: .center)
    }

    /// Tonight's moon, drawn as a lit shape inside a hairline circle.
    private func drawMoon() {
        let p = moonPhase(now)
        let illum = Int(((1 - cos(2 * .pi * p)) / 2 * 100).rounded())
        let daysToFull = Int(((0.5 - p + (p > 0.5 ? 1 : 0)) * synodicMonth).rounded())
        let fullF = DateFormatter()
        fullF.locale = uiLocale
        fullF.setLocalizedDateFormatFromTemplate("MMMd")
        caption([L(moonName(p)), "\(illum)% \(L("illuminated"))",
                 daysToFull == 0 ? L("Full moon tonight")
                     : "\(L("Full moon")) \(fullF.string(from: now.addingTimeInterval(Double(daysToFull) * 86400)))"])

        let r = min(colW * 0.40, (bottom - captionBottom(3) - H * 0.08) / 2)
        let c = CGPoint(x: heroCentre, y: H - (bottom - r))
        let disc = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.setFillColor(inkA(0.07)); ctx.fillEllipse(in: disc)
        ctx.setStrokeColor(inkA(0.9)); ctx.setLineWidth(hair); ctx.strokeEllipse(in: disc)

        // Lit half-disc on one side, closed by the terminator (half an ellipse).
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
            path.addLine(to: CGPoint(x: waxing ? c.x + r * k * cos(th) : c.x - r * k * cos(th), y: c.y + r * sin(th)))
        }
        path.closeSubpath()
        ctx.setFillColor(inkC); ctx.addPath(path); ctx.fillPath()
    }

    /// Start time of the next meeting, or "Free".
    private func drawNextMeeting(_ agenda: Agenda?) {
        guard let m = agenda?.meetings.first(where: { $0.start > now && !$0.allDay }) else {
            bigText(L("Free"))
            caption([L("No more meetings"), (agenda?.heading ?? L("This week")).lowercased()])
            return
        }
        bigText(formatter("HH:mm").string(from: m.start))
        let cal = Calendar.current
        let mins = Int(m.start.timeIntervalSince(now) / 60)
        let when: String
        if cal.isDateInToday(m.start) {
            when = mins < 60 ? "\(capFirst(L("in"))) \(mins) min"
                : "\(capFirst(L("in"))) \(mins / 60) \(nb ? "t" : "h") \(mins % 60) min"
        } else if cal.isDateInTomorrow(m.start) {
            when = L("Tomorrow")
        } else {
            when = capFirst(formatter("EEEE", locale: uiLocale).string(from: m.start))
        }
        caption(["\(L("Next meeting")) · \(when)", m.title])
    }

    /// How much of the year has gone.
    private func drawYearProgress() {
        let cal = Calendar.current
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        let doy = cal.ordinality(of: .day, in: .year, for: date)!
        let total = cal.range(of: .day, in: .year, for: date)!.count
        bigText("\(Int((Double(doy) / Double(total) * 100).rounded()))%")
        caption(nb ? ["av \(year) er gått", "Dag \(doy) av \(total) · \(total - doy) igjen"]
                   : ["of \(year) has passed", "Day \(doy) of \(total) · \(total - doy) left"])
    }
}

// MARK: - Column C: colour of the day and markets

extension Canvas {
    func drawColour(_ p: Palette) {
        for (i, s) in [p.name, p.hex, p.words].enumerated() {
            text(s, x: xs[2] + pad, capTop: textTop + CGFloat(i) * lead)
        }
    }

    /// Bottom-aligned with the calendar.
    func drawMarkets(_ quotes: [Quote]) {
        guard !quotes.isEmpty else { return }
        let left = xs[2] + pad, right = xs[3] - pad
        let valueRight = left + (right - left) * 0.68
        func rowTop(_ r: Int) -> CGFloat { bottom - capSmall - CGFloat(quotes.count - r) * rowStep }
        text(L("Markets"), x: left, capTop: rowTop(0))
        text(formatter("HH:mm").string(from: now), color: inkA(0.55), x: right, capTop: rowTop(0), align: .right)
        for (i, q) in quotes.enumerated() {
            let y = rowTop(i + 1)
            text(q.label, x: left, capTop: y)
            text(q.priceText, x: valueRight, capTop: y, align: .right)
            text(q.changeText, color: inkA(0.75), x: right, capTop: y, align: .right)
        }
    }
}

// MARK: - Column D: weather, month and the week agenda

extension Canvas {
    /// Weather lines at the top and the month in the middle. Returns how far up the agenda may reach.
    func drawWeatherAndMonth(_ scene: Scene) -> CGFloat {
        if let wx = scene.weather, let t = wx.tempC {
            var lines = ["\(t)°  \(wx.desc)"]
            if let f = wx.feelsC, f != t { lines.append("\(L("Feels like")) \(f)°") }
            if !wx.area.isEmpty { lines.append(wx.area) }
            if let note = scene.auroraNote { lines.append(note) }
            for (i, s) in lines.enumerated() { text(s, x: xs[3] + pad, capTop: textTop + CGFloat(i) * lead) }
        }
        let fMonth = ctFont("HelveticaNeue-Light", H * 0.043)
        text(capFirst(formatter("LLLL", locale: uiLocale).string(from: date)), fMonth, x: xs[3] + pad,
             capTop: H * 0.382, kern: -H * 0.0004)
        return H * 0.382 + CTFontGetCapHeight(fMonth) + H * 0.022
    }

    /// Meetings grouped by day, bottom-aligned with the calendar. Finished ones fade, the next one
    /// is bold (with "in 10 min" once it's close), and the earliest rows go first if it doesn't fit.
    func drawAgenda(_ agenda: Agenda, below limit: CGFloat) {
        enum Row { case title(String), day(String, today: Bool), item(time: String, title: String, alpha: CGFloat, bold: Bool, badge: String?) }
        let cal = Calendar.current
        let dayLabel = formatter("EEEE d", locale: uiLocale), hm = formatter("HH:mm")
        let nextIdx = agenda.meetings.firstIndex { $0.end > now && !$0.allDay }

        var rows: [Row] = [.title(agenda.heading)]
        var lastDay: Date?
        for (i, m) in agenda.meetings.enumerated() {
            let d = cal.startOfDay(for: m.start)
            if d != lastDay { rows.append(.day(capFirst(dayLabel.string(from: d)), today: cal.isDate(d, inSameDayAs: now))); lastDay = d }
            rows.append(.item(time: m.allDay ? L("All day") : hm.string(from: m.start), title: m.title,
                              alpha: m.end <= now ? 0.4 : (m.free ? 0.6 : 1), bold: i == nextIdx,
                              badge: i == nextIdx ? reminderBadge(m) : nil))
        }
        if agenda.meetings.isEmpty { rows.append(.item(time: "", title: L("No meetings"), alpha: 0.6, bold: false, badge: nil)) }

        let rowLead = small * 1.6, dayGap = small * 1.2
        func height(_ r: Row, first: Bool) -> CGFloat {
            if first { return 0 }
            if case .day = r { return rowLead + dayGap }
            return rowLead
        }
        func total() -> CGFloat { rows.enumerated().reduce(0) { $0 + height($1.element, first: $1.offset == 0) } }
        let maxHeight = bottom - capSmall - (limit + capSmall + H * 0.06)
        while total() > maxHeight, rows.count > 2 { rows.remove(at: 1) }

        let left = xs[3] + pad, right = xs[4] - pad
        let timeW = width(line("00:00", fMed, inkC)) + small * 1.1
        var y = bottom - capSmall - total()
        for (i, r) in rows.enumerated() {
            y += height(r, first: i == 0)
            switch r {
            case .title(let s):
                text(s, x: left, capTop: y)
            case .day(let s, let today):
                text(s, today ? fBold : fMed, color: inkA(today ? 1 : 0.8), x: left, capTop: y)
            case .item(let time, let title, let alpha, let bold, let badge):
                let f = bold ? fBold : fMed
                text(time, f, color: inkA(alpha), x: left, capTop: y)
                var badgeW: CGFloat = 0
                if let badge {
                    badgeW = width(line(badge, fBold, inkC)) + small * 1.0
                    text(badge, fBold, x: right, capTop: y, align: .right)
                }
                text(title, f, color: inkA(alpha), x: left + timeW, capTop: y, maxWidth: right - left - timeW - badgeW)
            }
        }
    }
}
