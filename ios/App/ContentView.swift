import SwiftUI

struct ContentView: View {
    @State private var pagedPoem = PoemStore.loadPagedPoem()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pagedPoem.poem.title)
                            .font(.title2.bold())
                        Text("by \(pagedPoem.poem.author)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(pagedPoem.pages.count) page\(pagedPoem.pages.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(pagedPoem.pages.enumerated()), id: \.offset) { idx, page in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Page \(idx + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(page)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }
            .navigationTitle("Poem of the Day")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { pagedPoem = await PoemStore.loadPagedPoemRemote() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                pagedPoem = await PoemStore.loadPagedPoemRemote()
            }
        }
    }
}

#Preview { ContentView() }
