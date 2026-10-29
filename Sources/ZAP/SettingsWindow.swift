import AppKit
import Observation
import SwiftUI
import ZAPKit

// The Settings window: a separate, native macOS window with a permanent sidebar of six sections.

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, device, apps, voice, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .device: return "Device"
        case .apps: return "Apps"
        case .voice: return "Voice"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "switch.2"
        case .device: return "tv"
        case .apps: return "square.grid.2x2"
        case .voice: return "mic"
        case .advanced: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

/// Which section is open, plus the sheets and confirmations of the Settings window (the toolchain lacks
/// SwiftUI's @State macro, so view state lives here).
@MainActor
@Observable
final class SettingsNavigation {
    var section: SettingsSection = .general

    var renaming = false
    var renameText = ""
    var confirmingForget = false
    var confirmingPairAgain = false
    /// The pairing flow this window opened (`RemoteModel.pairingSession`); its sheet closes when that flow ends.
    var pairingSession: Int?
    var showingDeviceInfo = false

    var choosingApp = false
    /// Shortcut being replaced in the app chooser (nil = adding).
    var replacingAppID: String?
    var appSearch = ""
    var confirmingRestoreApps = false
    /// The shortcut row a drag is currently over (highlight only; the dragged ID travels with the drag).
    var dropTargetID: String?

    var confirmingHideMenuBarIcon = false
    var showingShortcuts = false
    var diagnosticsCopied = false

    /// About → Check for Updates: one request to GitHub per click, never in the background.
    private(set) var checkingForUpdates = false
    private(set) var updateResult: UpdateCheckResult?
    var showingUpdateResult = false

    func checkForUpdates() {
        guard !checkingForUpdates else { return }
        checkingForUpdates = true
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        Task {
            let result = await UpdateChecker.check(installedVersion: version)
            checkingForUpdates = false
            updateResult = result
            showingUpdateResult = true
        }
    }

    /// Bumped whenever the window becomes key, so permission and login-item states are re-read.
    private(set) var refreshTick = 0

    func refresh() {
        refreshTick += 1
        AppPreferences.shared.refresh()
    }

