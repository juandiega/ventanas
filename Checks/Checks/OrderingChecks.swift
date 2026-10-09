import CoreGraphics
import VentanasCore

func orderingChecks() {
    typealias Entry = WindowOrdering.Entry<String>

    func win(_ id: CGWindowID, _ layer: Int = 0) -> WindowOrdering.OnScreenWindow { .init(id: id, layer: layer) }
    func visible(_ name: String, _ id: CGWindowID) -> Entry { Entry(item: name, windowID: id) }
    /// Minimized, from a hidden app, or with an unreadable ID: not listed by CGWindowList.
    func hidden(_ name: String, id: CGWindowID? = 900, appRank: Int = 0, index: Int = 0) -> Entry {
        Entry(item: name, windowID: id, appRank: appRank, indexInApp: index)
    }
    func windowless(_ name: String, appRank: Int = 0) -> Entry {
        Entry(item: name, windowID: nil, appRank: appRank, hasWindow: false)
    }
    func order(_ entries: [Entry], _ onScreen: [WindowOrdering.OnScreenWindow], focused: CGWindowID? = nil) -> [String] {
        WindowOrdering.order(entries, onScreen: onScreen, focused: focused)
    }

    // MARK: visible windows
    // Real bug: a floating window (Picture-in-Picture, layer 3) is always listed first by CGWindowList
    // and was counted as "the current window", so the first Tab went back to the current window.
    let pip = order(
        [visible("acrobat", 300), visible("pip", 100), visible("iterm", 200)],
        [win(100, 3), win(200), win(300)], focused: 200)
    check("the current window goes first", pip.first == "iterm", "\(pip)")
    check("the first Tab reaches the next window, not the current one", pip.count > 1 && pip[1] == "acrobat", "\(pip)")
    check("the floating window goes after the normal ones", pip.last == "pip", "\(pip)")

    check("without floating windows the z-order is kept, however the input comes",
          order([visible("c", 3), visible("a", 1), visible("b", 2)], [win(1), win(2), win(3)], focused: 1) == ["a", "b", "c"])

    check("the focused window goes first even if it is not on top of the z-order",
          order([visible("a", 1), visible("b", 2), visible("c", 3)], [win(1), win(2), win(3)], focused: 2) == ["b", "a", "c"])

    check("if the focused window is floating, it also goes first",
          order([visible("normal", 200), visible("pip", 100)], [win(100, 3), win(200)], focused: 100) == ["pip", "normal"])

    check("with no known focused window, floating ones go last",
          order([visible("pip", 100), visible("a", 200), visible("b", 300)], [win(100, 3), win(200), win(300)]) == ["a", "b", "pip"])

    // MARK: windows that are not on screen
    check("visible windows go before minimized ones even if the latter's app is more recent",
          order([hidden("minimized", appRank: 0), visible("visible", 200)], [win(200)], focused: 200) == ["visible", "minimized"])

    check("non-visible ones are ordered by app recency and then by position in the app",
          order([hidden("m1", appRank: 2), hidden("m2", appRank: 1, index: 1), hidden("m3", appRank: 1, index: 0)], [])
            == ["m3", "m2", "m1"])

    check("a window with an unreadable ID counts as non-visible",
          order([hidden("no-id", id: nil), visible("visible", 200)], [win(200)]) == ["visible", "no-id"])

    // MARK: apps without windows
    check("apps without windows go last, after the minimized ones",
          order([windowless("windowless"), hidden("minimized", appRank: 5), visible("visible", 200)], [win(200)], focused: 200)
            == ["visible", "minimized", "windowless"])

    check("apps without windows are ordered by recency",
          order([windowless("w1", appRank: 3), windowless("w2", appRank: 1)], []) == ["w2", "w1"])

    // MARK: edges
    check("no entries means no list", order([], [win(1)], focused: 1).isEmpty)

    check("ties keep the input order",
          order([hidden("x", appRank: 4), hidden("y", appRank: 4), hidden("z", appRank: 4)], []) == ["x", "y", "z"])
}
