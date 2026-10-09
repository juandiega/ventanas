import CoreGraphics

public enum WindowOrdering {
    /// A visible window as listed by CGWindowList (front to back).
    public struct OnScreenWindow {
        public let id: CGWindowID
        public let layer: Int

        public init(id: CGWindowID, layer: Int) {
            self.id = id
            self.layer = layer
        }
    }

    /// Position of each visible window in the switcher list (0 = the current one).
    ///
    /// CGWindowList sorts by level before recency, so floating windows (Picture-in-Picture,
    /// panels) always come first without being the ones you use. They go after the normal ones,
    /// and the window that is really focused always goes first.
    private static func rank(onScreen: [OnScreenWindow], focused: CGWindowID?) -> [CGWindowID: Int] {
        var ordered = onScreen.filter { $0.layer == 0 } + onScreen.filter { $0.layer != 0 }
        if let focused, let index = ordered.firstIndex(where: { $0.id == focused }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        var ranks: [CGWindowID: Int] = [:]
        for (index, window) in ordered.enumerated() { ranks[window.id] = index }
        return ranks
    }

    /// A window (or an app without windows) that may appear in the switcher, with the data needed to
    /// order it. The adapter reads them from macOS; this module doesn't know where they come from.
    public struct Entry<Item> {
        public var item: Item
        /// `nil` if the ID couldn't be read or the app has no windows.
        public var windowID: CGWindowID?
        /// 0 = the most recently activated app.
        public var appRank: Int
        /// Position of the window within its app's list.
        public var indexInApp: Int
        /// `false` for an app without windows.
        public var hasWindow: Bool

        public init(item: Item, windowID: CGWindowID? = nil, appRank: Int = 0, indexInApp: Int = 0, hasWindow: Bool = true) {
            self.item = item
            self.windowID = windowID
            self.appRank = appRank
            self.indexInApp = indexInApp
            self.hasWindow = hasWindow
        }
    }

    /// The switcher list, from the current window backwards.
    ///
    /// Three groups, in this order:
    /// 1. Visible windows, by position (the focused one first, floating ones after the normal ones).
    /// 2. Windows that aren't on screen (minimized, from hidden apps, with an unreadable ID), by
    ///    their app's recency and then by their position within it.
    /// 3. Apps without windows, by recency.
    ///
    /// Ties keep the input order.
    public static func order<Item>(_ entries: [Entry<Item>], onScreen: [OnScreenWindow], focused: CGWindowID?) -> [Item] {
        let ranks = rank(onScreen: onScreen, focused: focused)

        func key(_ entry: Entry<Item>, _ inputIndex: Int) -> (Int, Int, Int, Int) {
            if !entry.hasWindow { return (2, entry.appRank, 0, inputIndex) }
            if let id = entry.windowID, let visibleRank = ranks[id] { return (0, visibleRank, 0, inputIndex) }
            return (1, entry.appRank, entry.indexInApp, inputIndex)
        }

        return entries.enumerated()
            .map { (key: key($1, $0), item: $1.item) }
            .sorted { $0.key < $1.key }
            .map(\.item)
    }
}
