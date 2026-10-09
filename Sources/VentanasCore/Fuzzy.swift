import Foundation

public enum Fuzzy {
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// 0 = prefijo, 1 = contiene, 2 = subsecuencia, nil = no coincide.
    static func score(_ query: String, _ text: String) -> Int? {
        let text = normalize(text)
        if text.hasPrefix(query) { return 0 }
        if text.contains(query) { return 1 }
        var remaining = text[...]
        for char in query {
            guard let index = remaining.firstIndex(of: char) else { return nil }
            remaining = remaining[remaining.index(after: index)...]
        }
        return 2
    }

    /// Indices into `items` of the ones that match, best match first (ties keep the input order).
    public static func matches<Item: Searchable>(_ items: [Item], query: String) -> [Int] {
        let query = normalize(query)
        guard !query.isEmpty else { return Array(items.indices) }
        return items.enumerated()
            .compactMap { index, item -> (Int, Int)? in
                let best = [score(query, item.searchName), score(query, item.searchTitle)].compactMap { $0 }.min()
                return best.map { ($0, index) }
            }
            .sorted { $0 < $1 }
            .map(\.1)
    }

    public static func filter<Item: Searchable>(_ items: [Item], query: String) -> [Item] {
        matches(items, query: query).map { items[$0] }
    }
}
