import Foundation

enum PoemPaginator {
    /// Split poem text into widget-sized pages using **visual-line estimation**.
    ///
    /// Long logical lines wrap in the widget, so we estimate how many visual
    /// lines each logical line occupies: `ceil(charCount / charsPerVisualLine)`.
    /// Pages are filled to a visual-line budget, preventing text cutoff.
    ///
    /// - `firstPageVisualLines`: budget for page 1 (title/author eat space).
    /// - `otherPageVisualLines`: budget for pages 2+.
    /// - `charsPerVisualLine`:   conservative estimate of characters per
    ///    rendered line (Georgia ~11.5pt in a medium widget ≈ 40).
    static func paginate(
        text: String,
        firstPageVisualLines: Int = 7,
        otherPageVisualLines: Int = 9,
        charsPerVisualLine: Int = 40
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
            let budget = pages.isEmpty ? firstPageVisualLines : otherPageVisualLines

            // Skip leading blank lines on pages 2+ (don't waste space)
            if !pages.isEmpty {
                while idx < allLines.count,
                      allLines[idx].trimmingCharacters(in: .whitespaces).isEmpty {
                    idx += 1
                }
            }
            guard idx < allLines.count else { break }

            var visualLinesUsed = 0
            var pageLines: [String] = []

            while idx < allLines.count {
                let line = allLines[idx]
                let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
                let cost = isBlank
                    ? 1
                    : max(1, Int(ceil(Double(line.count) / Double(charsPerVisualLine))))

                // If adding this line would exceed the budget and we already
                // have content, stop — the line goes on the next page.
                if visualLinesUsed + cost > budget && !pageLines.isEmpty {
                    break
                }

                pageLines.append(line)
                visualLinesUsed += cost
                idx += 1

                if visualLinesUsed >= budget { break }
            }

            // Trim trailing blank lines
            while let last = pageLines.last,
                  last.trimmingCharacters(in: .whitespaces).isEmpty {
                pageLines.removeLast()
            }

            let page = pageLines.joined(separator: "\n")
            if !page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(page)
            }
        }

        return pages.isEmpty ? [cleaned] : pages
    }
}
