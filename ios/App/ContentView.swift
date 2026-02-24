import SwiftUI
import PhotosUI
import WidgetKit

struct ContentView: View {
    @State private var pagedPoem = PoemStore.loadPagedPoem()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var wallpaperPreview = WidgetAppearanceStore.loadWallpaperImage()
    @State private var overlayOpacity = WidgetAppearanceStore.loadOverlayOpacity()
    @State private var setupStatus = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transparent Widget Setup")
                            .font(.headline)

                        Text("On iOS 26, take a Home Screen screenshot, import it here, then tune dark overlay so the widget blends in.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Text("Upload Wallpaper Screenshot")
                                .font(.subheadline)
                        }

                        if let preview = wallpaperPreview {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dark Overlay: \(Int(overlayOpacity * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $overlayOpacity, in: 0...0.75, step: 0.01)
                                .onChange(of: overlayOpacity) { _, newValue in
                                    WidgetAppearanceStore.saveOverlayOpacity(newValue)
                                    WidgetCenter.shared.reloadAllTimelines()
                                }
                        }

                        if !setupStatus.isEmpty {
                            Text(setupStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(pagedPoem.poem.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("by \(pagedPoem.poem.author)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("Pages for widget stack: \(pagedPoem.pages.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(Array(pagedPoem.pages.enumerated()), id: \.offset) { index, page in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Page \(index + 1)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(page)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Poem of the Day")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task {
                            pagedPoem = await PoemStore.loadPagedPoemRemoteFirst()
                        }
                    }
                }
            }
        }
        .task {
            pagedPoem = await PoemStore.loadPagedPoemRemoteFirst()
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   WidgetAppearanceStore.saveWallpaperImageData(data) {
                    wallpaperPreview = WidgetAppearanceStore.loadWallpaperImage()
                    setupStatus = "Wallpaper saved. Add/edit widgets to align and blend."
                    WidgetCenter.shared.reloadAllTimelines()
                } else {
                    setupStatus = "Could not save screenshot. Try another image."
                }
                selectedPhoto = nil
            }
        }
    }
}

#Preview {
    ContentView()
}
