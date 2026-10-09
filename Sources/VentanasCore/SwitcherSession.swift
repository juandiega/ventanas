/// Modifier held down to open the switcher.
public enum Modifier: Sendable {
    case command, option, control

    public var flag: Modifiers {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        }
    }
}

public struct Modifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
}

/// Which windows a session walks through.
public enum Scope: Equatable, Sendable {
    case allWindows
    case currentApp
}

public enum Key: Equatable, Sendable {
    case tab
    /// The ` key (ANSI) or º (ISO): walks only the current app's windows.
    case sameAppKey
    case escape, confirm, delete
    case left, right, up, down
    /// Raw text; the session decides whether it counts as search input.
    case character(String)
}

public enum Input: Sendable {
    case key(Key, Modifiers)
    case modifiersChanged(Modifiers)
    /// Click on a row of the panel (index into the list being shown).
    case pick(Int)
    /// Click outside the panel.
    case dismiss
    /// Click on a row's close button (index into the list being shown).
    case closeWindow(Int)
    /// Click on a row's quit button (index into the list being shown).
    case quitApp(Int)
}

public enum Effect<Item> {
    case show(items: [Item], query: String, selection: Int)
    case select(Int)
    case focus(Item)
    /// Close this window. Fire and forget: the row is already gone from the list.
    case closeWindow(Item)
    /// Quit this window's app. Fire and forget: its rows are already gone from the list.
    case quitApp(Item)
    case hide
}

extension Effect: Equatable where Item: Equatable {}

public struct Outcome<Item> {
    /// `true` if the key must not reach the app.
    public var swallow: Bool
    public var effects: [Effect<Item>]

    public init(swallow: Bool, effects: [Effect<Item>]) {
        self.swallow = swallow
        self.effects = effects
    }
}

extension Outcome: Equatable where Item: Equatable {}

/// A switcher session: from pressing the shortcut until it is released or cancelled.
/// It never touches the world: it takes inputs and returns effects for an adapter to run.
public final class SwitcherSession<Item: SwitcherItem> {
    private let trigger: () -> Modifier
    private let listWindows: (Scope) -> [Item]

    private var active = false
    /// After typing, releasing the modifier no longer closes: it waits for Return or Esc.
    private var sticky = false
    private var items: [Item] = []
    /// Indices into `items` of the rows being shown (all of them, or the ones the search kept).
    private var shown: [Int] = []
    private var selection = 0
    private var query = ""

    public init(trigger: @escaping () -> Modifier, listWindows: @escaping (Scope) -> [Item]) {
        self.trigger = trigger
        self.listWindows = listWindows
    }

    /// `true` while a session is open. The adapter uses it to avoid reading the text of keys that
    /// will do nothing.
    public var isActive: Bool { active }

    public func handle(_ input: Input) -> Outcome<Item> {
        switch input {
        case .modifiersChanged(let modifiers):
            if active && !sticky && !modifiers.contains(trigger().flag) { return commit(swallow: false) }
            return passThrough
        case .key(let key, let modifiers):
            return active ? handleActive(key, modifiers) : handleInactive(key, modifiers)
        case .pick(let index):
            guard active else { return passThrough }
            selection = index
            return commit(swallow: false)
        case .dismiss:
            return active ? close(swallow: false) : passThrough
        case .closeWindow(let position):
            return perform(.closeWindow, at: position, swallow: false)
        case .quitApp(let position):
            return perform(.quitApp, at: position, swallow: false)
        }
    }

    // MARK: - No session

    private func handleInactive(_ key: Key, _ modifiers: Modifiers) -> Outcome<Item> {
        // Only opens with the trigger modifier; any other modifier cancels it.
        let all: Modifiers = [.command, .option, .control]
        let others = all.subtracting(trigger().flag)
        guard modifiers.contains(trigger().flag), modifiers.isDisjoint(with: others) else { return passThrough }
        switch key {
        case .tab: return begin(.allWindows, reverse: modifiers.contains(.shift))
        case .sameAppKey: return begin(.currentApp, reverse: modifiers.contains(.shift))
        default: return passThrough
        }
    }

    private func begin(_ scope: Scope, reverse: Bool) -> Outcome<Item> {
        items = listWindows(scope)
        // With no windows there is nothing to show, but the shortcut is still swallowed.
        guard !items.isEmpty else { return Outcome(swallow: true, effects: []) }

        active = true
        sticky = false
        query = ""
        shown = Array(items.indices)
        selection = items.count > 1 ? (reverse ? items.count - 1 : 1) : 0
        return swallowed(show())
    }

