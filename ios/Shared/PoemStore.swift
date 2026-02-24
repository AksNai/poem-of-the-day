import Foundation

enum PoemStore {
    private static let cachedPoemKey = "cachedPoemJSON"

    static func loadPoemRemoteFirst() async -> PoemData {
        if let remote = await fetchRemotePoem() {
            saveCachedPoem(remote)
            return remote
        }

        if let cached = loadCachedPoem() {
            return cached
        }

        return loadPoem()
    }

    static func loadPagedPoemRemoteFirst() async -> PagedPoem {
        let poem = await loadPoemRemoteFirst()
        let pages = PoemPaginator.paginate(poem: poem.poem)
        return PagedPoem(poem: poem, pages: pages)
    }

    static func loadPoem() -> PoemData {
        guard let url = Bundle.main.url(forResource: "poem", withExtension: "json") else {
            return .placeholder
        }

        do {
            let data = try Data(contentsOf: url)
            if let decoded = decodePoemData(data) {
                return decoded
            }
            return .placeholder
        } catch {
            return .placeholder
        }
    }

    static func loadPagedPoem() -> PagedPoem {
        let poem = loadPoem()
        let pages = PoemPaginator.paginate(poem: poem.poem)
        return PagedPoem(poem: poem, pages: pages)
    }

    private static func fetchRemotePoem() async -> PoemData? {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "PoemRemoteURL") as? String,
            let remoteURL = URL(string: urlString),
            !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            return decodePoemData(data)
        } catch {
            return nil
        }
    }

    private static func decodePoemData(_ data: Data) -> PoemData? {
        do {
            let decoded = try JSONDecoder().decode(PoemData.self, from: data)
            return sanitize(decoded)
        } catch {
            return nil
        }
    }

    private static func sanitize(_ poem: PoemData) -> PoemData {
        let cleaned = PoemData(
            title: poem.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Poem of the Day" : poem.title,
            author: poem.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : poem.author,
            poem: poem.poem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? PoemData.placeholder.poem : poem.poem
        )
        return cleaned
    }

    private static func saveCachedPoem(_ poem: PoemData) {
        guard let encoded = try? JSONEncoder().encode(poem) else {
            return
        }
        UserDefaults.standard.set(encoded, forKey: cachedPoemKey)
    }

    private static func loadCachedPoem() -> PoemData? {
        guard let data = UserDefaults.standard.data(forKey: cachedPoemKey) else {
            return nil
        }
        return decodePoemData(data)
    }
}
