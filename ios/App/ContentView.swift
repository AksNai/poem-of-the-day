import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var poem = PoemStore.loadPagedPoem().poem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(poem.title)
                            .font(.title2.bold())
                        Text("by \(poem.author)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Epigraph / dedication (e.g. "(for Harlem Magic)")
                    if let epigraph = poem.epigraph, !epigraph.isEmpty {
                        MarkdownRenderer.epigraphText(from: epigraph)
                            .font(poem.isQuoteEpigraph ? .footnote : .body)
                            .foregroundStyle(poem.isQuoteEpigraph ? .secondary : .primary)
                            .padding(.leading, poem.isQuoteEpigraph ? 24 : 8)
                            .padding(.top, 4)
                    }

                    MarkdownRenderer.text(from: poem.poem)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Poem of the Day")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            poem = await PoemStore.loadPagedPoemRemote().poem
                            PoemStore.reloadWidgetTimelines()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                poem = await PoemStore.loadPagedPoemRemote().poem
                PoemStore.reloadWidgetTimelines()
            }
        }
    }
}

#Preview { ContentView() }
