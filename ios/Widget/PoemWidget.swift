import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Configuration Intent

/// Users long-press → Edit Widget → pick the page number for this instance.
struct PoemPageIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Poem Page"
    static var description = IntentDescription("Choose which page of today's poem to display.")

    @Parameter(title: "Page", default: 1)
    var page: Int
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
        makeEntry(from: PoemStore.loadPagedPoem(), requestedPage: configuration.page)
    }

    func timeline(for configuration: PoemPageIntent, in context: Context) async -> Timeline<PoemEntry> {
        let paged = await PoemStore.loadPagedPoemRemote()
        let entry = makeEntry(from: paged, requestedPage: configuration.page)
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
        .padding(.vertical, 14)
        .containerBackground(for: .widget) {
            Color.black.opacity(0.6)
        }
    }

    // Serif font helpers — "Georgia" is a built-in iOS font
    private static let titleFont = Font.custom("Georgia", fixedSize: 14).bold()
    private static let authorFont = Font.custom("Georgia", fixedSize: 11).italic()
    private static let poemFont  = Font.custom("Georgia", fixedSize: 11)

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
                        .font(Font.custom("Georgia", fixedSize: 10).italic())
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                } else {
                    Text(epigraph)
                        .font(Font.custom("Georgia", fixedSize: 11).italic())
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer().frame(height: 5)

            MarkdownRenderer.text(from: entry.excerpt)
                .font(Self.poemFont)
                .foregroundStyle(.white)
                .lineLimit(nil)

            Spacer(minLength: 0)
        }
    }

    // ── Subsequent pages: poem only ────────────────────────
    private var subsequentPageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarkdownRenderer.text(from: entry.excerpt)
                .font(Self.poemFont)
                .foregroundStyle(.white)
                .lineLimit(nil)

            Spacer(minLength: 0)
        }
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
