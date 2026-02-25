import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct PoemEntry: TimelineEntry {
    let date: Date
    let title: String
    let author: String
    let excerpt: String          // fits the current widget size
    let epigraph: String?        // dedication / epigraph (e.g. "(for Harlem Magic)")
    let pageIndex: Int
    let totalPages: Int
}

// MARK: - Timeline Provider

struct PoemTimelineProvider: TimelineProvider {

    // Placeholder shown while the widget loads for the first time.
    func placeholder(in context: Context) -> PoemEntry {
        PoemEntry(
            date: .now,
            title: "Poem of the Day",
            author: "Loading…",
            excerpt: "A new poem every day\nright on your home screen.",            epigraph: nil,            pageIndex: 1,
            totalPages: 1
        )
    }

    // Snapshot used in the widget gallery preview.
    func getSnapshot(in context: Context, completion: @escaping (PoemEntry) -> Void) {
        completion(makeEntry(from: PoemStore.loadPagedPoem()))
    }

    // Full timeline — refresh roughly every 30 minutes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PoemEntry>) -> Void) {
        Task {
            let paged = await PoemStore.loadPagedPoemRemote()
            let entry = makeEntry(from: paged)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    // MARK: Helpers

    private func makeEntry(from paged: PagedPoem) -> PoemEntry {
        let page = paged.pages.first ?? paged.poem.poem
        return PoemEntry(
            date: .now,
            title: paged.poem.title,
            author: paged.poem.author,
            excerpt: page,
            epigraph: paged.poem.epigraph,
            pageIndex: 1,
            totalPages: paged.pages.count
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
                    .font(.caption)
                    .padding(.leading, 10)
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text("by \(entry.author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if entry.totalPages > 1 {
                    Text("p. \(entry.pageIndex)/\(entry.totalPages)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let epi = entry.epigraph, !epi.isEmpty {
                MarkdownRenderer.epigraphText(from: epi)
                    .font(.footnote)
                    .padding(.leading, 16)
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text("by \(entry.author)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if entry.totalPages > 1 {
                    Text("Page \(entry.pageIndex) of \(entry.totalPages)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if let epi = entry.epigraph, !epi.isEmpty {
                MarkdownRenderer.epigraphText(from: epi)
                    .font(.title3)
                    .padding(.leading, 20)
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
        StaticConfiguration(kind: kind, provider: PoemTimelineProvider()) { entry in
            PoemWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Poem of the Day")
        .description("Displays today's poem right on your home screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Small", as: .systemSmall) {
    PoemOfTheDayWidget()
} timeline: {
    PoemEntry(date: .now, title: "The Road Not Taken", author: "Robert Frost",
              excerpt: "Two roads diverged in a yellow wood,\nAnd sorry I could not travel both…",              epigraph: nil,              pageIndex: 1, totalPages: 2)
}

#Preview("Medium", as: .systemMedium) {
    PoemOfTheDayWidget()
} timeline: {
    PoemEntry(date: .now, title: "The Road Not Taken", author: "Robert Frost",
              excerpt: "Two roads diverged in a yellow wood,\nAnd sorry I could not travel both\nAnd be one traveler, long I stood\nAnd looked down one as far as I could\nTo where it bent in the undergrowth;",
              epigraph: nil,
              pageIndex: 1, totalPages: 2)
}

#Preview("Large", as: .systemLarge) {
    PoemOfTheDayWidget()
} timeline: {
    PoemEntry(date: .now, title: "The Road Not Taken", author: "Robert Frost",
              excerpt: "Two roads diverged in a yellow wood,\nAnd sorry I could not travel both\nAnd be one traveler, long I stood\nAnd looked down one as far as I could\nTo where it bent in the undergrowth;\n\nThen took the other, as just as fair,\nAnd having perhaps the better claim,\nBecause it was grassy and wanted wear;\nThough as for that the passing there\nHad worn them really about the same,",
              epigraph: nil,
              pageIndex: 1, totalPages: 2)
}
#endif
