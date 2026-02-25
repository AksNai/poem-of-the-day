import Foundation
import WidgetKit

enum PoemStore {
    private static let cacheKey = "cachedPoemJSON"
    static let remoteURL = "https://raw.githubusercontent.com/AksNai/poem-of-the-day/main/poem.json"

    /// App Group identifier shared between main app and widget extension.
    static let appGroupID = "group.com.aksha.poemoftheday"

    /// Shared UserDefaults accessible by both app and widget.
    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // MARK: - Public

    static func loadPagedPoem() -> PagedPoem {
        // Try cached (shared) first, fall back to bundled.
        let poem = loadCached() ?? loadBundled()
        return PagedPoem(poem: poem, pages: PoemPaginator.paginate(text: poem.poem))
    }

    static func loadPagedPoemRemote() async -> PagedPoem {
        let poem = await remoteFirst()
        return PagedPoem(poem: poem, pages: PoemPaginator.paginate(text: poem.poem))
    }

    /// Tell WidgetKit to refresh after new data is available.
    static func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Internal

    private static func remoteFirst() async -> PoemData {
        if let remote = await fetchRemote() {
            cache(remote)
            return remote
        }
        if let cached = loadCached() { return cached }
        return loadBundled()
    }

    private static func fetchRemote() async -> PoemData? {
        guard let url = URL(string: remoteURL) else { return nil }

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 15

        guard
            let (data, resp) = try? await URLSession.shared.data(for: req),
            let http = resp as? HTTPURLResponse,
            (200...299).contains(http.statusCode)
        else { return nil }

        return decode(data)
    }

    private static func loadBundled() -> PoemData {
        guard
            let url = Bundle.main.url(forResource: "poem", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let poem = decode(data)
        else { return .placeholder }
        return poem
    }

    private static func decode(_ data: Data) -> PoemData? {
        try? JSONDecoder().decode(PoemData.self, from: data)
    }

    private static func cache(_ poem: PoemData) {
        guard let data = try? JSONEncoder().encode(poem) else { return }
        sharedDefaults.set(data, forKey: cacheKey)
    }

    private static func loadCached() -> PoemData? {
        guard let data = sharedDefaults.data(forKey: cacheKey) else { return nil }
        return decode(data)
    }
}
