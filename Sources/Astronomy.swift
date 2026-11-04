// Sun and moon, computed locally from the date and your coordinates.

import Foundation

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

/// Solar elevation in degrees, and whether it is before solar noon.
func sunPosition(at d: Date, lat: Double, lon: Double) -> (elevation: Double, morning: Bool) {
    let rad = Double.pi / 180
    func norm(_ x: Double) -> Double { let r = x.truncatingRemainder(dividingBy: 360); return r < 0 ? r + 360 : r }
    let n = d.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
    let l = norm(280.460 + 0.9856474 * n)
    let g = norm(357.528 + 0.9856003 * n) * rad
    let lambda = (l + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
    let eps = (23.439 - 0.0000004 * n) * rad
    let ra = atan2(cos(eps) * sin(lambda), cos(lambda)) / rad
    let dec = asin(sin(eps) * sin(lambda))
    let gmst = norm(280.46061837 + 360.98564736629 * n)
    var ha = norm(gmst + lon - ra)
    if ha > 180 { ha -= 360 }  // negative = morning
    let el = asin(sin(lat * rad) * sin(dec) + cos(lat * rad) * cos(dec) * cos(ha * rad)) / rad
    return (el, ha < 0)
}

let synodicMonth = 29.530588853

/// Fraction of the lunar cycle: 0 = new, 0.5 = full.
func moonPhase(_ d: Date) -> Double {
    let ref = Date(timeIntervalSince1970: 947182440)  // new moon 2000-01-06 18:14 UTC
    let p = (d.timeIntervalSince(ref) / 86400).truncatingRemainder(dividingBy: synodicMonth) / synodicMonth
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
