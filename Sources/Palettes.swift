// The colours: named palettes per weather, the sun-following sky, and how one is picked.

import CoreGraphics
import CoreImage
import Foundation

struct Palette {
    let name: String
    let hex: String
    let words: String
    let base: String
    let blobs: [String]
    let tags: Set<String>
    /// Optional vertical position per blob (0 = bottom, 1 = top), used by the sky palettes
    /// so the warm colours sit at the horizon and the blues overhead.
    var ys: [CGFloat]? = nil
}

/// One palette per line: name, hex, mood words, base colour, blob colours, weather tags.
func P(_ name: String, _ hex: String, _ words: String, _ base: String, _ blobs: String, _ tags: String,
       ys: [CGFloat]? = nil) -> Palette {
    Palette(name: name, hex: hex, words: words, base: base, blobs: blobs.split(separator: " ").map(String.init),
            tags: Set(tags.split(separator: " ").map(String.init)), ys: ys)
}

/// Night palettes after dark (Aurora Night when it's likely and the sky is clear), the sun-following
/// sky on clear days, otherwise the weather's family tinted by the time of day. The date picks
/// which palette within a family, so the same weather looks different from day to day.
func choosePalette(category: String, night: Bool, elevation: Double, morning: Bool, auroraLikely: Bool) -> (palette: Palette, tag: String) {
    let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
    if night {
        let nights = palettes.filter { $0.tags.contains("night") }
        if auroraLikely && ["clear", "partly"].contains(category) {
            return (nights.first { $0.name == "Aurora Night" } ?? nights[0], "night")
        }
        return (nights[day % nights.count], "night")
    }
    if category == "clear" { return (skyPalette(elevation: elevation, morning: morning), "sky") }
    var family = palettes.filter { $0.tags.contains(category) }
    if family.isEmpty { family = palettes.filter { $0.tags.contains("clear") } }
    return (sunTinted(family[day % family.count], elevation: elevation, morning: morning), category)
}

// MARK: - Clear sky, by sun height

let skyBlueHour = P("Blue Hour", "#2E3A6B", "Stillness, cool, in between", "#2E3A6B", "#141A3D #34427E #6C64A0 #C2879A #E3A584", "",
              ys: [1.05, 0.75, 0.42, 0.12, -0.08])
let skyFirstLight = P("First Light", "#F2C6C2", "Waking, soft, promise", "#C9C6E0", "#8FA6D6 #B4B6E0 #F0C4C4 #F7D7B0 #FFF0DF", "",
              ys: [1.05, 0.72, 0.38, 0.12, -0.08])
let skyGoldenHour = P("Golden Hour", "#F2A070", "Warmth, glow, ending", "#EBA880", "#6E80BA #C48AAA #F09A6C #F6C064 #FBE2AE", "",
              ys: [1.08, 0.74, 0.40, 0.14, -0.08])
let skyLowSun = P("Low Sun", "#A9C4E4", "Crisp, long shadows, clarity", "#A9C4E4", "#5A8CCE #86AFE0 #C6DAEE #F1D2B6 #F8E7D3", "",
              ys: [1.05, 0.74, 0.46, 0.16, -0.06])
let skyHighSun = P("Clear Cerulean", "#7FB7E0", "Clarity, distance, calm", "#8FC0E6", "#2F6FB5 #4F8FD0 #8FC0E6 #D3E7F5 #F4F1EA", "",
              ys: [1.08, 0.80, 0.52, 0.22, -0.05])

/// Clear sky colour for a solar elevation, blended smoothly between keyframes.
func skyPalette(elevation e: Double, morning: Bool) -> Palette {
    let frames: [(Double, Palette)] = [
        (-2, skyBlueHour), (3, morning ? skyFirstLight : skyGoldenHour), (12, skyLowSun), (28, skyHighSun),
    ]
    if e <= frames[0].0 { return frames[0].1 }
    for i in 0..<(frames.count - 1) where e < frames[i + 1].0 {
        let t = smoothstep(clamp01((e - frames[i].0) / (frames[i + 1].0 - frames[i].0)))
        return blend(frames[i].1, frames[i + 1].1, t)
    }
    return frames[frames.count - 1].1
}