    // MARK: - With a session: the session takes every key

    private func handleActive(_ key: Key, _ modifiers: Modifiers) -> Outcome<Item> {
        switch key {
        case .tab, .sameAppKey: return swallowed(move(modifiers.contains(.shift) ? -1 : 1))
        case .down, .right: return swallowed(move(1))
        case .up, .left: return swallowed(move(-1))
        case .escape: return close(swallow: true)
        case .confirm: return commit(swallow: true)
        case .delete:
            guard !query.isEmpty else { return swallowed([]) }
            query.removeLast()
            return swallowed(applyFilter())
        case .character(let text):
            // Trigger modifier + ⇧ + W / Q close the selected window / quit its app. Without the
            // trigger modifier (while searching) they are plain text.
            if modifiers.contains(trigger().flag), modifiers.contains(.shift) {
                switch text.lowercased() {
                case "w": return perform(.closeWindow, at: selection, swallow: true)
                case "q": return perform(.quitApp, at: selection, swallow: true)
                default: break
                }
            }
            // Anything typeable as text counts as search input; the rest is ignored.
            guard let first = text.first, first.isLetter || first.isNumber || first.isPunctuation || first == " "
            else { return swallowed([]) }
            query += text
            sticky = true
            return swallowed(applyFilter())
        }
    }

    private func move(_ delta: Int) -> [Effect<Item>] {
        guard !shown.isEmpty else { return [] }
        selection = (selection + delta + shown.count) % shown.count
        return [.select(selection)]
    }

    private func applyFilter() -> [Effect<Item>] {
        shown = Fuzzy.matches(items, query: query)
        selection = 0
        return show()
    }

    private func show() -> [Effect<Item>] {
        [.show(items: shown.map { items[$0] }, query: query, selection: selection)]
    }

    private func commit(swallow: Bool) -> Outcome<Item> {
        let chosen = shown.indices.contains(selection) ? items[shown[selection]] : nil
        var outcome = close(swallow: swallow)
        if let chosen { outcome.effects.append(.focus(chosen)) }
        return outcome
    }

    private func close(swallow: Bool) -> Outcome<Item> {
        active = false
        sticky = false
        return Outcome(swallow: swallow, effects: [.hide])
    }

    // MARK: - Closing windows and quitting apps

    private enum RowAction { case closeWindow, quitApp }

    /// Runs `action` on the row at `position` of the list being shown, and drops the rows that go away.
    private func perform(_ action: RowAction, at position: Int, swallow: Bool) -> Outcome<Item> {
        let nothing = Outcome<Item>(swallow: swallow, effects: [])
        guard active, shown.indices.contains(position) else { return nothing }
        let target = items[shown[position]]

        let effect: Effect<Item>
        let removed: Set<Int>
        switch action {
        case .closeWindow:
            guard target.hasWindow else { return nothing }
            effect = .closeWindow(target)
            removed = [shown[position]]
        case .quitApp:
            guard target.canQuit else { return nothing }
            effect = .quitApp(target)
            removed = Set(items.indices.filter { items[$0].appID == target.appID })
        }
        return Outcome(swallow: swallow, effects: [effect] + remove(removed))
    }

    /// Drops rows from the session. The selection goes to the first surviving row at or after where
    /// it was (or the last one, if there are none after it). With nothing left, the session ends.
    private func remove(_ removed: Set<Int>) -> [Effect<Item>] {
        let survivorsBeforeSelection = shown.prefix(selection).filter { !removed.contains($0) }.count

        var newIndex: [Int: Int] = [:]
        for index in items.indices where !removed.contains(index) { newIndex[index] = newIndex.count }
        items = items.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        shown = shown.compactMap { newIndex[$0] }

        guard !items.isEmpty else { return close(swallow: false).effects }
        selection = shown.isEmpty ? 0 : min(survivorsBeforeSelection, shown.count - 1)
        return show()
    }

    // MARK: - Outcomes

    private var passThrough: Outcome<Item> { Outcome(swallow: false, effects: []) }

    private func swallowed(_ effects: [Effect<Item>]) -> Outcome<Item> {
        Outcome(swallow: true, effects: effects)
    }
}
