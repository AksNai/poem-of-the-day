import Foundation
import UIKit

enum WidgetAppearanceStore {
    static let appGroupID = "group.com.aksha.poemoftheday"

    private static let overlayOpacityKey = "widgetOverlayOpacity"
    private static let wallpaperFileName = "widget-wallpaper.jpg"

    static func loadOverlayOpacity() -> Double {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        let value = defaults.object(forKey: overlayOpacityKey) as? Double ?? 0.28
        return min(max(value, 0.0), 0.75)
    }

    static func saveOverlayOpacity(_ opacity: Double) {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        let clamped = min(max(opacity, 0.0), 0.75)
        defaults.set(clamped, forKey: overlayOpacityKey)
    }

    static func hasWallpaperImage() -> Bool {
        guard let url = wallpaperImageURL() else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func loadWallpaperImage() -> UIImage? {
        guard let url = wallpaperImageURL() else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }

    static func saveWallpaperImageData(_ imageData: Data) -> Bool {
        guard let image = UIImage(data: imageData),
              let jpegData = image.jpegData(compressionQuality: 0.92),
              let url = wallpaperImageURL() else {
            return false
        }

        do {
            try jpegData.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private static func wallpaperImageURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        return containerURL.appendingPathComponent(wallpaperFileName)
    }
}
