import Foundation

struct PoemData: Codable {
    let title: String
    let author: String
    let poem: String
    let epigraph: String?

    static let placeholder = PoemData(
        title: "Poem of the Day",
        author: "Unknown",
        poem: "No poem available yet.\nCheck back soon.",
        epigraph: nil
    )
}

struct PagedPoem {
    let poem: PoemData
    let pages: [String]
}
