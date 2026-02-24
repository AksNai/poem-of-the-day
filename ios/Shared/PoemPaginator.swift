import Foundation

enum PoemPaginator {
    static func paginate(poem: String, maxCharacters: Int = 420, maxLines: Int = 16) -> [String] {
        let normalized = poem
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return ["No poem content available."]
        }

        let stanzas = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var pages: [String] = []
        var currentStanzas: [String] = []
        var currentLines = 0
        var currentChars = 0

        func flushPage() {
            let joined = currentStanzas.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                pages.append(joined)
            }
            currentStanzas.removeAll(keepingCapacity: true)
            currentLines = 0
            currentChars = 0
        }

        for stanza in stanzas {
            let stanzaLines = stanza.components(separatedBy: "\n").count
            let stanzaChars = stanza.count
            let separatorChars = currentStanzas.isEmpty ? 0 : 2

            let wouldExceedLines = currentLines + stanzaLines > maxLines
            let wouldExceedChars = currentChars + stanzaChars + separatorChars > maxCharacters

            if (!currentStanzas.isEmpty && (wouldExceedLines || wouldExceedChars)) {
                flushPage()
            }

            if stanzaLines > maxLines || stanzaChars > maxCharacters {
                let chunks = chunk(stanza: stanza, maxCharacters: maxCharacters, maxLines: maxLines)
                if !currentStanzas.isEmpty {
                    flushPage()
                }
                pages.append(contentsOf: chunks)
                continue
            }

            currentStanzas.append(stanza)
            currentLines += stanzaLines
            currentChars += stanzaChars + (currentStanzas.count == 1 ? 0 : 2)
        }

        if !currentStanzas.isEmpty {
            flushPage()
        }

        return pages.isEmpty ? [normalized] : pages
    }

    private static func chunk(stanza: String, maxCharacters: Int, maxLines: Int) -> [String] {
        let lines = stanza.components(separatedBy: "\n")
        var chunks: [String] = []
        var current: [String] = []
        var currentChars = 0

        for line in lines {
            let lineChars = line.count + (current.isEmpty ? 0 : 1)
            let exceedsChars = currentChars + lineChars > maxCharacters
            let exceedsLines = current.count + 1 > maxLines

            if !current.isEmpty && (exceedsChars || exceedsLines) {
                chunks.append(current.joined(separator: "\n"))
                current.removeAll(keepingCapacity: true)
                currentChars = 0
            }

            if line.count > maxCharacters {
                if !current.isEmpty {
                    chunks.append(current.joined(separator: "\n"))
                    current.removeAll(keepingCapacity: true)
                    currentChars = 0
                }

                var start = line.startIndex
                while start < line.endIndex {
                    let end = line.index(start, offsetBy: maxCharacters, limitedBy: line.endIndex) ?? line.endIndex
                    chunks.append(String(line[start..<end]))
                    start = end
                }
                continue
            }

            current.append(line)
            currentChars += lineChars
        }

        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }

        return chunks
    }
}
