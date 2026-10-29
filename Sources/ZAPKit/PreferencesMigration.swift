import Foundation

/// The few defaults operations the migration needs; `UserDefaults` provides them, tests use memory.
public protocol PreferenceStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func bool(forKey key: String) -> Bool
}

extension UserDefaults: PreferenceStore {}

/// Pre-release builds used the bundle identifier `local.fireremote.app`, so their preferences live in that
/// defaults domain. Release builds are `local.zap.app`; this moves the known settings across once.
public enum PreferencesMigration {
    public static let legacyDomain = "local.fireremote.app"
    public static let legacyPreviewDomain = "local.fireremote.app.preview"
    public static let markerKey = "preferencesMigratedFromLegacyDomain"

    /// ZAP's own settings (Settings → General / Voice / Advanced, shortcuts, the TV's AirPlay receiver name).
    public static let preferenceKeys = ["quickActions", "showAppIcons", "voiceMode", "allowServerRecognition",
                                        "globalPushToTalk", "showMenuBarIcon", "showNowPlaying", "animationFeedback",
                                        "checkConnectionOnOpen", "airPlayReceiverNames"]
    /// The Settings window's frame autosave name; AppKit stores the frame as "NSWindow Frame <name>".
    public static let settingsWindowAutosaveName = "ZAPSettingsWindow"
    /// What moves from pre-release builds: the settings and the window position. Other legacy keys (such as the
    /// developer automation switch or the status item position) are dropped with the old domain.
    public static var migratedKeys: [String] { preferenceKeys + ["NSWindow Frame \(settingsWindowAutosaveName)"] }

    /// Copies `keys` that exist in `legacy` and are not set in `target`, then calls `removeLegacy` only if every
    /// copied value reads back identical, so nothing is lost if a write fails. Runs once (marker in `target`);
    /// the marker is set before the legacy domain is removed, so a failed removal leaves a harmless copy.
    /// Returns the keys copied, or nil if nothing was done.
    @discardableResult
    public static func migrate(from legacy: PreferenceStore, to target: PreferenceStore, keys: [String],
                               removeLegacy: () -> Void) -> [String]? {
        guard !target.bool(forKey: markerKey) else { return nil }
        var copied: [String] = []
        for key in keys {
            guard let value = legacy.object(forKey: key), target.object(forKey: key) == nil else { continue }
            target.set(value, forKey: key)
            copied.append(key)
        }
        let intact = copied.allSatisfy { key in
            guard let written = target.object(forKey: key) as AnyObject?,
                  let original = legacy.object(forKey: key) as AnyObject? else { return false }
            return written.isEqual(original)
        }
        guard intact else { return nil }   // keep the legacy copy and try again next launch
        target.set(true, forKey: markerKey)
        removeLegacy()
        return copied
    }
}
