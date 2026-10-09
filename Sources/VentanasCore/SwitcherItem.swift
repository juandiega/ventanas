/// What the switcher session needs to know about a row in order to act on it.
public protocol SwitcherItem: Searchable {
    /// Identifies the app the row belongs to (rows of the same app share it).
    var appID: Int { get }
    /// `false` for an app that has no windows.
    var hasWindow: Bool { get }
    /// `false` for an app that can't be quit (the Finder).
    var canQuit: Bool { get }
}
