import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Timeline Entry

struct PoemEntry: TimelineEntry {
    let date: Date
    let title: String
    let author: String
    let pageText: String
    let page: Int
    let totalPages: Int
}

// MARK: - Provider

struct PoemProvider: AppIntentTimelineProvider {
    typealias Entry = PoemEntry
    typealias Intent = PoemPageIntent

    func placeholder(in context: Context) -> PoemEntry {
        PoemEntry(date: .now, title: "Poem of the Day", author: "...",
                  pageText: "Loading...", page: 1, totalPages: 1)
    }

    func snapshot(for configuration: PoemPageIntent, in context: Context) async -> PoemEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: PoemPageIntent, in context: Context) async -> Timeline<PoemEntry> {
        let e = await entry(for: configuration)
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
        return Timeline(entries: [e], policy: .after(next))
    }

    private func entry(for config: PoemPageIntent) async -> PoemEntry {
        let paged = await PoemStore.loadPagedPoemRemote()
        let total = max(1, paged.pages.count)
        let idx = max(0, min(config.pageNumber - 1, total - 1))
        let text = paged.pages.indices.contains(idx) ? paged.pages[idx] : paged.poem.poem
        return PoemEntry(date: .now, title: paged.poem.title, author: paged.poem.author,
                         pageText: text, page: idx + 1, totalPages: total)
    }
}

// MARK: - Widget View

struct PoemWidgetView: View {
    var entry: PoemEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(1)

            Text("by \(entry.author)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Divider()

            Text(entry.pageText)
                .font(.caption)
                .lineLimit(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Text("\(entry.page)/\(entry.totalPages)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .containerBackground(Color(uiColor: .systemBackground), for: .widget)
    }
}

// MARK: - Widget & Bundle

struct PoemWidget: Widget {
    let kind = "PoemWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PoemPageIntent.self,
                               provider: PoemProvider()) { entry in
            PoemWidgetView(entry: entry)
        }
        .configurationDisplayName("Poem Page")
        .description("Shows one page of today's poem. Stack multiple for scrollable pages.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct PoemWidgetBundle: WidgetBundle {
    var body: some Widget {
        PoemWidget()
    }
}
