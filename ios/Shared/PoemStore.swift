import Foundation

enum PoemStore {
    private static let cacheKey = "cachedPoemJSON"

    // MARK: - Public

    static func loadPagedPoem() -> PagedPoem {
        let poem = loadBundled()
        return PagedPoem(poem: poem, pages: PoemPaginator.paginate(text: poem.poem))
    }

    static func loadPagedPoemRemote() async -> PagedPoem {
        let poem = await remoteFirst()
        return PagedPoem(poem: poem, pages: PoemPaginator.paginate(text: poem.poem))
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
        guard
            let urlStr = Bundle.main.object(forInfoDictionaryKey: "PoemRemoteURL") as? String,
            let url = URL(string: urlStr)
        else { return nil }

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
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private static func loadCached() -> PoemData? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return decode(data)
    }
}
