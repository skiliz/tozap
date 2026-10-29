import AppKit
import CoreServices
import SwiftUI

@main
struct ZAPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Same key as `AppPreferences.showMenuBarIcon` (Settings → General).
    @AppStorage("showMenuBarIcon", store: AppDefaults.store) private var showMenuBarIcon = true
    private let model = RemoteModel.shared

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            RemotePanel(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The remote silhouette with its status lights (see `MenuBarIcon`); only the icon, never text, in the menu
/// bar. Everything it shows comes from `RemoteModel.menuBarStatus`.
struct MenuBarLabel: View {
    let model: RemoteModel

    var body: some View {
        let description = model.menuBarDescription
        Image(nsImage: MenuBarIcon.image(model.menuBarState))
            .renderingMode(.original)
            .help(description)
            .accessibilityLabel("ZAP")
            .accessibilityValue(description)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Read while the "open application" event is still the current one.
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return }
        launchedAsLoginItem = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            RemoteModel.shared.start()
            AppPreferences.shared.refresh()
            Task { @MainActor in
                // The status item exists once SwiftUI has built the menu bar extra.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                MenuBarStatusText.track(RemoteModel.shared)
            }
            let prefs = AppPreferences.shared
            // Never invisible: with the icon hidden, every launch except a confirmed login-item launch
            // opens Settings (if macOS doesn't mark the login launch, Settings simply opens then too).
            let quietLogin = launchedAsLoginItem && prefs.loginItemStatus == .enabled
            // Not paired yet: open Settings → Device so the first run never shows nothing (the menu bar icon
            // can be hidden behind a notch or a crowded menu bar).
            if !RemoteModel.shared.isPaired, !RemoteModel.offlinePreview {
                SettingsWindowController.shared.show(.device)
            } else if RemoteModel.offlinePreview || (!prefs.showMenuBarIcon && !quietLogin) {
                var previewSection: SettingsSection?
#if ZAP_DEVTOOLS
                // The preview can open on a chosen section: `-ZAPSettingsSection about`.
                if RemoteModel.offlinePreview {
                    previewSection = UserDefaults.standard.string(forKey: "ZAPSettingsSection").flatMap(SettingsSection.init(rawValue:))
                }
#endif
                SettingsWindowController.shared.show(prefs.showMenuBarIcon ? previewSection : .general)
            }
#if ZAP_DEVTOOLS
            // Screenshots: `-ZAPSettingsSection about -ZAPCaptureSettings <file.png>` opens that section (in the
            // preview or with the paired TV), captures ZAP's own window, then quits.
            if let path = UserDefaults.standard.string(forKey: "ZAPCaptureSettings") {
                guard let section = UserDefaults.standard.string(forKey: "ZAPSettingsSection").flatMap(SettingsSection.init(rawValue:)) else {
                    print("-ZAPCaptureSettings needs -ZAPSettingsSection with one of: \(SettingsSection.allCases.map(\.rawValue))")
                    NSApp.terminate(nil)
                    return
                }
                SettingsWindowController.shared.show(section)
                // `-ZAPCaptureSize 820x580` captures at that content size (default: the window's own size).
                if let size = UserDefaults.standard.string(forKey: "ZAPCaptureSize")?.split(separator: "x").compactMap({ Double($0) }),
                   size.count == 2 {
                    SettingsWindowController.shared.setContentSizeForCapture(NSSize(width: size[0], height: size[1]))
                }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await PanelCapture.capture(to: URL(fileURLWithPath: path))
                    NSApp.terminate(nil)
                }
            }
#endif
        }
    }

    /// Opening ZAP again (Finder, Spotlight, Launchpad) while it runs shows Settings — the way back when the
    /// menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            AppPreferences.shared.refresh()  // the icon may have been ⌘-dragged out of the menu bar
            SettingsWindowController.shared.show(AppPreferences.shared.showMenuBarIcon ? nil : .general)
        }
        return false
    }

#if ZAP_DEVTOOLS
    /// Developer automation (`zapremote://…`), ignored unless explicitly enabled. Not in the public app.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { RemoteModel.shared.handleURL(url) }
        }
    }
#endif
}
