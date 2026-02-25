import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Configuration Intent

/// AppEnum gives a native dropdown picker in the widget edit UI.
/// 15 pages is generous — most poems fit in 5–10 medium-widget pages.
enum PoemPage: String, AppEnum {
    case p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15

    /// The 1-based page number derived from the case name (e.g. p3 → 3).
    var pageNumber: Int {
        Int(String(rawValue.dropFirst())) ?? 1
    }

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Page")
    static var caseDisplayRepresentations: [PoemPage: DisplayRepresentation] = [
        .p1: "1", .p2: "2", .p3: "3", .p4: "4", .p5: "5",
        .p6: "6", .p7: "7", .p8: "8", .p9: "9", .p10: "10",
        .p11: "11", .p12: "12", .p13: "13", .p14: "14", .p15: "15"
    ]
}

/// Users long-press → Edit Widget → pick the page number from a dropdown.
struct PoemPageIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Poem Page"
    static var description = IntentDescription("Choose which page of today's poem to display.")

    @Parameter(title: "Page", default: .p1)
    var page: PoemPage
}

// MARK: - Timeline Entry

struct PoemEntry: TimelineEntry {
    let date: Date
    let title: String
    let author: String
    let excerpt: String          // the text for this page
    let epigraph: String?        // only present on page 1
    let epigraphStyle: String?   // "dedication" or "quote"
    let pageIndex: Int
    let totalPages: Int

    var isQuoteEpigraph: Bool { epigraphStyle == "quote" }
    var isFirstPage: Bool { pageIndex == 1 }
}

// MARK: - Timeline Provider (Intent-based)

struct PoemTimelineProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> PoemEntry {
        PoemEntry(
            date: .now,
            title: "Poem of the Day",
            author: "Loading…",
            excerpt: "A new poem every day\nright on your home screen.",
            epigraph: nil,
            epigraphStyle: nil,
            pageIndex: 1,
            totalPages: 1
        )
    }

    func snapshot(for configuration: PoemPageIntent, in context: Context) async -> PoemEntry {
        makeEntry(from: PoemStore.loadPagedPoem(), requestedPage: configuration.page.pageNumber)
    }

    func timeline(for configuration: PoemPageIntent, in context: Context) async -> Timeline<PoemEntry> {
        let paged = await PoemStore.loadPagedPoemRemote()
        let entry = makeEntry(from: paged, requestedPage: configuration.page.pageNumber)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    // MARK: Helpers

    private func makeEntry(from paged: PagedPoem, requestedPage: Int) -> PoemEntry {
        let total = paged.pages.count
        let clamped = max(1, min(requestedPage, total))
        let page = paged.pages[clamped - 1]

        return PoemEntry(
            date: .now,
            title: paged.poem.title,
            author: paged.poem.author,
            excerpt: page,
            epigraph: clamped == 1 ? paged.poem.epigraph : nil,
            epigraphStyle: clamped == 1 ? paged.poem.epigraphStyle : nil,
            pageIndex: clamped,
            totalPages: total
        )
    }
}

// MARK: - Widget View

struct PoemWidgetEntryView: View {
    var entry: PoemEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.isFirstPage {
                firstPageContent
            } else {
                subsequentPageContent
            }
        }
        .padding(.horizontal, 6)
        .containerBackground(for: .widget) {
            Color.black.opacity(0.6)
        }
    }

    // Serif font helpers — "Georgia" is a built-in iOS font
    private static let titleFont = Font.custom("Georgia", fixedSize: 15).bold()
    private static let authorFont = Font.custom("Georgia", fixedSize: 11.5).italic()
    private static let poemFont  = Font.custom("Georgia", fixedSize: 11.5)

    // ── First page: title, author, epigraph, poem ───────
    private var firstPageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.title)
                .font(Self.titleFont)
                .foregroundStyle(.white)
                .lineLimit(2)

            if !entry.author.isEmpty {
                Spacer().frame(height: 1)
                Text("by \(entry.author)")
                    .font(Self.authorFont)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if let epigraph = entry.epigraph, !epigraph.isEmpty {
                Spacer().frame(height: 3)
                if entry.isQuoteEpigraph {
                    MarkdownRenderer.epigraphText(from: epigraph)
                        .font(Font.custom("Georgia", fixedSize: 11.5).italic())
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                } else {
                    Text(epigraph)
                        .font(Font.custom("Georgia", fixedSize: 12).italic())
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer().frame(height: 5)

            poemLinesView

            Spacer(minLength: 0)
        }
    }

    // ── Subsequent pages: poem only ────────────────────────
    private var subsequentPageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            poemLinesView
    /// Renders each line of the excerpt in a VStack.
    /// Blank lines are replaced with a 5pt spacer for stanza breaks.
    private var poemLinesView: some View {
        let lines = entry.excerpt
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    Spacer().frame(height: 5)
                } else {
                    MarkdownRenderer.text(from: line)
                        .font(Self.poemFont)
                        .foregroundStyle(.white)
                        .lineLimit(nil)
                }
            }
        }
    }

            Spacer(minLength: 0)
        }
    }

    /// Splits the excerpt at blank lines and renders each stanza with
    /// 5pt gaps (matching the epigraph → body spacing).
    private var stanzaStack: some View {
        EmptyView()
    }
}

// MARK: - Widget Configuration

struct PoemOfTheDayWidget: Widget {
    let kind = "PoemOfTheDayWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PoemPageIntent.self, provider: PoemTimelineProvider()) { entry in
            PoemWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Poem of the Day")
        .description("Displays today's poem. Add multiple widgets and set each to a different page.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Page 1", as: .systemLarge) {
    PoemOfTheDayWidget()
} timeline: {
    PoemEntry(date: .now, title: "The Road Not Taken", author: "Robert Frost",
              excerpt: "Two roads diverged in a yellow wood,\nAnd sorry I could not travel both\nAnd be one traveler, long I stood\nAnd looked down one as far as I could\nTo where it bent in the undergrowth;\n\nThen took the other, as just as fair,",
              epigraph: nil, epigraphStyle: nil,
              pageIndex: 1, totalPages: 3)
}

#Preview("Page 2", as: .systemLarge) {
    PoemOfTheDayWidget()
} timeline: {
    PoemEntry(date: .now, title: "The Road Not Taken", author: "Robert Frost",
              excerpt: "And having perhaps the better claim,\nBecause it was grassy and wanted wear;\nThough as for that the passing there\nHad worn them really about the same,\n\nAnd both that morning equally lay\nIn leaves no step had trodden black.\nOh, I kept the first for another day!\nYet knowing how way leads on to way,\nI doubted if I should ever come back.",
              epigraph: nil, epigraphStyle: nil,
              pageIndex: 2, totalPages: 3)
}
#endif
