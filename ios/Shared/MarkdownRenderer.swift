import SwiftUI

/// Renders poem text that may contain Markdown formatting markers
/// (``*italic*``, ``_italic_``, ``**bold**``) into styled ``Text`` views.
///
/// Uses `.inlineOnlyPreservingWhitespace` so that leading spaces
/// (indentation) are kept and never misinterpreted as code blocks.
enum MarkdownRenderer {

    /// Convert a Markdown string into an `AttributedString` suitable
    /// for display in a SwiftUI `Text` view.
    static func attributedString(from markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let result = try? AttributedString(markdown: markdown, options: options) {
            return result
        }
        // Fallback: plain text (no Markdown interpretation)
        return AttributedString(markdown)
    }

    /// A convenience `Text` view that renders the given poem Markdown.
    @ViewBuilder
    static func text(from markdown: String) -> Text {
        Text(attributedString(from: markdown))
    }

    /// Render an epigraph (dedication) with italic styling.
    @ViewBuilder
    static func epigraphText(from epigraph: String) -> Text {
        Text(attributedString(from: "_\(epigraph)_"))
    }
}