    func select(offset: Int) {
        let all = SettingsSection.allCases
        guard let index = all.firstIndex(of: section) else { return }
        section = all[(index + offset + all.count) % all.count]
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    let navigation = SettingsNavigation()
    private var window: NSWindow?

    static let defaultSize = NSSize(width: 820, height: 660)  // every section fits without scrolling
    static let minimumSize = NSSize(width: 660, height: 440)

    func show(_ section: SettingsSection? = nil) {
        if let section { navigation.section = section }
        let window = self.window ?? makeWindow()
        self.window = window
        StandardMenus.installIfNeeded()
        fitOnScreen(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        navigation.refresh()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar puts the title beside the traffic lights, as in the approved design.
        window.toolbar = NSToolbar(identifier: "ZAPSettingsToolbar")
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(DS.Settings.windowBackground)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.moveToActiveSpace)
        // The content view runs under the unified title bar, so the window's minimum adds its height.
        window.contentMinSize = NSSize(width: Self.minimumSize.width, height: Self.minimumSize.height + 52)
        window.delegate = self

        let host = NSHostingView(rootView: SettingsRootView(model: RemoteModel.shared, navigation: navigation))
        host.sizingOptions = []  // the window, not the SwiftUI content, decides the size
        window.contentView = host
        window.setContentSize(Self.defaultSize)
        window.setFrameAutosaveName(PreferencesMigration.settingsWindowAutosaveName)
        if !window.setFrameUsingName(PreferencesMigration.settingsWindowAutosaveName) { window.center() }
        return window
    }

#if ZAP_DEVTOOLS
    /// Screenshots and layout checks: a known content size instead of the remembered one.
    func setContentSizeForCapture(_ size: NSSize) {
        window?.setFrameAutosaveName("")  // never overwrite the remembered window position
        window?.setContentSize(size)
    }
#endif

    /// Keeps the window inside the visible area of its screen (small MacBooks, scaled resolutions, Dock).
    private func fitOnScreen(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        if frame != window.frame { window.setFrame(frame, display: false) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        navigation.refresh()
    }
}

/// An agent app has no visible menu bar, but its key equivalents still work while one of its windows is
/// key: Edit (copy/paste in text fields), Close Window and Quit.
@MainActor
enum StandardMenus {
    static func installIfNeeded() {
        let main = NSApp.mainMenu ?? NSMenu()
        if NSApp.mainMenu == nil { NSApp.mainMenu = main }
        if main.items.first(where: { $0.submenu?.items.contains { $0.keyEquivalent == "q" } == true }) == nil {
            let app = NSMenu(title: "to.zap")
            app.addItem(withTitle: "Settings…", action: #selector(NSApplication.zapShowSettings(_:)), keyEquivalent: ",")
            app.addItem(.separator())
            app.addItem(withTitle: "Quit to.zap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            let item = NSMenuItem(title: "to.zap", action: nil, keyEquivalent: "")
            item.submenu = app
            main.insertItem(item, at: 0)
        }
        if main.item(withTitle: "Edit") == nil {
            let edit = NSMenu(title: "Edit")
            edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
            edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
            edit.addItem(.separator())
            edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            item.submenu = edit
            main.addItem(item)
        }
        if main.item(withTitle: "Window") == nil {
            let window = NSMenu(title: "Window")
            window.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
            item.submenu = window
            main.addItem(item)
        }
    }
}

extension NSApplication {
    @objc func zapShowSettings(_ sender: Any?) {
        MainActor.assumeIsolated { SettingsWindowController.shared.show() }
    }
}

// MARK: - Root

struct SettingsRootView: View {
    let model: RemoteModel
    let navigation: SettingsNavigation

    var body: some View {
        let reduce = AccessibilityPrefs.shared.motionReduced
        HStack(spacing: 0) {
            SettingsSidebar(navigation: navigation)
            SettingsContent(model: model, navigation: navigation)
                .id(navigation.section)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: DS.Settings.panelRadius, style: .continuous)
                    .fill(DS.Settings.panel))
                .overlay(RoundedRectangle(cornerRadius: DS.Settings.panelRadius, style: .continuous)
                    .strokeBorder(DS.Settings.panelStroke))
                .clipShape(RoundedRectangle(cornerRadius: DS.Settings.panelRadius, style: .continuous))
                .padding([.trailing, .bottom], 12)
                .padding(.top, 4)
                .animation(reduce ? nil : .easeOut(duration: 0.14), value: navigation.section)
        }
        .frame(minWidth: SettingsWindowController.minimumSize.width, minHeight: SettingsWindowController.minimumSize.height)
        .background(DS.Settings.windowBackground.ignoresSafeArea())
        .foregroundStyle(DS.Palette.textPrimary)
        .tint(DS.Settings.on)
        .environment(\.colorScheme, .dark)
        // At window level, so the result of Check for Updates appears even if another section is open by then.
        .modifier(UpdateResultAlert(navigation: navigation))
    }
}

private struct SettingsContent: View {
    let model: RemoteModel
    let navigation: SettingsNavigation

    var body: some View {
        switch navigation.section {
        case .general: GeneralSettingsPage(model: model, navigation: navigation)
        case .device: DeviceSettingsPage(model: model, navigation: navigation)
        case .apps: AppsSettingsPage(model: model, navigation: navigation)
        case .voice: VoiceSettingsPage(model: model, navigation: navigation)
        case .advanced: AdvancedSettingsPage(model: model, navigation: navigation)
        case .about: AboutSettingsPage(navigation: navigation)
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    let navigation: SettingsNavigation
    /// Keyboard focus follows ↑ / ↓, so Space never jumps back to a section that is no longer selected.
    @FocusState private var focused: SettingsSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(SettingsSection.allCases.enumerated()), id: \.element) { index, section in
                Button { navigation.section = section } label: {
                    SidebarLabel(section: section, selected: navigation.section == section)
                }
                .buttonStyle(SidebarButtonStyle(selected: navigation.section == section))
                .focused($focused, equals: section)
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .onMoveCommand { direction in
                    switch direction {
                    case .up: navigation.select(offset: -1)
                    case .down: navigation.select(offset: 1)
                    default: return
                    }
                    focused = navigation.section
                }
                .help("\(section.title) (⌘\(index + 1))")
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(navigation.section == section ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .frame(width: DS.Settings.sidebarWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }
}

private struct SidebarLabel: View {
    let section: SettingsSection
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 22)
                .foregroundStyle(selected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
            Text(section.title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .contentShape(Rectangle())
    }
}

private struct SidebarButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SidebarButton(label: configuration.label, pressed: configuration.isPressed, selected: selected)
    }
}

private struct SidebarButton<Label: View>: View {
    let label: Label
    let pressed: Bool
    let selected: Bool
    @StateObject private var hover = HoverState()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        label
            .background(shape.fill(selected ? DS.Settings.selection
                                   : (pressed ? DS.Settings.selection : (hover.isHovering ? DS.Settings.hover : .clear))))
            .contentShape(shape)
            .contentShape(.focusEffect, shape)
            .onHover { hover.isHovering = $0 }
    }
}

// MARK: - Page building blocks

/// A page: title, one-line description, then its rows. Scrolls when the window is short.
struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 16)
                content
            }
            .padding(DS.Settings.contentPadding)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(DS.Settings.divider).frame(height: 1).accessibilityHidden(true)
    }
}

