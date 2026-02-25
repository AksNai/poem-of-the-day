import Foundation

struct PoemData: Codable {
    let title: String
    let author: String
    let poem: String
    let epigraph: String?
    let epigraphStyle: String?   // "dedication" or "quote"

    /// True when the epigraph is a substantive quote (body-sized).
    var isQuoteEpigraph: Bool { epigraphStyle == "quote" }

    static let placeholder = PoemData(
        title: "Poem of the Day",
        author: "Unknown",
        poem: "No poem available yet.\nCheck back soon.",
        epigraph: nil,
        epigraphStyle: nil
    )
}

struct PagedPoem {
    let poem: PoemData
    let pages: [String]
}
