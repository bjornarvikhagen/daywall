// The soft colour background: blurred blobs, slow drift, fog, film grain, rain and snow.

import CoreGraphics
import CoreImage

/// Small deterministic RNG so a day's layout is the same on every redraw.
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

private let ciContext = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])

/// `seed` fixes the layout for the day; `drift` (fraction of the day, 0–1) slowly moves the blobs
/// so the background breathes over the day instead of jumping.
func renderBackground(_ p: Palette, w: Int, h: Int, seed: UInt64, drift: CGFloat, fog: Bool) -> CGImage {
    let extent = CGRect(x: 0, y: 0, width: w, height: h)
    let W = CGFloat(w), H = CGFloat(h)
    let diag = (W * W + H * H).squareRoot()
    var img = CIImage(color: ciColor(p.base)).cropped(to: extent)
    var rng = SplitMix(state: seed)

    // Large Gaussian blobs, spread across the width so the whole screen gets variation.
    let order = p.blobs.indices.sorted { _, _ in rng.unit() < 0.5 }
    for (k, i) in order.enumerated() {
        let slot = (CGFloat(k) + rng.range(0.1, 0.9)) / CGFloat(order.count)
        let ph1 = rng.range(0, 2 * .pi), ph2 = rng.range(0, 2 * .pi)
        let x = (slot * 1.3 - 0.15) * W + 0.06 * W * sin(2 * .pi * drift * 3 + ph1)
        let y = (p.ys.map { $0[i] + rng.range(-0.05, 0.05) } ?? rng.range(-0.15, 1.15)) * H
            + (p.ys == nil ? 0.06 : 0.02) * H * cos(2 * .pi * drift * 2 + ph2)
        let blob = CIFilter(name: "CIGaussianGradient", parameters: [
            "inputCenter": CIVector(x: x, y: y),
            "inputColor0": ciColor(p.blobs[i], 0.92),
            "inputColor1": ciColor(p.blobs[i], 0),
            "inputRadius": rng.range(0.22, 0.40) * diag,
        ])!.outputImage!.cropped(to: extent)
        img = blob.composited(over: img)
    }
    img = img.clampedToExtent().applyingGaussianBlur(sigma: Double(min(W, H)) * 0.04).cropped(to: extent)
    if fog {  // softer and paler, like looking through mist
        img = img.clampedToExtent().applyingGaussianBlur(sigma: Double(min(W, H)) * 0.06).cropped(to: extent)
        img = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.16)).cropped(to: extent).composited(over: img)
    }

    // Fine film grain via soft light, so it doesn't wash the colours out.
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

/// Faint rain streaks or snow flakes over the background, under the text.
func drawPrecipitation(_ ctx: CGContext, kind: String, intensity: CGFloat, light: Bool, W: CGFloat, H: CGFloat, seed: UInt64) {
    guard ["rain", "storm", "snow"].contains(kind) else { return }
    var rng = SplitMix(state: seed ^ 0x5EED_F00D)
    if kind == "snow" {
        // White flakes with a faint soft halo so they read on pale backgrounds too.
        for _ in 0..<Int(W * H / 6000 * intensity) {
            let r = H * rng.range(0.0012, 0.0036)
            let a = rng.range(0.55, 0.95)
            let c = CGPoint(x: rng.range(0, W), y: rng.range(0, H))
            ctx.setFillColor(cgColor(light ? "#8EA3BF" : "#FFFFFF", light ? 0.10 : 0.12))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 2.2, y: c.y - r * 2.2, width: r * 4.4, height: r * 4.4))
            ctx.setFillColor(CGColor(gray: 1, alpha: a))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
    } else {
        ctx.setLineCap(.round)
        for _ in 0..<Int(W * H / 6000 * intensity * (kind == "storm" ? 1.4 : 1)) {
            let x = rng.range(0, W), y = rng.range(0, H)
            let len = H * rng.range(0.018, 0.05)
            let a = rng.range(0.10, 0.26)
            ctx.setStrokeColor(light ? cgColor("#3C4E66", a) : CGColor(gray: 1, alpha: a))
            ctx.setLineWidth(max(1, H / 900) * rng.range(0.6, 1.2))
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x - len * 0.18, y: y - len))
            ctx.strokePath()
        }
    }
}