/// Title and description on the leading side; `note` adds a small status line (approval needed, errors…).
struct SettingsRowText: View {
    let title: String
    var subtitle: String?
    var note: String?
    var noteIsWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13, weight: .medium))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note {
                Label(note, systemImage: noteIsWarning ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(noteIsWarning ? DS.Palette.warning : DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row whose trailing control is a real switch. VoiceOver reads the title, then the description.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    var note: String?
    var noteIsWarning = false
    let isOn: Binding<Bool>
    var enabled = true

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsRowText(title: title, subtitle: subtitle, note: note, noteIsWarning: noteIsWarning)
                .opacity(enabled ? 1 : 0.6)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DS.Settings.on)
                .disabled(!enabled)
                .accessibilityHint([subtitle, note].compactMap { $0 }.joined(separator: " "))
        }
        .padding(.vertical, 12)
        .frame(minHeight: DS.Settings.rowMinHeight)
    }
}

/// A row with a trailing value or control.
struct SettingsValueRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var note: String?
    var noteIsWarning = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsRowText(title: title, subtitle: subtitle, note: note, noteIsWarning: noteIsWarning)
            trailing
        }
        .padding(.vertical, 12)
        .frame(minHeight: DS.Settings.rowMinHeight)
    }
}

/// A full-width list button (Device Information, Pair Again…, Forget This TV…, Add App Shortcut).
struct SettingsListButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        SettingsListButton(label: configuration.label, pressed: configuration.isPressed, destructive: destructive)
    }
}

private struct SettingsListButton<Label: View>: View {
    let label: Label
    let pressed: Bool
    let destructive: Bool
    @StateObject private var hover = HoverState()
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Settings.groupRadius, style: .continuous)
        let fill: Color = destructive
            ? (pressed || hover.isHovering ? DS.Settings.dangerFillHover : DS.Settings.dangerFill)
            : (pressed ? DS.Settings.groupPressed : (hover.isHovering ? DS.Settings.groupHover : DS.Settings.group))
        label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(destructive ? DS.Settings.danger : DS.Palette.textPrimary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(shape.fill(isEnabled ? fill : DS.Settings.group))
            .overlay(shape.strokeBorder(DS.Settings.panelStroke))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(shape)
            .contentShape(.focusEffect, shape)
            .onHover { hover.isHovering = $0 }
    }
}

/// A rounded group for related rows (device card, app list).
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Settings.groupRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(DS.Settings.group))
            .overlay(shape.strokeBorder(DS.Settings.panelStroke))
            .clipShape(shape)
    }
}

/// Small status capsule ("Pending verification", "Unavailable in preview").
struct SettingsBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(DS.Palette.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
    }
}
