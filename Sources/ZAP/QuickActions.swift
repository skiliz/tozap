import AppKit
import CryptoKit
import Foundation
import ImageIO
import Observation
import ZAPKit

/// The customisable shortcut row (`QuickAction`, ZAPKit), stored locally in ZAP's preferences.
@MainActor
@Observable
final class QuickActionsStore {
    static let suggestions = ["Netflix", "Prime Video", "Spotify"]
    static let maxCount = 4

    private(set) var items: [QuickAction]

    init() {
        if let data = AppDefaults.store.data(forKey: "quickActions"),
           let saved = try? JSONDecoder().decode([QuickAction].self, from: data) {
            items = saved
        } else {
            items = Self.suggestions.map { QuickAction(name: $0, appId: nil) }
        }
    }

    var canAdd: Bool { items.count < Self.maxCount }

    /// The shortcuts shown on the remote, in order (number keys 1–4 follow this order).
    var visibleItems: [QuickAction] { items.filter(\.isEnabled) }

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isEnabled != enabled else { return }
        items[index].isEnabled = enabled
        save()
    }

    /// Drag and drop in Settings → Apps.
    func move(_ id: String, to targetID: String) {
        let moved = items.moving(id, to: targetID)
        guard moved != items else { return }
        items = moved
        save()
    }

    /// Keyboard (⌥↑ / ⌥↓) and menu alternative to dragging.
    func move(_ id: String, by offset: Int) {
        let moved = items.moving(id, by: offset)
        guard moved != items else { return }
        items = moved
        save()
    }

    /// Ties suggested names to installed apps once the TV's list is known. A suggestion whose app is already a
    /// shortcut is dropped rather than duplicated.
    func resolve(with apps: [FireTVApp]) {
        var resolved: [QuickAction] = []
        for var item in items {
            if item.appId == nil, let app = apps.matching(item.name).first {
                if items.contains(where: { $0.appId == app.appId }) || resolved.contains(where: { $0.appId == app.appId }) {
                    continue
                }
                item.appId = app.appId
            }
            resolved.append(item)
        }
        if resolved != items {
            items = resolved
            save()
        }
    }

    /// The shortcut with this ID — also after its suggestion was resolved to a real app in the meantime.
    func index(matching id: String) -> Int? {
        items.firstIndex { $0.id == id || "suggested:\($0.name)" == id }
    }

    func app(for item: QuickAction, in apps: [FireTVApp]) -> FireTVApp? {
        guard let id = item.appId else { return nil }
        return apps.first { $0.appId == id }
    }

    func add(_ app: FireTVApp) {
        guard canAdd, !items.contains(where: { $0.appId == app.appId }) else { return }
        items.append(QuickAction(name: shortAppName(app.name), appId: app.appId))
        save()
    }

    func replace(at index: Int, with app: FireTVApp) {
        guard items.indices.contains(index),
              !items.enumerated().contains(where: { $0.offset != index && $0.element.appId == app.appId }) else { return }
        items[index] = QuickAction(name: shortAppName(app.name), appId: app.appId, isEnabled: items[index].isEnabled)
        save()
    }

    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        save()
    }

    func restoreDefaults() {
        items = Self.suggestions.map { QuickAction(name: $0, appId: nil) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { AppDefaults.store.set(data, forKey: "quickActions") }
    }
}

/// "Spotify - Musica e podcast gratis" → "Spotify", "DAZN: Diretta Calcio e Sport" → "DAZN".
func shortAppName(_ name: String) -> String {
    let beforeColon = name.components(separatedBy: CharacterSet(charactersIn: ":|–—")).first ?? name
    let beforeDash = beforeColon.components(separatedBy: " - ").first ?? beforeColon
    let trimmed = beforeDash.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? name : trimmed
}

/// App icons exactly as the TV's app list provides them (Amazon's image servers), downloaded once and
/// cached in ~/Library/Application Support/ZAP/icons. Optional: Settings → Advanced.
@MainActor
@Observable
final class AppIconStore {
    static let shared = AppIconStore()
    static let allowedHosts: Set<String> = ["m.media-amazon.com", "images-na.ssl-images-amazon.com"]

    var enabled: Bool {
        didSet {
            AppDefaults.store.set(enabled, forKey: "showAppIcons")
            if !enabled { images = [:] }
        }
    }
    private(set) var images: [String: NSImage] = [:]

    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private let folder = PairingStore.directory.appendingPathComponent("icons-v2", isDirectory: true)

    /// No cookies, no disk cache, no redirects (a redirect could leave Amazon's image hosts), minimal headers.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "to.zap", "Accept": "image/*"]
        return URLSession(configuration: config, delegate: RefuseRedirects(), delegateQueue: nil)
    }()

    private init() {
        enabled = AppDefaults.store.object(forKey: "showAppIcons") as? Bool ?? true
        URLCache.shared.removeAllCachedResponses()  // left by builds that used the shared session
    }

    func image(for appId: String?) -> NSImage? {
        guard enabled, let appId else { return nil }
        return images[appId]
    }

    /// Loads icons from the disk cache, downloading the missing ones (only from Amazon's image hosts).
    func prefetch(_ apps: [FireTVApp]) {
        guard enabled else { return }
        for app in apps where !requested.contains(app.appId) {
            requested.insert(app.appId)
            let file = folder.appendingPathComponent(Self.cacheName(app.appId))
            if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
                images[app.appId] = image
                continue
            }
            guard !RemoteModel.offlinePreview,  // the preview makes no network requests at all
                  let link = app.tvIconArt, let url = URL(string: link), url.scheme == "https",
                  let host = url.host, Self.allowedHosts.contains(host) else { continue }
            Task {
                guard let data = await Self.download(url), let png = Self.thumbnail(data) else { return }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                         attributes: [.posixPermissions: 0o700])
                try? png.write(to: file, options: .atomic)
                images[app.appId] = NSImage(data: png)
            }
        }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: folder)
        images = [:]
        requested = []
    }

    /// Downscales to at most 192×108 px, keeping the artwork's own aspect ratio.
    /// Cache files are named by a hash of the app ID, never by the ID itself.
    static func cacheName(_ appId: String) -> String {
        SHA256.hash(data: Data(appId.utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
    }

    /// At most 2 MB, stopped as soon as the limit is passed.
    private static func download(_ url: URL) async -> Data? {
        guard let (bytes, response) = try? await session.bytes(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength <= 2_000_000 else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > 2_000_000 { return nil }
            }
        } catch {
            return nil
        }
        return data
    }

    /// Decodes only PNG or JPEG, straight into a thumbnail of at most 192 px (ImageIO never builds the full image).
    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?, ["public.png", "public.jpeg"].contains(type) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 192]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// Icon requests must stay on the allowed Amazon image hosts, so redirects are never followed.
private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
