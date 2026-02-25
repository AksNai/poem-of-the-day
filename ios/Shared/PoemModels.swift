import Foundation

struct PoemData: Codable {
    let title: String
    let author: String
    let poem: String

    static let placeholder = PoemData(
        title: "Poem of the Day",
        author: "Unknown",
        poem: "No poem available yet.\nCheck back soon."
    )
}

struct PagedPoem {
    let poem: PoemData
    let pages: [String]
}
