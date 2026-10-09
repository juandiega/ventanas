import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = SwitcherController()
    private var tap: HotkeyTap?
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let settings = SettingsWindowController()
    private var permissionTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppRecency.shared
        setUpMenu()
        restoreSystemSwitcherOnSignals()
        NotificationCenter.default.addObserver(
            forName: .preferencesChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.applyHotkeyMode() }
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startTap()
        } else {
            statusLine.title = "Waiting for Accessibility permission…"
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                MainActor.assumeIsolated {
                    guard AXIsProcessTrusted() else { return }
                    timer.invalidate()
                    (NSApp.delegate as? AppDelegate)?.startTap()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemSwitcher.setEnabled(true)
    }

    private func startTap() {
        let switcher = switcher
        let tap = HotkeyTap { type, event in switcher.handle(type, event) }
        guard tap.start() else {
            statusLine.title = "Couldn't capture the keyboard"
            return
        }
        self.tap = tap
        statusLine.title = "Active"
        applyHotkeyMode()
    }

    private func applyHotkeyMode() {
        // Until permission is granted there is no tap, so leave the system ⌘Tab alone.
        guard tap != nil else { return }
        SystemSwitcher.setEnabled(!Preferences.replacesSystemSwitcher)
    }

    // MARK: - Menu

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Ventanas")

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permissions = NSMenuItem(title: "Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func openAccessibility() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }

    /// If we get killed with SIGTERM/SIGINT, give the native ⌘Tab back before exiting.
    private func restoreSystemSwitcherOnSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                SystemSwitcher.setEnabled(true)
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
