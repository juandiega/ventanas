import AppKit
import VentanasCore

/// Modifier key held down to open the switcher.
enum TriggerModifier: String, CaseIterable, Identifiable {
    case command, option, control

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: "⌘ Command"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        }
    }

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        }
    }

    var core: Modifier {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        }
    }
}

extension Notification.Name {
    static let preferencesChanged = Notification.Name("VentanasPreferencesChanged")
}

enum Preferences {
    private static let modifierKey = "triggerModifier"

    static var modifier: TriggerModifier {
        get {
            UserDefaults.standard.string(forKey: modifierKey).flatMap(TriggerModifier.init) ?? .command
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modifierKey)
            NotificationCenter.default.post(name: .preferencesChanged, object: nil)
        }
    }

    /// The native ⌘Tab is only turned off when the chosen modifier is Command.
    static var replacesSystemSwitcher: Bool { modifier == .command }
}
