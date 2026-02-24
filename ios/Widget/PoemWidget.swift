import AppIntents
import SwiftUI
import WidgetKit

struct PoemEntry: TimelineEntry {
    let date: Date
    let title: String
    let author: String
    let pageText: String
    let pageIndex: Int
    let totalPages: Int
    let overlayOpacity: Double
    let hasWallpaper: Bool
}

struct PoemProvider: AppIntentTimelineProvider {
    typealias Entry = PoemEntry
    typealias Intent = PoemPageIntent

    func placeholder(in context: Context) -> PoemEntry {
        PoemEntry(
            date: Date(),
            title: "Poem of the Day",
            author: "Unknown",
            pageText: "This is a placeholder page.",
            pageIndex: 1,
            totalPages: 1,
            overlayOpacity: WidgetAppearanceStore.loadOverlayOpacity(),
            hasWallpaper: WidgetAppearanceStore.hasWallpaperImage()
        )
    }

    func snapshot(for configuration: PoemPageIntent, in context: Context) async -> PoemEntry {
        await makeEntry(for: configuration)
    }

    func timeline(for configuration: PoemPageIntent, in context: Context) async -> Timeline<PoemEntry> {
        let entry = await makeEntry(for: configuration)
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func makeEntry(for configuration: PoemPageIntent) async -> PoemEntry {
        let pagedPoem = await PoemStore.loadPagedPoemRemoteFirst()
        let totalPages = max(1, pagedPoem.pages.count)
        let requestedPage = max(1, configuration.pageNumber)
        let page = min(requestedPage, totalPages)
        let text = pagedPoem.pages[safe: page - 1] ?? pagedPoem.poem.poem

        return PoemEntry(
            date: Date(),
            title: pagedPoem.poem.title,
            author: pagedPoem.poem.author,
            pageText: text,
            pageIndex: page,
            totalPages: totalPages,
            overlayOpacity: WidgetAppearanceStore.loadOverlayOpacity(),
            hasWallpaper: WidgetAppearanceStore.hasWallpaperImage()
        )
    }
}

struct PoemWidgetView: View {
    var entry: PoemProvider.Entry

    var body: some View {
        ZStack {
            if entry.hasWallpaper, let wallpaper = WidgetAppearanceStore.loadWallpaperImage() {
                Image(uiImage: wallpaper)
                    .resizable()
                    .scaledToFill()
                Color.black.opacity(entry.overlayOpacity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(entry.hasWallpaper ? Color.white : Color.primary)

                Text("by \(entry.author)")
                    .font(.caption)
                    .foregroundStyle(entry.hasWallpaper ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(1)

                Divider()

                Text(entry.pageText)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .lineLimit(12)
                    .foregroundStyle(entry.hasWallpaper ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack {
                    Spacer()
                    Text("\(entry.pageIndex)/\(entry.totalPages)")
                        .font(.caption2)
                        .foregroundStyle(entry.hasWallpaper ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .padding(12)
        }
        .clipped()
        .containerBackground(entry.hasWallpaper ? .clear : .background, for: .widget)
    }
}

struct PoemWidget: Widget {
    let kind: String = "PoemWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PoemPageIntent.self, provider: PoemProvider()) { entry in
            PoemWidgetView(entry: entry)
        }
        .configurationDisplayName("Poem Page")
        .description("Shows one page of today's poem. Add multiple pages in a Smart Stack.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct PoemWidgetBundle: WidgetBundle {
    var body: some Widget {
        PoemWidget()
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
