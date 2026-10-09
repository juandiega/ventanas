import AppKit
import VentanasCore

/// Adapter between the macOS keyboard/mouse and `SwitcherSession`: translates events to `Input` and
/// runs the effects (panel, window switch). The switcher's rules live in the session.
@MainActor
final class SwitcherController {
    private let panel = SwitcherPanel()
    private let session: SwitcherSession<WindowItem>
    private var clickMonitor: Any?

    init() {
        session = SwitcherSession(
            trigger: { Preferences.modifier.core },
            listWindows: { scope in
                let pid = scope == .currentApp ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
                return WindowManager.listWindows(onlyApp: pid)
            }
        )
        panel.onPick = { [weak self] index in self?.run(.pick(index)) }
        panel.onClose = { [weak self] index in self?.run(.closeWindow(index)) }
        panel.onQuit = { [weak self] index in self?.run(.quitApp(index)) }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.run(.dismiss) }
        }
    }

    /// Returns `true` if the event must not reach the app.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .flagsChanged: run(.modifiersChanged(Modifiers(event.flags)))
        case .keyDown: run(.key(key(for: event), Modifiers(event.flags)))
        default: false
        }
    }

    @discardableResult
    private func run(_ input: Input) -> Bool {
        let outcome = session.handle(input)
        for effect in outcome.effects {
            switch effect {
            case .show(let items, let query, let selection):
                panel.hint = hint
                panel.show(items: items, query: query, selection: selection)
            case .select(let index): panel.select(index)
            case .focus(let item): WindowManager.focus(item)
            case .closeWindow(let item): WindowManager.closeWindow(item)
            case .quitApp(let item): WindowManager.quit(item)
            case .hide: panel.orderOut(nil)
            }
        }
        return outcome.swallow
    }

    /// The help line at the bottom of the panel, with the current trigger modifier.
    private var hint: String {
        let symbol = Preferences.modifier.symbol
        return "\(symbol)⇧W close window  ·  \(symbol)⇧Q quit app"
    }

    private func key(for event: CGEvent) -> Key {
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 48: .tab
        case 50, 10: .sameAppKey  // ` on ANSI; º ª on a Spanish keyboard (above Tab)
        case 53: .escape
        case 36, 76: .confirm
        case 51: .delete
        case 123: .left
        case 124: .right
        case 125: .down
        case 126: .up
        default:
            // Reading the text costs something and only matters while a session is open.
            .character(session.isActive ? NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? "" : "")
        }
    }
}

private extension Modifiers {
    init(_ flags: CGEventFlags) {
        var modifiers: Modifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        self = modifiers
    }
}
