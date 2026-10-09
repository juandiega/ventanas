import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    private let picker = NSSegmentedControl()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let usage = NSTextField(wrappingLabelWithString: "")
    private let loginCheck = NSButton(checkboxWithTitle: "Open at login", target: nil, action: nil)

    func show() {
        if window == nil { window = makeWindow() }
        refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let heading = NSTextField(labelWithString: "Shortcut key")
        heading.font = .boldSystemFont(ofSize: 13)

        picker.segmentCount = TriggerModifier.allCases.count
        for (index, modifier) in TriggerModifier.allCases.enumerated() {
            picker.setLabel(modifier.title, forSegment: index)
        }
        picker.segmentStyle = .rounded
        picker.trackingMode = .selectOne
        picker.target = self
        picker.action = #selector(modifierChanged)

        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        usage.font = .systemFont(ofSize: 12)
        usage.textColor = .secondaryLabelColor

        loginCheck.target = self
        loginCheck.action = #selector(loginChanged)

        let stack = NSStackView(views: [heading, picker, hint, usage, loginCheck])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(18, after: usage)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: 420),
            hint.widthAnchor.constraint(equalToConstant: 372),
            usage.widthAnchor.constraint(equalToConstant: 372),
        ])

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ventanas Settings"
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func refresh() {
        let modifier = Preferences.modifier
        picker.selectedSegment = TriggerModifier.allCases.firstIndex(of: modifier) ?? 0
        let symbol = modifier.symbol
        hint.stringValue = modifier == .command
            ? "Replaces the system ⌘Tab while Ventanas is running."
            : "The system ⌘Tab keeps working; Ventanas uses \(symbol)Tab."
        usage.stringValue = "\(symbol)Tab: all windows  ·  \(symbol)`: windows of the current app\n"
            + "With the panel open, type to search."
        loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func modifierChanged() {
        Preferences.modifier = TriggerModifier.allCases[picker.selectedSegment]
        refresh()
    }

    @objc private func loginChanged() {
        do {
            if loginCheck.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }
}
