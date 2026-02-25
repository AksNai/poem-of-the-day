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
            // Only show epigraph on the first page
            epigraph: clamped == 1 ? paged.poem.epigraph : nil,
            epigraphStyle: clamped == 1 ? paged.poem.epigraphStyle : nil,
            pageIndex: clamped,
            totalPages: total
        )
    }
}

// MARK: - Widget Views

struct PoemWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: PoemEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    // ── Small ──────────────────────────────────────────────
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.caption.bold())
                .lineLimit(1)
            Text(entry.author)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let epi = entry.epigraph, !epi.isEmpty {
                MarkdownRenderer.epigraphText(from: epi)
                    .font(entry.isQuoteEpigraph ? .caption2 : .caption)
                    .foregroundStyle(entry.isQuoteEpigraph ? .secondary : .primary)
                    .padding(.leading, entry.isQuoteEpigraph ? 10 : 4)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            MarkdownRenderer.text(from: entry.excerpt)
                .font(.caption2)
                .lineLimit(6)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    // ── Medium ─────────────────────────────────────────────
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text("by \(entry.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let epi = entry.epigraph, !epi.isEmpty {
                MarkdownRenderer.epigraphText(from: epi)
                    .font(entry.isQuoteEpigraph ? .caption : .footnote)
                    .foregroundStyle(entry.isQuoteEpigraph ? .secondary : .primary)
                    .padding(.leading, entry.isQuoteEpigraph ? 16 : 6)
                    .lineLimit(1)
            }
            Divider()
            MarkdownRenderer.text(from: entry.excerpt)
                .font(.caption)
                .lineLimit(6)
                .minimumScaleFactor(0.85)
        }
        .padding(14)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    // ── Large ──────────────────────────────────────────────
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("by \(entry.author)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let epi = entry.epigraph, !epi.isEmpty {
                MarkdownRenderer.epigraphText(from: epi)
                    .font(entry.isQuoteEpigraph ? .footnote : .body)
                    .foregroundStyle(entry.isQuoteEpigraph ? .secondary : .primary)
                    .padding(.leading, entry.isQuoteEpigraph ? 20 : 8)
                    .lineLimit(2)
            }
            Divider()
            MarkdownRenderer.text(from: entry.excerpt)
                .font(.body)
                .lineLimit(nil)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(16)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Small", as: .systemSmall) {
    PoemOfTheDayWidget()
} timeline: {
    PoemEntry(date: .now, title: "The Road Not Taken", author: "Robert Frost",
              excerpt: "Two roads diverged in a yellow wood,\nAnd sorry I could not travel both…",
              epigraph: nil, epigraphStyle: nil,
              pageIndex: 1, totalPages: 2)
}

#Preview("Medium", as: .systemMedium) {
    PoemOfTheDayWidget()
} timeline: {
    PoemEntry(date: .now, title: "The Road Not Taken", author: "Robert Frost",
              excerpt: "Two roads diverged in a yellow wood,\nAnd sorry I could not travel both\nAnd be one traveler, long I stood\nAnd looked down one as far as I could\nTo where it bent in the undergrowth;",
              epigraph: nil, epigraphStyle: nil,
              pageIndex: 1, totalPages: 2)
}

#Preview("Large", as: .systemLarge) {
    PoemOfTheDayWidget()
} timeline: {
    PoemEntry(date: .now, title: "The Road Not Taken", author: "Robert Frost",
              excerpt: "Two roads diverged in a yellow wood,\nAnd sorry I could not travel both\nAnd be one traveler, long I stood\nAnd looked down one as far as I could\nTo where it bent in the undergrowth;\n\nThen took the other, as just as fair,\nAnd having perhaps the better claim,\nBecause it was grassy and wanted wear;\nThough as for that the passing there\nHad worn them really about the same,",
              epigraph: nil, epigraphStyle: nil,
              pageIndex: 1, totalPages: 2)
}
#endif
