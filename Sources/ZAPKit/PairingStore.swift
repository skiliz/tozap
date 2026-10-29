import Foundation

/// A paired Fire TV. Stored as JSON (mode 0600, folder 0700) in ~/Library/Application Support/to.zap/.
public struct PairedDevice: Codable, Sendable, Equatable {
    public var host: String
    public var token: String
    /// DER of the pinned Amazon "Turnstile Server" root the device's TLS chain must verify to.
    public var rootCertificate: Data
    /// Friendly name the TV advertises over Bonjour (TXT "n").
    public var deviceName: String?
    /// Stable ID the TV advertises over Bonjour (TXT "u"); used to find it again after an IP change.
    public var deviceID: String?
    /// Serial number from the authenticated properties call; confirms identity after rediscovery.
    public var serial: String?
    /// Optional local nickname chosen in Settings.
    public var nickname: String?
    /// Fire OS version ("osVersion") from the same authenticated properties call; nil until it was read.
    public var softwareVersion: String?
    public var clientName: String
    public var pairedAt: Date

    public init(host: String, token: String, rootCertificate: Data, deviceName: String?, deviceID: String? = nil,
                serial: String? = nil, nickname: String? = nil, softwareVersion: String? = nil,
                clientName: String, pairedAt: Date) {
        self.host = host
        self.token = token
        self.rootCertificate = rootCertificate
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.serial = serial
        self.nickname = nickname
        self.softwareVersion = softwareVersion
        self.clientName = clientName
        self.pairedAt = pairedAt
    }

    /// Nickname, else the TV's own name, else a generic label. Never the IP address.
    public var displayName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty { return nickname }
        if let deviceName, !deviceName.isEmpty { return deviceName }
        return "Fire TV"
    }
}

public enum PairingStore {
    /// `ZAP_SUPPORT_DIR` lets the test runner and developer tools (plain executables, not the app bundle) use a
    /// temporary folder. The app itself always uses the real one.
    static let applicationSupport = (Bundle.main.bundleIdentifier == nil
        ? ProcessInfo.processInfo.environment["ZAP_SUPPORT_DIR"] : nil)
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    /// to.zap's own folder.
    public static let directory = applicationSupport.appendingPathComponent("to.zap", isDirectory: true)
    /// Where pre-release builds kept their files, newest first: "ZAP Remote", then "ZAP" (the ZAP web security
    /// scanner's folder name). Moved once.
    static let previousDirectories = ["ZAP Remote", "ZAP"].map { applicationSupport.appendingPathComponent($0, isDirectory: true) }
    /// Where the pre-1.0 "Fire Remote" builds kept their data.
    static let legacyDirectory = applicationSupport.appendingPathComponent("Fire Remote", isDirectory: true)

    public static var deviceFile: URL { directory.appendingPathComponent("device.json") }
    public static var appsFile: URL { directory.appendingPathComponent("apps.json") }

    /// Marks that the pre-1.0 store was looked at once, so a later "Forget This TV" can't be undone by a
    /// second migration.
    static var migrationMarker: URL { directory.appendingPathComponent(".legacy-store-checked") }

    /// Runs once, so nobody has to pair again and a later "Forget This TV" can't be undone:
    /// - files from pre-release builds in `…/ZAP Remote` or `…/ZAP` are moved to `…/to.zap` (copied, read back, then
    ///   only the app's own files are removed from the old folders — anything else in them is left alone);
    /// - otherwise a pairing from the pre-1.0 "Fire Remote" builds is copied (never moved).
    /// If the copied pairing doesn't read back, nothing old is removed and the next launch tries again.
    public static func migrateLegacyStoreIfNeeded() {
        let files = FileManager.default
        guard !files.fileExists(atPath: migrationMarker.path) else { return }
        guard !files.fileExists(atPath: deviceFile.path) else {
            try? write(Data(), to: migrationMarker)
            return
        }
        if let previous = previousDirectories.first(where: {
            files.fileExists(atPath: $0.appendingPathComponent("device.json").path)
        }) {
            guard moveOwnFiles(from: previous) else { return }
            // Older copies of the token elsewhere go too, so only the new folder holds it.
            for other in previousDirectories where other != previous { removeOwnFiles(from: other) }
            try? write(Data(), to: migrationMarker)
            return
        }
        if files.fileExists(atPath: legacyDirectory.appendingPathComponent("device.json").path) {
            for name in ["device.json", "apps.json"] {
                if let data = try? Data(contentsOf: legacyDirectory.appendingPathComponent(name)) {
                    try? write(data, to: directory.appendingPathComponent(name))
                }
            }
        }
        try? write(Data(), to: migrationMarker)
    }

    private static let ownFiles = ["device.json", "apps.json", ".legacy-store-checked"]
    private static let ownFolders = ["icons", "icons-v2"]

    /// Copies the pairing and app list, and moves the icon caches. Returns false (removing nothing) if the
    /// pairing doesn't read back from the new place.
    private static func moveOwnFiles(from old: URL) -> Bool {
        let files = FileManager.default
        for name in ["device.json", "apps.json"] {
            if let data = try? Data(contentsOf: old.appendingPathComponent(name)) {
                try? write(data, to: directory.appendingPathComponent(name))
            }
        }
        guard load() != nil else { return false }
        for folder in ownFolders where !files.fileExists(atPath: directory.appendingPathComponent(folder).path) {
            try? files.moveItem(at: old.appendingPathComponent(folder), to: directory.appendingPathComponent(folder))
        }
        removeOwnFiles(from: old)
        return true
    }

    /// Removes only the app's own files from an old folder (a cache folder only once it exists in the new place),
    /// then the folder itself if nothing else is left in it.
    private static func removeOwnFiles(from old: URL) {
        let files = FileManager.default
        for name in ownFiles { try? files.removeItem(at: old.appendingPathComponent(name)) }
        for folder in ownFolders where files.fileExists(atPath: directory.appendingPathComponent(folder).path) {
            try? files.removeItem(at: old.appendingPathComponent(folder))
        }
        if (try? files.contentsOfDirectory(atPath: old.path))?.isEmpty == true { try? files.removeItem(at: old) }
    }

    public static func load() -> PairedDevice? {
        guard let data = try? Data(contentsOf: deviceFile) else { return nil }
        return try? decoder.decode(PairedDevice.self, from: data)
    }

    public static func save(_ device: PairedDevice) throws {
        try write(encoder.encode(device), to: deviceFile)
    }

    /// Removes the pairing and the saved app list, including older copies, so the token is gone from disk.
    public static func forget() {
        let files = FileManager.default
        for folder in [directory, legacyDirectory] + previousDirectories {
            for name in ["device.json", "apps.json"] { try? files.removeItem(at: folder.appendingPathComponent(name)) }
        }
        try? write(Data(), to: migrationMarker)
    }

    /// The device's own app list, cached so quick actions work before the first network call.
    public static func loadApps() -> [FireTVApp] {
        guard let data = try? Data(contentsOf: appsFile) else { return [] }
        return ((try? decoder.decode([FireTVApp].self, from: data)) ?? []).filter { FireTVApp.isValidAppID($0.appId) }
    }

    public static func saveApps(_ apps: [FireTVApp]) {
        if let data = try? encoder.encode(apps) { try? write(data, to: appsFile) }
    }

    /// Writes atomically with mode 0600 from the start (the temporary file is never readable by others), and
    /// keeps the folder at 0700.
    static func write(_ data: Data, to url: URL) throws {
        let files = FileManager.default
        let folder = url.deletingLastPathComponent()
        try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard files.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if rename(temporary.path, url.path) != 0 {
            try? files.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
