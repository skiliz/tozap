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

    /// Copies `keys` that exist in `legacy` and are not set in `target`, then calls `removeLegacy` only if every
    /// copied value reads back identical, so nothing is lost if a write fails. Runs once (marker in `target`).
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