/// Other weather keeps its colours but warms up around sunrise/sunset and dims through dusk.
func sunTinted(_ p: Palette, elevation e: Double, morning: Bool) -> Palette {
    let warm = e >= 0 ? 0.30 * clamp01(1 - e / 8) : 0.30 * clamp01(1 + e / 3)
    var q = tint(p, toward: morning ? "#D9A3B0" : "#DC9C72", warm)
    if e < 0 { q = tint(q, toward: "#2B3460", 0.6 * clamp01(-e / 6)) }
    return q
}

// MARK: - Weather families

let palettes: [Palette] = [
    // Clear
    P("Golden Straw", "#E6C16E", "Light, abundance, transition", "#D4B544", "#7E2F4F #D46A9A #E0956A #F6F0EE #C9B030 #E2C25A", "clear partly"),
    P("Apricot Haze", "#F2A97E", "Warmth, ease, open sky", "#F2A97E", "#E8664F #F7D9A8 #B8C7E8 #FDF3E6 #F08A6C", "clear partly"),
    P("Clear Cerulean", "#7FB7E0", "Clarity, distance, calm", "#8FC0E6", "#2F6FB5 #F4D9C6 #CFE6F5 #F7C8A0 #5E97CF", "clear"),
    P("Citrus Bloom", "#F3D34A", "Brightness, zest, momentum", "#F0D24A", "#F39A3A #F8F1D0 #9FD3A8 #E86F5A #F5C33B", "clear"),
    P("Coral Noon", "#F08A6C", "Energy, heat, presence", "#F08A6C", "#C43D5A #FBD4A0 #F6B8C8 #FFE9D6 #E9715E", "clear partly"),
    // Cloudy
    P("Pewter Mist", "#A7A9B4", "Quiet, depth, patience", "#B4B5BF", "#6F7488 #E6E2DF #C9B8C6 #8D9AA8 #D8D2CE", "cloudy partly"),
    P("Lavender Overcast", "#B9AFCF", "Softness, reflection, hush", "#BDB3D3", "#7D6FA5 #ECE6F0 #D9B6C8 #9FB3D1 #C7BCDB", "cloudy partly"),
    P("Sage Cloud", "#A9B8A2", "Calm, growth, stillness", "#AEBCA7", "#6F8A74 #E9ECE0 #C8C3A6 #8EA7A8 #BFCBB5", "cloudy"),
    P("Dove Rose", "#C9A9A6", "Tenderness, memory, grace", "#CBAAA7", "#8F5F6A #F1E5DF #B9B0C9 #D9B98F #D7B7B3", "cloudy"),
    // Rain
    P("Storm Teal", "#4F7C82", "Depth, renewal, rhythm", "#557F86", "#23414F #6F9C9C #7C8FA8 #5F8A8E #3E6A72", "rain"),
    P("Slate Indigo", "#5B6A9A", "Focus, introspection, flow", "#5F6D9C", "#2B2F5A #7E8FC0 #8A6F9E #6E7DAE #4A578A", "rain"),
    P("Wet Moss", "#6E8A6A", "Grounded, fresh, patient", "#708C6C", "#2F4A3A #B5C9A3 #8AA3A8 #D6DCC8 #5C7A5A", "rain"),
    P("Puddle Blue", "#7D98B3", "Reflection, softness, cadence", "#7F9AB5", "#3D5A7A #D2DDE6 #9E8FB0 #B8C9C4 #6A88A8", "rain"),
    // Snow
    P("Frost White", "#E8EDF2", "Purity, silence, space", "#E6EBF1", "#B8C8DC #FFFFFF #D9D2E6 #C5DBE0 #A9BCD6", "snow"),
    P("Glacier Blue", "#BFD7E6", "Crisp, clean, still", "#C2D8E7", "#7FA6C9 #F6F9FB #D6CDE8 #A9CFD0 #E8F0F6", "snow"),
    P("Icy Lilac", "#D6D0E8", "Hush, wonder, light", "#D8D2E9", "#9F93C7 #F7F4FB #BCD4EA #E8C9D8 #C3BBDF", "snow"),
    // Fog
    P("Fog Linen", "#D9D4CC", "Softness, hush, mystery", "#D9D4CC", "#A59E95 #F2EFEA #C2C6C9 #CDBFB0 #E6E2DB", "fog"),
    P("Haze Grey", "#C4C7CC", "Ambiguity, calm, drift", "#C5C8CD", "#8D939C #EEF0F1 #B9B3AE #A9B5B8 #D6D8DB", "fog"),
    // Storm
    P("Thunder Plum", "#5A3F5E", "Intensity, charge, drama", "#5C405F", "#241A33 #A35D7A #4F5F8A #C08A7A #3A2A48", "storm"),
    P("Charcoal Surge", "#3E4650", "Power, weight, tension", "#3F4751", "#15191F #6C7F94 #8A6A5A #A0A8B0 #2A3038", "storm"),
    // Night
    P("Midnight Ink", "#1F2A44", "Rest, depth, dreaming", "#1F2A44", "#0C1020 #3E4F8A #6A3F6E #2E5A6A #141B30", "night"),
    P("Aurora Night", "#1E3B3A", "Wonder, glow, the north", "#1B3236", "#0A141A #2F8F6F #4B3F8A #1F5F6A #0F2226", "night"),
    P("Velvet Dusk", "#3A2A4A", "Calm, closure, warmth", "#3A2A4A", "#15101F #8A4A6A #3A4A7A #C2706A #241A30", "night"),
    P("Deep Harbor", "#18323F", "Quiet, distance, harbour lights", "#18323F", "#081419 #2F5F7A #A07A4A #1F4450 #0E222B", "night"),
]

