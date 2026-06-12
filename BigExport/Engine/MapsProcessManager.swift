import AppKit

enum MapsProcessManager {
    static var isMapsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Maps").isEmpty
    }

    /// Quit Maps and wait until it's fully gone (up to 10s).
    static func quitMaps() async {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Maps")
            .forEach { $0.terminate() }
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(200))
            if !isMapsRunning { return }
        }
    }

    /// Launch Maps and wait until the DB is writable (up to 15s).
    static func launchMaps() async {
        NSWorkspace.shared.open(URL(string: "maps://")!)
        for _ in 0..<75 {
            try? await Task.sleep(for: .milliseconds(200))
            if isMapsRunning { return }
        }
    }
}
