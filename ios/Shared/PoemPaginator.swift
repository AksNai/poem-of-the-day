import Foundation

enum PoemPaginator {
    /// Split poem text into widget-sized pages by stanza boundaries.
    static func paginate(text: String, maxChars: Int = 400, maxLines: Int = 14) -> [String] {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return ["No poem content."] }

        let stanzas = cleaned
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var pages: [String] = []
        var buf: [String] = []
        var lines = 0
        var chars = 0

        func flush() {
            let page = buf.joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !page.isEmpty { pages.append(page) }
            buf.removeAll()
            lines = 0
            chars = 0
        }

        for stanza in stanzas {
            let sLines = stanza.components(separatedBy: "\n").count
            let sChars = stanza.count
            let sep = buf.isEmpty ? 0 : 2

            if !buf.isEmpty && (lines + sLines > maxLines || chars + sChars + sep > maxChars) {
                flush()
            }
            buf.append(stanza)
            lines += sLines
            chars += sChars + sep
        }
        flush()

        return pages.isEmpty ? [cleaned] : pages
    }
}
