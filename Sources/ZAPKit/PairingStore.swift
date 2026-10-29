import Foundation

/// A paired Fire TV. Stored as JSON (mode 0600, folder 0700) in ~/Library/Application Support/ZAP/.
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

    /// ZAP's own folder. Not "ZAP": that is the ZAP web security scanner's folder, which its Homebrew cask removes.
    public static let directory = applicationSupport.appendingPathComponent("ZAP Remote", isDirectory: true)
    /// Where pre-release 1.0 builds kept their files, inside the scanner's folder name; moved once.
    static let previousDirectory = applicationSupport.appendingPathComponent("ZAP", isDirectory: true)
    /// Where the pre-1.0 "Fire Remote" builds kept their data.
    static let legacyDirectory = applicationSupport.appendingPathComponent("Fire Remote", isDirectory: true)

    public static var deviceFile: URL { directory.appendingPathComponent("device.json") }
    public static var appsFile: URL { directory.appendingPathComponent("apps.json") }

    /// Marks that the pre-1.0 store was looked at once, so a later "Forget This TV" can't be undone by a
    /// second migration.
    static var migrationMarker: URL { directory.appendingPathComponent(".legacy-store-checked") }

    /// Runs once, so nobody has to pair again and a later "Forget This TV" can't be undone:
    /// - files from pre-release builds in `…/ZAP` are moved to `…/ZAP Remote` (copied, read back, then only ZAP's
    ///   own files are removed from the old folder — anything else in it is left alone);
    /// - otherwise a pairing from the pre-1.0 "Fire Remote" builds is copied (never moved).
    public static func migrateLegacyStoreIfNeeded() {
        let files = FileManager.default
        guard !files.fileExists(atPath: migrationMarker.path) else { return }
        defer { try? write(Data(), to: migrationMarker) }
        guard !files.fileExists(atPath: deviceFile.path) else { return }
        if files.fileExists(atPath: previousDirectory.appendingPathComponent("device.json").path) {
            moveOwnFiles(from: previousDirectory)
            return
        }
        guard files.fileExists(atPath: legacyDirectory.appendingPathComponent("device.json").path) else { return }
        for name in ["device.json", "apps.json"] {
            if let data = try? Data(contentsOf: legacyDirectory.appendingPathComponent(name)) {
                try? write(data, to: directory.appendingPathComponent(name))
            }
        }
    }

    private static let ownFiles = ["device.json", "apps.json", ".legacy-store-checked"]
    private static let ownFolders = ["icons", "icons-v2"]

    private static func moveOwnFiles(from old: URL) {
        let files = FileManager.default
        for name in ["device.json", "apps.json"] {
            if let data = try? Data(contentsOf: old.appendingPathComponent(name)) {
                try? write(data, to: directory.appendingPathComponent(name))
            }
        }
        // Remove the old copies only once the pairing reads back from the new place.
        guard load() != nil else { return }
        for name in ownFiles + ownFolders { try? files.removeItem(at: old.appendingPathComponent(name)) }
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
        for folder in [directory, previousDirectory, legacyDirectory] {
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
