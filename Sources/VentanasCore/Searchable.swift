/// The least the switcher needs to know about a window in order to search for it.
public protocol Searchable {
    /// App name.
    var searchName: String { get }
    /// Window title (may be empty).
    var searchTitle: String { get }
}
