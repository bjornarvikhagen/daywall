// Talking to macOS: saving and setting wallpapers, re-applying them on Space switches,
// following sunset with dark mode, and the background watcher.

import AppKit
import ImageIO
import UniformTypeIdentifiers

func writeJPEG(_ img: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.93] as CFDictionary)
    return CGImageDestinationFinalize(dest)
}

func setWallpaper(_ url: URL, on screen: NSScreen) {
    do {
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ])
    } catch {
        log("setDesktopImageURL failed: \(error)")
    }
}

/// macOS only changes the wallpaper of the Space you're on, so put the latest images back when you switch.
func reapplyLast() {
    guard let s = try? String(contentsOf: appDir.appendingPathComponent("last-files"), encoding: .utf8) else { return }
    let paths = s.components(separatedBy: "\n")
    for (i, screen) in NSScreen.screens.enumerated() where i < paths.count && !paths[i].isEmpty {
        let url = URL(fileURLWithPath: paths[i])
        guard fm.fileExists(atPath: url.path), NSWorkspace.shared.desktopImageURL(for: screen) != url else { continue }
        setWallpaper(url, on: screen)
    }
}

/// Switches macOS to dark mode after sunset and back at sunrise. Only acts when the wanted state
/// changes, so flipping it yourself during the day sticks until the next sunrise or sunset.
func syncDarkMode(wantDark: Bool) {
    let state = appDir.appendingPathComponent("last-appearance")
    let want = wantDark ? "dark" : "light"
    guard (try? String(contentsOf: state, encoding: .utf8)) != want else { return }
    try? want.write(to: state, atomically: true, encoding: .utf8)
    var err: NSDictionary?
    NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to \(wantDark)")?
        .executeAndReturnError(&err)
    if let err {
        log("dark mode switch failed; allow daywall under Privacy & Security → Automation → System Events (\(err))")
    } else {
        log("switched to \(want) mode")
    }
}

// MARK: - Watcher (--watch)

/// Runs the one-shot renderer as a child process, one at a time.
final class Watcher {
    let exe: URL
    var running = false
    var pending: [String]?

    init(exe: URL) { self.exe = exe }

    func run(_ args: [String] = []) {
        if running {
            if pending == nil || args.isEmpty { pending = args }  // a full run beats a re-apply
            return
        }
        running = true
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.running = false
                if let next = self.pending { self.pending = nil; self.run(next) }
            }
        }
        do { try p.run() } catch { running = false; log("could not start renderer: \(error)") }
    }
}

/// Stays running (started by the LaunchAgent): redraws every 5 minutes, after wake and when
/// displays change, and re-applies the current images when you switch Space.
func runWatcher() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let w = Watcher(exe: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
    let ws = NSWorkspace.shared.notificationCenter
    ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { w.run() }  // give the network a moment
    }
    ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in w.run() }
    ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
        w.run(["--reapply"])
    }
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                           object: nil, queue: .main) { _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { w.run() }
    }
    Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in w.run() }
    log("watching: every 5 min, after wake, on display and Space changes")
    w.run()
    app.run()
    exit(0)
}