// MARK: - Colour maths

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
    let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0
    return (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
}

func ciColor(_ hex: String, _ a: CGFloat = 1) -> CIColor {
    let (r, g, b) = rgb(hex)
    return CIColor(red: r, green: g, blue: b, alpha: a, colorSpace: sRGB)!
}

func cgColor(_ hex: String, _ a: CGFloat = 1) -> CGColor {
    let (r, g, b) = rgb(hex)
    return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func luminance(_ hex: String) -> CGFloat {
    let (r, g, b) = rgb(hex)
    func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

func mix(_ a: String, _ b: String, _ t: CGFloat) -> String {
    let (r1, g1, b1) = rgb(a), (r2, g2, b2) = rgb(b)
    func c(_ x: CGFloat, _ y: CGFloat) -> Int { Int((min(max(x + (y - x) * t, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", c(r1, r2), c(g1, g2), c(b1, b2))
}

func clamp01(_ x: Double) -> CGFloat { CGFloat(min(max(x, 0), 1)) }
func smoothstep(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }

func blend(_ a: Palette, _ b: Palette, _ t: CGFloat) -> Palette {
    let named = t < 0.5 ? a : b
    var ys: [CGFloat]? = nil
    if let ya = a.ys, let yb = b.ys { ys = zip(ya, yb).map { $0 + ($1 - $0) * t } }
    return Palette(name: named.name, hex: named.hex, words: named.words, base: mix(a.base, b.base, t),
                   blobs: zip(a.blobs, b.blobs).map { mix($0, $1, t) }, tags: named.tags, ys: ys)
}

func tint(_ p: Palette, toward c: String, _ amount: CGFloat) -> Palette {
    guard amount > 0 else { return p }
    return Palette(name: p.name, hex: p.hex, words: p.words, base: mix(p.base, c, amount),
                   blobs: p.blobs.map { mix($0, c, amount) }, tags: p.tags, ys: p.ys)
}
