import AppKit
import Observation
import ServiceManagement
import ZAPKit

/// Where ZAP keeps its preferences (the `local.tozap.app` domain). The offline preview works on a copy
/// (`local.tozap.app.preview`), refreshed from the real preferences at each preview launch, so trying things out
/// changes nothing real.
enum AppDefaults {
#if ZAP_DEVTOOLS
    /// `-ZAPOfflinePreview YES` on the command line (argument domain, never stored). Developer builds only.
    static let isOfflinePreview = UserDefaults.standard.bool(forKey: "ZAPOfflinePreview")
#else
    static let isOfflinePreview = false
#endif

    static let preferenceKeys = PreferencesMigration.preferenceKeys


    /// Before anything reads a preference: settings from pre-release builds move to `local.tozap.app` once.
    static func migrateLegacyPreferences() {
        guard Bundle.main.bundleIdentifier == PreferencesMigration.currentDomain, !isOfflinePreview else { return }
        let keys = PreferencesMigration.migratedKeys
        let legacy = PreferencesMigration.legacyDomains.compactMap { UserDefaults(suiteName: $0) }
        guard let source = legacy.first(where: { suite in keys.contains { suite.object(forKey: $0) != nil } }) ?? legacy.first
        else { return }
        PreferencesMigration.migrate(from: source, to: UserDefaults.standard, keys: keys) {
            for domain in PreferencesMigration.legacyDomains + PreferencesMigration.legacyPreviewDomains {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
        }
    }

    static let store: UserDefaults = {
        migrateLegacyPreferences()
        guard isOfflinePreview, let preview = UserDefaults(suiteName: PreferencesMigration.currentDomain + ".preview") else {
            return .standard
        }
        for key in preferenceKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                preview.set(value, forKey: key)
            } else {
                preview.removeObject(forKey: key)
            }
        }
        return preview
    }()
}

/// Settings → General / Advanced preferences, stored in ZAP's own defaults. Every switch here changes real
/// behaviour; anything ZAP can't do is shown as unavailable instead of as a switch.
@MainActor
@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    /// The status item. Hidden only after confirmation; opening ZAP again (Finder, Spotlight) shows Settings.
    var showMenuBarIcon: Bool {
        didSet { AppDefaults.store.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    /// Gates verified Now Playing metadata in the capsule (`NowPlayingPolicy`); nothing is verified yet.
    var showNowPlaying: Bool {
        didSet { AppDefaults.store.set(showNowPlaying, forKey: "showNowPlaying") }
    }
    /// Brief feedback on the menu bar icon when the TV accepts a command. Reduce Motion always applies.
    var animationFeedback: Bool {
        didSet { AppDefaults.store.set(animationFeedback, forKey: "animationFeedback") }
    }
    /// A read-only reachability check when the remote opens. ZAP never polls in the background.
    var checkConnectionOnOpen: Bool {
        didSet { AppDefaults.store.set(checkConnectionOnOpen, forKey: "checkConnectionOnOpen") }
    }

    // MARK: Launch at login (SMAppService, the system login-item mechanism)

    private(set) var loginItemStatus: SMAppService.Status = .notRegistered
    private(set) var loginItemError: String?

    var launchAtLogin: Bool { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }
    var loginItemNeedsApproval: Bool { loginItemStatus == .requiresApproval }

    private init() {
        let defaults = AppDefaults.store
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        showNowPlaying = defaults.object(forKey: "showNowPlaying") as? Bool ?? true
        animationFeedback = defaults.object(forKey: "animationFeedback") as? Bool ?? true
        checkConnectionOnOpen = defaults.object(forKey: "checkConnectionOnOpen") as? Bool ?? true
        refreshLoginItem()
    }

    /// Re-reads what may have changed outside Settings: the login item (System Settings → Login Items) and
    /// the menu bar icon (⌘-dragged out of the menu bar).
    func refresh() {
        refreshLoginItem()
        let shown = AppDefaults.store.object(forKey: "showMenuBarIcon") as? Bool ?? true
        if shown != showMenuBarIcon { showMenuBarIcon = shown }
    }

    func refreshLoginItem() {
        loginItemStatus = SMAppService.mainApp.status
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !RemoteModel.offlinePreview else {
            loginItemError = "Not changed in the offline preview."
            return
        }
        loginItemError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItem()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
