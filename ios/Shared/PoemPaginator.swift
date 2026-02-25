import Foundation

enum PoemPaginator {
    /// Split poem text into widget-sized pages by **line count**.
    ///
    /// - First page: `firstPageLines` lines (default 7) — title/author take space.
    /// - Subsequent pages: `otherPageLines` lines (default 10).
    ///
    /// Blank lines between stanzas count as lines.
    static func paginate(
        text: String,
        firstPageLines: Int = 6,
        otherPageLines: Int = 10
    ) -> [String] {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return ["No poem content."] }

        let allLines = cleaned.components(separatedBy: "\n")
        var pages: [String] = []
        var idx = 0

        while idx < allLines.count {
            let limit = pages.isEmpty ? firstPageLines : otherPageLines
            let end = min(idx + limit, allLines.count)
            let slice = Array(allLines[idx..<end])

            // Trim trailing blank lines from this page
            var trimmed = slice
            while let last = trimmed.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                trimmed.removeLast()
            }

            let page = trimmed.joined(separator: "\n")
            if !page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(page)
            }
            idx = end
        }

        return pages.isEmpty ? [cleaned] : pages
    }
}
