import AppKit
import ApplicationServices
import VentanasCore

/// A window (or an app without windows) that can be shown in the switcher.
struct WindowItem {
    let app: NSRunningApplication
    let element: AXUIElement?
    let windowID: CGWindowID
    let title: String
    let isMinimized: Bool

    var appName: String { app.localizedName ?? "?" }
    var displayTitle: String { title.isEmpty ? appName : title }

    var detail: String {
        var parts = [appName]
        if element == nil { parts.append("no windows") }
        if isMinimized { parts.append("minimized") }
        if app.isHidden { parts.append("hidden") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Private APIs (loaded at runtime; if one is missing, the public path is used)

private let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer?) -> T? {
    guard let pointer = dlsym(handle ?? rtldDefault, name) else { return nil }
    return unsafeBitCast(pointer, to: T.self)
}

private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
private typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
private typealias PostEventFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
private typealias SetHotKeyFn = @convention(c) (Int32, Bool) -> CGError

private let axGetWindow: GetWindowFn? = loadSymbol("_AXUIElementGetWindow", from: nil)
private let getProcessForPID: GetPSNFn? = loadSymbol("GetProcessForPID", from: nil)
private let slpsSetFrontProcess: SetFrontFn? = loadSymbol("_SLPSSetFrontProcessWithOptions", from: skyLight)
private let slpsPostEventRecordTo: PostEventFn? = loadSymbol("SLPSPostEventRecordTo", from: skyLight)
private let setSymbolicHotKey: SetHotKeyFn? = loadSymbol("CGSSetSymbolicHotKeyEnabled", from: skyLight)

/// Turns the native macOS ⌘Tab / ⌘` on or off.
enum SystemSwitcher {
    // IDs of the "symbolic hotkeys": 1 = ⌘Tab, 2 = ⌘⇧Tab, 6 = ⌘`
    private static let hotKeys: [Int32] = [1, 2, 6]

    static func setEnabled(_ enabled: Bool) {
        for id in hotKeys { _ = setSymbolicHotKey?(id, enabled) }
    }
}

/// Remembers the order in which apps were activated (most recent first).
@MainActor
final class AppRecency {
    static let shared = AppRecency()
    private var order: [pid_t] = []

    private init() {
        if let front = NSWorkspace.shared.frontmostApplication {
            order = [front.processIdentifier]
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { AppRecency.shared.touch(pid) }
        }
    }

    func touch(_ pid: pid_t) {
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
    }

    func rank(_ pid: pid_t) -> Int {
        order.firstIndex(of: pid) ?? order.count
    }
}

@MainActor
enum WindowManager {
    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// ID of the focused window of the frontmost app (the "current" window).
    private static func focusedWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.2)
        guard let window: AXUIElement = attribute(axApp, kAXFocusedWindowAttribute) else { return nil }
        var id: CGWindowID = 0
        return axGetWindow?(window, &id) == .success ? id : nil
    }

    /// Lists windows ordered by recent use. With `pid`, only that app's windows.
    static func listWindows(onlyApp pid: pid_t? = nil) -> [WindowItem] {
        // On-screen windows, front to back; the final order is decided by `WindowOrdering`.
        let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let onScreen = visible.compactMap { info -> WindowOrdering.OnScreenWindow? in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return .init(id: id, layer: info[kCGWindowLayer as String] as? Int ?? 0)
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var entries: [WindowOrdering.Entry<WindowItem>] = []

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            if let pid, app.processIdentifier != pid { continue }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.2)
            let windows: [AXUIElement] = attribute(axApp, kAXWindowsAttribute) ?? []
            let appRank = AppRecency.shared.rank(app.processIdentifier)
            var found = false

            for (localIndex, window) in windows.enumerated() {
                let subrole: String? = attribute(window, kAXSubroleAttribute)
                guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }

                var windowID: CGWindowID = 0
                _ = axGetWindow?(window, &windowID)
                let item = WindowItem(
                    app: app,
                    element: window,
                    windowID: windowID,
                    title: attribute(window, kAXTitleAttribute) ?? "",
                    isMinimized: attribute(window, kAXMinimizedAttribute) ?? false
                )
                entries.append(.init(
                    item: item, windowID: windowID == 0 ? nil : windowID, appRank: appRank, indexInApp: localIndex))
                found = true
            }

            if !found && pid == nil {
                let item = WindowItem(app: app, element: nil, windowID: 0, title: "", isMinimized: false)
                entries.append(.init(item: item, appRank: appRank, hasWindow: false))
            }
        }

        return WindowOrdering.order(entries, onScreen: onScreen, focused: focusedWindowID())
    }

    /// Closes the window by pressing its close button. Does nothing if the window has none.
    static func closeWindow(_ item: WindowItem) {
        guard let window = item.element,
              let button: AXUIElement = attribute(window, kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    /// Asks the app to quit, the same as ⌘Q: it can still ask to save changes.
    static func quit(_ item: WindowItem) {
        item.app.terminate()
    }

    /// Brings the window to the front (un-minimizing it or unhiding the app if needed).
    static func focus(_ item: WindowItem) {
        if item.app.isHidden { item.app.unhide() }

        guard let window = item.element else {
            item.app.activate()
            return
        }
        if item.isMinimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        var psn = ProcessSerialNumber()
        if let getProcessForPID, let slpsSetFrontProcess,
           getProcessForPID(item.app.processIdentifier, &psn) == noErr {
            // 0x200 = kCPSUserGenerated: activates the app with that specific window in front.
            _ = slpsSetFrontProcess(&psn, item.windowID, 0x200)
            makeKeyWindow(&psn, windowID: item.windowID)
        } else {
            item.app.activate()
        }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

/// Sends the app the two events that make that window the "key window", so the keyboard
/// (⌘W, ⌘Q…) reaches it instead of staying with the previous app.
private func makeKeyWindow(_ psn: inout ProcessSerialNumber, windowID: CGWindowID) {
    guard let post = slpsPostEventRecordTo, windowID != 0 else { return }
    var bytes = [UInt8](repeating: 0, count: 0xF8)
    bytes[0x04] = 0xF8
    bytes[0x3A] = 0x10
    var id = windowID
    memcpy(&bytes[0x3C], &id, MemoryLayout<CGWindowID>.size)
    memset(&bytes[0x20], 0xFF, 0x10)
    for marker: UInt8 in [0x01, 0x02] {
        bytes[0x08] = marker
        _ = post(&psn, &bytes)
    }
}

extension WindowItem: SwitcherItem {
    var searchName: String { appName }
    var searchTitle: String { title }
    var appID: Int { Int(app.processIdentifier) }
    var hasWindow: Bool { element != nil }
    /// The Finder can't be quit.
    var canQuit: Bool { app.bundleIdentifier != "com.apple.finder" }
}
