import AppKit
import SwiftUI
import ZAPKit

private func binding<Value>(_ get: @escaping () -> Value, _ set: @escaping (Value) -> Void) -> Binding<Value> {
    Binding(get: get, set: set)
}

/// Connection state with its dot. Green only while the TV confirmed the connection recently (the same rule
/// as the menu bar and the capsule); a hollow dot means not confirmed. The label always carries the meaning.
struct ConnectionStatusLabel: View {
    let model: RemoteModel

    var body: some View {
        let link = model.menuBarStatus.link
        let connection = model.connection
        HStack(spacing: 6) {
            switch (link, connection) {
            case (_, .checking), (.reconnecting, _):
                ProgressView().controlSize(.mini).frame(width: 10, height: 10)
            case (.unknown, _):
                Circle().strokeBorder(DS.Palette.textTertiary, lineWidth: 1.3).frame(width: 8, height: 8)
            case (.connected, _):
                Circle().fill(DS.Palette.connected).frame(width: 8, height: 8)
            case (.unreachable, _):
                Circle().fill(DS.Palette.warning).frame(width: 8, height: 8)
            case (.preview, _):
                Circle().fill(DS.Palette.textTertiary).frame(width: 8, height: 8)
            }
            Text(model.connectionLabel)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(link == .connected ? DS.Palette.connected : DS.Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - General

struct GeneralSettingsPage: View {
    let model: RemoteModel
    let navigation: SettingsNavigation

    var body: some View {
        let prefs = AppPreferences.shared
        let _ = navigation.refreshTick  // re-read the login item when the window becomes key
        SettingsPage(title: "General", subtitle: "Startup, the menu bar, and how to.zap looks and moves.") {
            SettingsToggleRow(title: "Launch at login",
                              subtitle: "Open to.zap automatically when you log in to this Mac.",
                              note: loginNote(prefs), noteIsWarning: prefs.loginItemError != nil,
                              isOn: binding({ prefs.launchAtLogin }, { prefs.setLaunchAtLogin($0) }),
                              enabled: !RemoteModel.offlinePreview)
            if prefs.loginItemNeedsApproval {
                HStack {
                    Spacer()
                    Button("Open Login Items…") { prefs.openLoginItemsSettings() }
                }
                .padding(.bottom, 12)
            }
            SettingsDivider()
            SettingsToggleRow(title: "Show menu bar icon",
                              subtitle: "The remote opens from this icon. If you hide it, open to.zap again from Applications or Spotlight to come back to Settings.",
                              isOn: binding({ prefs.showMenuBarIcon }, { show in
                                  if show { prefs.showMenuBarIcon = true } else { navigation.confirmingHideMenuBarIcon = true }
                              }))
            SettingsDivider()
            SettingsValueRow(title: "Appearance", subtitle: "to.zap uses its dark graphite design in every macOS appearance.") {
                Text("Dark").font(.system(size: 13)).foregroundStyle(DS.Palette.textSecondary)
            }
            SettingsDivider()
            SettingsToggleRow(title: "Show Now Playing",
                              subtitle: "Show the app and title playing on your TV in the status capsule, when the TV reports them.",
                              note: NowPlayingPolicy.isAvailable ? nil
                                  : "Not available yet: no Fire TV source has been verified. to.zap never shows a guessed title.",
                              isOn: binding({ NowPlayingPolicy.isAvailable && prefs.showNowPlaying }, { prefs.showNowPlaying = $0 }),
                              enabled: NowPlayingPolicy.isAvailable)
            SettingsDivider()
            SettingsToggleRow(title: "Animation feedback",
                              subtitle: "Subtle motion in the remote, and a brief pulse of the menu bar icon when the TV accepts a command.",
                              note: AccessibilityPrefs.shared.reduceMotion ? "Reduce Motion is on, so movement is replaced by fades." : nil,
                              isOn: binding({ prefs.animationFeedback }, { prefs.animationFeedback = $0 }))
            SettingsDivider()
            HStack {
                Spacer()
                Button("Quit to.zap") { NSApplication.shared.terminate(nil) }
            }
            .padding(.top, 18)
        }
        .alert("Hide the menu bar icon?",
               isPresented: binding({ navigation.confirmingHideMenuBarIcon }, { navigation.confirmingHideMenuBarIcon = $0 })) {
            Button("Hide Icon") { prefs.showMenuBarIcon = false }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The remote opens from the menu bar icon. To come back to Settings, open to.zap again from Applications or Spotlight.")
        }
    }

    private func loginNote(_ prefs: AppPreferences) -> String? {
        if let error = prefs.loginItemError { return error }
        if prefs.loginItemNeedsApproval { return "Waiting for your approval in System Settings → General → Login Items." }
        if RemoteModel.offlinePreview { return "Unavailable in the offline preview." }
        return nil
    }
}

// MARK: - Device

struct DeviceSettingsPage: View {
    let model: RemoteModel
    let navigation: SettingsNavigation

    var body: some View {
        SettingsPage(title: "Device", subtitle: "The Fire TV this Mac controls.") {
            if let device = model.device {
                DeviceCard(model: model, device: device, navigation: navigation)
                    .padding(.bottom, 14)
                DeviceInformation(model: model, device: device, navigation: navigation)
                    .padding(.bottom, 14)
                VStack(spacing: 10) {
                    Button { navigation.confirmingPairAgain = true } label: { Text("Pair Again…") }
                        .buttonStyle(SettingsListButtonStyle())
                        .help("Pair with the PIN shown on the TV. The current pairing stays until the new one succeeds.")
                    Button { navigation.confirmingForget = true } label: { Text("Forget This TV…") }
                        .buttonStyle(SettingsListButtonStyle(destructive: true))
                        .help("Remove this TV's pairing from this Mac")
                }
                .disabled(RemoteModel.offlinePreview)
            } else {
                SettingsGroup {
                    HStack(spacing: 14) {
                        DeviceGlyph()
                        SettingsRowText(title: "No Fire TV paired",
                                        subtitle: "Your Mac and the Fire TV must be on the same network. The TV shows a PIN to confirm.")
                        Button("Pair a Fire TV…") {
                            model.beginPairing()
                            navigation.pairingSession = model.pairingSession
                        }
                        .disabled(RemoteModel.offlinePreview)
                    }
                    .padding(16)
                }
            }
        }
        .alert("Rename TV", isPresented: binding({ navigation.renaming }, { navigation.renaming = $0 })) {
            TextField(model.device?.deviceName ?? "Fire TV", text: binding({ navigation.renameText }, { navigation.renameText = $0 }))
            Button("Save") { model.setNickname(navigation.renameText) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The name is used in to.zap on this Mac only. Leave it empty to use the TV's own name.")
        }
        .alert("Pair again with this TV?", isPresented: binding({ navigation.confirmingPairAgain }, { navigation.confirmingPairAgain = $0 })) {
            Button("Continue") {
                model.beginPairing()
                navigation.pairingSession = model.pairingSession
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The TV will show a PIN. to.zap keeps the current pairing until the new one succeeds.")
        }
        .alert("Forget “\(model.title)”?", isPresented: binding({ navigation.confirmingForget }, { navigation.confirmingForget = $0 })) {
            Button("Forget", role: .destructive) { model.forgetDevice() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("to.zap removes the pairing and the saved app list from this Mac. To use this TV again, you'll need the PIN shown on the TV.")
        }
        .sheet(isPresented: binding({ model.page == .pairing && navigation.pairingSession == model.pairingSession }, { shown in
            // Closed by the user (Esc): end the flow. Success or a cancel elsewhere already ended it.
            if !shown, model.page == .pairing, navigation.pairingSession == model.pairingSession { model.cancelPairing() }
        })) {
            PairingSheet(model: model, navigation: navigation)
        }
    }
}

private struct DeviceGlyph: View {
    var body: some View {
        Image(systemName: "tv")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(DS.Palette.textPrimary)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.black.opacity(0.45)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.08)))
            .accessibilityHidden(true)
    }
}

private struct DeviceCard: View {
    let model: RemoteModel
    let device: PairedDevice
    let navigation: SettingsNavigation

    var body: some View {
        SettingsGroup {
            HStack(spacing: 14) {
                DeviceGlyph()
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    ConnectionStatusLabel(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Rename…") {
                    navigation.renameText = device.nickname ?? ""
                    navigation.renaming = true
                }
                .disabled(RemoteModel.offlinePreview)
                .help("Change the name to.zap shows for this TV")
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DeviceInformation: View {
    let model: RemoteModel
    let device: PairedDevice
    let navigation: SettingsNavigation

    var body: some View {
        let expanded = navigation.showingDeviceInfo
        VStack(alignment: .leading, spacing: 0) {
            Button {
                navigation.showingDeviceInfo.toggle()
            } label: {
                HStack {
                    Text("Device Information")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
            }
            .buttonStyle(SettingsListButtonStyle())
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                SettingsGroup {
                    InfoRow(title: "Name on the TV", value: device.deviceName)
                    SettingsDivider()
                    InfoRow(title: "Address", value: device.host)
                    SettingsDivider()
                    InfoRow(title: "Model", value: nil)
                    SettingsDivider()
                    InfoRow(title: "Software", value: device.softwareVersion)
                    SettingsDivider()
                    InfoRow(title: "Serial number", value: device.serial)
                    SettingsDivider()
                    InfoRow(title: "Paired on", value: device.pairedAt.formatted(date: .abbreviated, time: .omitted))
                    SettingsDivider()
                    InfoRow(title: "Security", value: "TLS, Amazon root certificate pinned")
                }
                .padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(model.deviceInfoMessage
                         ?? "Software and serial number come from the paired TV. “Load from TV” asks it once, without waking it.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(model.deviceInfoMessage == nil ? DS.Palette.textTertiary : DS.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if model.deviceInfoLoading { ProgressView().controlSize(.small) }
                    Button("Load from TV") { model.refreshDeviceInfo() }
                        .disabled(model.deviceInfoLoading || RemoteModel.offlinePreview || model.client == nil)
                }
                .padding(.top, 8)
            }
        }
    }
}

private struct InfoRow: View {
    let title: String
    let value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(DS.Palette.textSecondary)
            Spacer(minLength: 8)
            Text(value ?? "Unknown")
                .font(.system(size: 12.5, weight: value == nil ? .regular : .medium))
                .foregroundStyle(value == nil ? DS.Palette.textTertiary : DS.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct PairingSheet: View {
    let model: RemoteModel
    let navigation: SettingsNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PairingPage(model: model)
            HStack {
                Spacer()
                Button("Cancel") { model.cancelPairing() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Apps

struct AppsSettingsPage: View {
    let model: RemoteModel
    let navigation: SettingsNavigation

    var body: some View {
        let store = model.quickActions
        SettingsPage(title: "Apps", subtitle: "The app shortcuts on your remote — up to four, in this order.") {
            if store.items.isEmpty {
                Text("No shortcuts yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .padding(.bottom, 12)
            } else {
                SettingsGroup {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SettingsDivider().padding(.leading, 72) }
                        AppShortcutRow(model: model, navigation: navigation, item: item, index: index)
                    }
                }
                Text("Drag to reorder. With the keyboard, select a shortcut, then ⌥↑ / ⌥↓ moves it, Return replaces it and ⌘⌫ removes it. Switch one off to hide it from the remote without removing it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            }
            Button {
                navigation.replacingAppID = nil
                navigation.appSearch = ""
                navigation.choosingApp = true
            } label: {
                Label("Add App Shortcut", systemImage: "plus")
            }
            .buttonStyle(SettingsListButtonStyle())
            .disabled(!store.canAdd || !model.isPaired)
            if !store.canAdd {
                Text("The remote has room for four shortcuts. Remove one to add another.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .padding(.top, 6)
            }
            HStack {
                Spacer()
                Button("Restore Suggestions…") { navigation.confirmingRestoreApps = true }
            }
            .padding(.top, 16)
        }
        .sheet(isPresented: binding({ navigation.choosingApp }, { navigation.choosingApp = $0 })) {
            AppChooserSheet(model: model, navigation: navigation)
        }
        .alert("Restore the suggested shortcuts?",
               isPresented: binding({ navigation.confirmingRestoreApps }, { navigation.confirmingRestoreApps = $0 })) {
            Button("Restore", role: .destructive) {
                store.restoreDefaults()
                store.resolve(with: model.apps)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your shortcuts are replaced by Netflix, Prime Video and Spotify, matched to the apps on your TV when to.zap knows its app list.")
        }
    }
}

private struct AppShortcutRow: View {
    let model: RemoteModel
    let navigation: SettingsNavigation
    let item: QuickAction
    let index: Int
    @FocusState private var focused: Bool

    var body: some View {
        let store = model.quickActions
        let missing = model.isMissing(item)
        let last = store.items.count - 1
        HStack(spacing: 12) {
            AppIcon(appId: item.appId, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if missing {
                    Text("Not on this TV").font(.system(size: 11.5)).foregroundStyle(DS.Palette.warning)
                } else if item.appId == nil {
                    Text("Matched when to.zap reads your TV's app list")
                        .font(.system(size: 11.5)).foregroundStyle(DS.Palette.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Toggle("Show \(item.name) on the remote",
                   isOn: binding({ item.isEnabled }, { store.setEnabled(item.id, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DS.Settings.on)
                .help(item.isEnabled ? "Shown on the remote" : "Hidden from the remote")
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 26, height: 30)
                .contentShape(Rectangle())
                .help("Drag to reorder")
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(rowFill)
        .contentShape(Rectangle())
        .focusable()
        .focused($focused)
        .onTapGesture { focused = true }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            store.move(item.id, by: press.key == .upArrow ? -1 : 1)
            return .handled
        }
        .onKeyPress(.return) {
            replace()
            return .handled
        }
        .onKeyPress(keys: [.delete]) { press in
            // ⌘⌫, not a bare Delete: the first row can hold focus without the user having chosen it.
            guard press.modifiers.contains(.command) else { return .ignored }
            store.remove(at: index)
            return .handled
        }
        // The dragged ID travels with the drag, so nothing can go stale if a drag is cancelled.
        .draggable(item.id)
        .dropDestination(for: String.self) { ids, _ in
            navigation.dropTargetID = nil
            guard let id = ids.first, id != item.id else { return false }
            let reduce = AccessibilityPrefs.shared.motionReduced
            withAnimation(reduce ? nil : .easeOut(duration: 0.15)) { store.move(id, to: item.id) }
            return true
        } isTargeted: { targeted in
            if targeted {
                navigation.dropTargetID = item.id
            } else if navigation.dropTargetID == item.id {
                navigation.dropTargetID = nil
            }
        }
        .contextMenu {
            Button("Move Up") { store.move(item.id, by: -1) }.disabled(index == 0)
            Button("Move Down") { store.move(item.id, by: 1) }.disabled(index == last)
            Divider()
            Button("Replace…") { replace() }.disabled(!model.isPaired)
            Button("Remove") { store.remove(at: index) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.name)
        .accessibilityAction(named: Text("Move Up")) { store.move(item.id, by: -1) }
        .accessibilityAction(named: Text("Move Down")) { store.move(item.id, by: 1) }
        .accessibilityAction(named: Text("Replace")) { replace() }
        .accessibilityAction(named: Text("Remove")) { store.remove(at: index) }
    }

    private var rowFill: Color {
        if navigation.dropTargetID == item.id { return Color.white.opacity(0.08) }
        return focused ? Color.white.opacity(0.05) : Color.clear
    }

    private func replace() {
        guard model.isPaired else { return }
        navigation.replacingAppID = item.id
        navigation.appSearch = ""
        navigation.choosingApp = true
    }
}

/// Chooses an app from the TV's own list (the copy ZAP saved, or a fresh read when asked).
private struct AppChooserSheet: View {
    let model: RemoteModel
    let navigation: SettingsNavigation

    var body: some View {
        let store = model.quickActions
        let replacing = navigation.replacingAppID
        let query = normalizedText(navigation.appSearch)
        let apps = query.isEmpty ? model.apps : model.apps.filter { normalizedText($0.name).contains(query) }
        VStack(alignment: .leading, spacing: 12) {
            Text(replacing == nil ? "Add App Shortcut" : "Replace Shortcut")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(model.appsFromTV ? "Apps installed on \(model.title)."
                 : "From the app list to.zap saved from \(model.title). Refresh to read it from the TV again.")
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
            TextField("Search apps", text: binding({ navigation.appSearch }, { navigation.appSearch = $0 }))
                .textFieldStyle(.roundedBorder)
            if model.apps.isEmpty {
                Text("to.zap hasn't read your TV's app list yet. Refresh to read it — the TV must be on and on this network.")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                            if index > 0 { SettingsDivider().padding(.leading, 62) }
                            AppChoiceRow(model: model, navigation: navigation, app: app,
                                         added: store.items.contains { $0.appId == app.appId })
                        }
                    }
                }
                .frame(height: 280)
                .background(RoundedRectangle(cornerRadius: DS.Settings.groupRadius, style: .continuous).fill(DS.Settings.group))
                .overlay(RoundedRectangle(cornerRadius: DS.Settings.groupRadius, style: .continuous).strokeBorder(DS.Settings.panelStroke))
            }
            HStack {
                Button("Refresh from TV") { Task { await model.refreshApps() } }
                    .disabled(model.client == nil)
                    .help("Reads the list of installed apps from the TV")
                Spacer()
                Button("Done") { navigation.choosingApp = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct AppChoiceRow: View {
    let model: RemoteModel
    let navigation: SettingsNavigation
    let app: FireTVApp
    let added: Bool

    var body: some View {
        let store = model.quickActions
        let name = shortAppName(app.name)
        HStack(spacing: 12) {
            AppIcon(appId: app.appId, size: 22)
            Text(name).font(.system(size: 13)).lineLimit(1).help(app.name)
            Spacer()
            if added {
                Text("Added").font(.system(size: 12)).foregroundStyle(DS.Palette.textTertiary)
            } else if let replacing = navigation.replacingAppID {
                Button("Choose") {
                    if let index = store.index(matching: replacing) { store.replace(at: index, with: app) }
                    navigation.choosingApp = false
                }
            } else {
                Button("Add") { store.add(app) }
                    .disabled(!store.canAdd)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Voice

struct VoiceSettingsPage: View {
    let model: RemoteModel
    let navigation: SettingsNavigation

    var body: some View {
        let voice = model.voice
        let _ = navigation.refreshTick  // permissions are re-read when the window becomes key
        SettingsPage(title: "Voice", subtitle: "How to.zap understands what you say. The microphone is on only while you hold push-to-talk.") {
            VStack(alignment: .leading, spacing: 6) {
                VoiceModeOption(voice: voice, mode: .local, title: "Apple Speech on this Mac (Italian)",
                                subtitle: localSubtitle(voice))
                VoiceModeOption(voice: voice, mode: .alexa, title: "Alexa on the Fire TV (Amazon cloud)",
                                subtitle: "While you hold the mic, your voice goes through the TV to Amazon's Alexa service, like the voice button on the TV's remote. Alexa answers on the TV.")
            }
            .padding(.bottom, 10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Voice mode")
            if voice.mode == .local, !voice.onDeviceItalian {
                SettingsDivider()
                SettingsToggleRow(title: "Allow Apple server recognition",
                                  subtitle: "This Mac can't recognize Italian on-device. With this on, your voice is sent to Apple for recognition.",
                                  isOn: binding({ voice.allowServerRecognition }, { voice.allowServerRecognition = $0 }))
            }
            SettingsDivider()
            SettingsToggleRow(title: "Push-to-talk anywhere",
                              subtitle: "Hold \(PushToTalkHotKey.displayName) in any app to talk. In the remote, hold V or the Voice button.",
                              note: RemoteModel.offlinePreview ? "Not active in the offline preview."
                                  : (model.hotKeyUnavailable ? "\(PushToTalkHotKey.displayName) is already used by another app, so it isn't active." : nil),
                              noteIsWarning: model.hotKeyUnavailable,
                              isOn: binding({ model.globalShortcutEnabled }, { model.globalShortcutEnabled = $0 }),
                              enabled: !RemoteModel.offlinePreview)
            SettingsDivider()
            PermissionRow(title: "Microphone", permission: voice.microphonePermission,
                          subtitle: "Needed in both modes. to.zap asks the first time you hold the mic.")
            if voice.mode == .local {
                SettingsDivider()
                PermissionRow(title: "Speech Recognition", permission: voice.speechPermission,
                              subtitle: "Needed for Apple Speech. to.zap asks the first time you use it.")
            }
            HStack {
                Spacer()
                Button("Privacy Settings…") {
                    let micOff = voice.microphonePermission == .denied || voice.microphonePermission == .restricted
                    voice.openPrivacySettings(voice.mode == .local && !micOff ? "Privacy_SpeechRecognition" : "Privacy_Microphone")
                }
                .help("Opens System Settings → Privacy & Security")
            }
            .padding(.top, 14)
        }
    }

    private func localSubtitle(_ voice: VoiceController) -> String {
        let base = "Commands like “Apri Netflix” or “Vai a destra”, recognized by Apple Speech."
        return voice.onDeviceItalian
            ? base + " This Mac supports on-device Italian recognition, and to.zap requires it."
            : base + " On-device Italian isn't available on this Mac."
    }
}

private struct VoiceModeOption: View {
    let voice: VoiceController
    let mode: VoiceController.Mode
    let title: String
    let subtitle: String

    var body: some View {
        let selected = voice.mode == mode
        Button { if !voice.isBusy { voice.mode = mode } } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? DS.Settings.on : Color.white.opacity(0.32), lineWidth: 1.5)
                    if selected {
                        Circle().fill(DS.Settings.on).padding(1.5)
                        Circle().fill(Color.white).frame(width: 6, height: 6)
                    }
                }
                .frame(width: 18, height: 18)
                .padding(.top, 1)
                SettingsRowText(title: title, subtitle: subtitle)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: DS.Settings.groupRadius, style: .continuous)
                .fill(selected ? DS.Settings.group : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: DS.Settings.groupRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(voice.isBusy)
        .contentShape(.focusEffect, RoundedRectangle(cornerRadius: DS.Settings.groupRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}

private struct PermissionRow: View {
    let title: String
    let permission: VoiceController.Permission
    let subtitle: String

    var body: some View {
        SettingsValueRow(title: title, subtitle: subtitle,
                         note: permission == .denied || permission == .restricted
                             ? "Turn it on in System Settings → Privacy & Security." : nil,
                         noteIsWarning: true) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(permission == .allowed ? DS.Palette.connected
                                 : (permission == .notAsked ? DS.Palette.textSecondary : DS.Palette.warning))
        }
    }

    private var label: String {
        switch permission {
        case .allowed: return "Allowed"
        case .notAsked: return "Not requested yet"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        }
    }
}

// MARK: - Advanced

struct AdvancedSettingsPage: View {
    let model: RemoteModel
    let navigation: SettingsNavigation

    var body: some View {
        let prefs = AppPreferences.shared
        let icons = AppIconStore.shared
        SettingsPage(title: "Advanced", subtitle: "Connection, privacy and troubleshooting.") {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    SettingsRowText(title: "Connection",
                                    subtitle: "Checks the TV without waking it, and finds it again if its address changed.")
                    ConnectionStatusLabel(model: model)
                }
                Button("Check Now") { model.refreshConnection(force: true) }
                    .disabled(!model.isPaired || RemoteModel.offlinePreview)
            }
            .padding(.vertical, 12)
            .frame(minHeight: DS.Settings.rowMinHeight)
            SettingsDivider()
            SettingsToggleRow(title: "Check connection automatically",
                              subtitle: "A quick read-only check when you open the remote. to.zap never checks in the background.",
                              isOn: binding({ prefs.checkConnectionOnOpen }, { prefs.checkConnectionOnOpen = $0 }))
            SettingsDivider()
            SettingsToggleRow(title: "Show app icons",
                              subtitle: "On by default. Downloads the icons your TV lists from Amazon's image servers (m.media-amazon.com, images-na.ssl-images-amazon.com), which see your IP address. Off keeps to.zap's traffic on your local network.",
                              isOn: binding({ icons.enabled }, { enabled in
                                  icons.enabled = enabled
                                  if enabled { icons.prefetch(model.apps) }
                              }))
            SettingsValueRow(title: "Downloaded icons", subtitle: "Kept in to.zap's folder on this Mac.") {
                Button("Remove") { icons.clearCache() }
                    .disabled(RemoteModel.offlinePreview)
            }
            SettingsDivider()
            KeyboardShortcutsDisclosure(navigation: navigation)
                .padding(.vertical, 12)
            SettingsDivider()
            SettingsValueRow(title: "Diagnostics",
                             subtitle: "Copies the to.zap and macOS versions, the connection state and your voice, icon, shortcut, login and menu bar settings — no names, addresses or tokens — for a bug report.") {
                Button(navigation.diagnosticsCopied ? "Copied" : "Copy Summary") { copyDiagnostics() }
            }
        }
    }

    private func copyDiagnostics() {
        let info = Bundle.main.infoDictionary
        let prefs = AppPreferences.shared
        let voice = model.voice
        let shortcuts = model.quickActions
        var lines = [
            "to.zap \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Paired: \(model.isPaired ? "yes" : "no") · Connection: \(model.connection.label)",
            "Voice: \(voice.mode == .local ? "Apple Speech" : "Alexa") · on-device Italian: \(voice.onDeviceItalian ? "yes" : "no") · push-to-talk anywhere: \(model.globalShortcutEnabled ? "on" : "off")",
            "App icons: \(AppIconStore.shared.enabled ? "on" : "off") · shortcuts: \(shortcuts.items.count) (\(shortcuts.visibleItems.count) shown)",
            "Launch at login: \(prefs.loginItemNeedsApproval ? "needs approval" : (prefs.launchAtLogin ? "on" : "off")) · menu bar icon: \(prefs.showMenuBarIcon ? "shown" : "hidden")",
        ]
        if RemoteModel.offlinePreview { lines.append("Offline preview") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        navigation.diagnosticsCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            navigation.diagnosticsCopied = false
        }
    }
}

private struct KeyboardShortcutsDisclosure: View {
    let navigation: SettingsNavigation

    private static let remote: [(String, String)] = [
        ("← ↑ → ↓", "Navigate (hold to repeat)"), ("Return", "OK"), ("Esc or Delete", "Back"),
        ("Space", "Play / Pause"), ("[  ]", "Rewind / Fast-forward"), ("H", "Home"), ("M", "Menu"),
        ("1 – 4", "Open an app shortcut"), ("Hold V", "Talk"), ("⌘ ,", "Settings"),
    ]

    var body: some View {
        let expanded = navigation.showingShortcuts
        VStack(alignment: .leading, spacing: 10) {
            Button { navigation.showingShortcuts.toggle() } label: {
                HStack(spacing: 16) {
                    SettingsRowText(title: "Keyboard shortcuts", subtitle: "Keys that work while the remote is open, and anywhere.")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                SettingsGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("While the remote is open").font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(DS.Palette.textSecondary)
                        ForEach(Self.remote, id: \.0) { keys, action in ShortcutLine(keys: keys, action: action) }
                        Text("Anywhere").font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .padding(.top, 6)
                        ShortcutLine(keys: "Hold \(PushToTalkHotKey.displayName)", action: "Talk (when Push-to-talk anywhere is on)")
                        Text("In Settings").font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .padding(.top, 6)
                        ShortcutLine(keys: "⌘1 – ⌘\(SettingsSection.allCases.count)", action: "Switch section")
                    }
                    .padding(14)
                }
            }
        }
    }

    private struct ShortcutLine: View {
        let keys: String
        let action: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(keys)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(width: 128, alignment: .leading)
                Text(action).font(.system(size: 12)).foregroundStyle(DS.Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - About

/// The product identity, centred: icon, name, version and signature, then two actions. Legal texts live in
/// the repository and inside the app bundle (LICENSE, THIRD_PARTY_NOTICES.md), not on this page.
struct AboutSettingsPage: View {
    let navigation: SettingsNavigation

    var body: some View {
        let info = Bundle.main.infoDictionary
        GeometryReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    AboutIdentity(version: info?["CFBundleShortVersionString"] as? String ?? "—",
                                  build: info?["CFBundleVersion"] as? String)
                    AboutSignature()
                        .padding(.top, 20)
                    AboutActions(navigation: navigation)
                        .frame(maxWidth: 340)
                        .padding(.top, 26)
                }
                .padding(.horizontal, DS.Settings.contentPadding)
                .padding(.vertical, 24)
                // Centred in the panel when there's room, scrolling when the window is short.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }
}

private struct AboutIdentity: View {
    let version: String
    let build: String?

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                .accessibilityHidden(true)
            // Light weight and gradient as approved; lowercase "to.zap" takes only slight tracking. Tracking also
            // follows the last letter, so the same leading padding re-centres the word.
            Text("to.zap")
                .font(.system(size: 34, weight: .light))
                .tracking(1.5)
                .padding(.leading, 1.5)
                .foregroundStyle(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.76)],
                                                startPoint: .top, endPoint: .bottom))
                .padding(.top, 18)
                .accessibilityLabel("to.zap")
                .accessibilityAddTraits(.isHeader)
            Text("Version \(version)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(DS.Palette.textTertiary)
                .textSelection(.enabled)
                .help(build.map { "Build \($0)" } ?? "")
                .padding(.top, 6)
        }
    }
}

/// The product signature: small and quiet, "Open Source" as a plain descriptor rather than a badge.
private struct AboutSignature: View {
    var body: some View {
        VStack(spacing: 3) {
            Text("A product of Cosmos")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
            Text("Open Source")
                .font(.system(size: 11))
                .tracking(0.5)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AboutActions: View {
    let navigation: SettingsNavigation

    var body: some View {
        SettingsGroup {
            AboutActionRow(symbol: "chevron.left.forwardslash.chevron.right", title: "GitHub Repository",
                           accessory: .symbol("arrow.up.right"),
                           hint: "Opens to.zap's source code on GitHub in your browser.") {
                NSWorkspace.shared.open(ZAPProject.repository)
            }
            SettingsDivider().padding(.leading, 46)
            AboutActionRow(symbol: "arrow.triangle.2.circlepath", title: "Check for Updates",
                           accessory: updateAccessory,
                           hint: RemoteModel.offlinePreview
                               ? "Unavailable in the offline preview."
                               : "Asks GitHub once for to.zap's latest release. Nothing is downloaded or installed.") {
                navigation.checkForUpdates()
            }
            .disabled(navigation.checkingForUpdates || RemoteModel.offlinePreview)
            .accessibilityValue(navigation.checkingForUpdates ? "Checking" : "")
        }
    }

    private var updateAccessory: AboutActionRow.Accessory? {
        if navigation.checkingForUpdates { return .progress }
        switch navigation.updateResult {
        case .upToDate: return .text("Up to date")
        case .updateAvailable(_, let latest, _): return .text("Version \(latest) available")
        default: return nil
        }
    }
}

private struct AboutActionRow: View {
    enum Accessory {
        case symbol(String)
        case text(String)
        case progress
    }

    let symbol: String
    let title: String
    let accessory: Accessory?
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: 20)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 8)
                switch accessory {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                case .text(let text):
                    Text(text).font(.system(size: 12)).foregroundStyle(DS.Palette.textTertiary)
                case .progress:
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                case nil:
                    EmptyView()
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(AboutRowButtonStyle())
        .help(hint)
        .accessibilityHint(hint)
    }
}

private struct AboutRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AboutRowButton(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct AboutRowButton<Label: View>: View {
    let label: Label
    let pressed: Bool
    @StateObject private var hover = HoverState()
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .background(Color.white.opacity(!isEnabled ? 0 : (pressed ? 0.09 : (hover.isHovering ? 0.045 : 0))))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .contentShape(.focusEffect, RoundedRectangle(cornerRadius: 7, style: .continuous).inset(by: 4))
            .onHover { hover.isHovering = $0 }
    }
}

/// The outcome of Check for Updates as a standard alert. Only a confirmed newer stable release offers a
/// download, and only from its GitHub release page; Homebrew installs are pointed at `brew upgrade`.
struct UpdateResultAlert: ViewModifier {
    let navigation: SettingsNavigation

    func body(content: Content) -> some View {
        let result = navigation.updateResult
        content.alert(result.map(UpdateMessage.title) ?? "",
                      isPresented: binding({ navigation.showingUpdateResult }, { navigation.showingUpdateResult = $0 }),
                      presenting: result) { result in
            switch result {
            case .updateAvailable(_, _, let page):
                if UpdateMessage.installation == .homebrew {
                    Button("Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ZAPProject.homebrewUpgradeCommand, forType: .string)
                    }
                }
                Button("View Release") { NSWorkspace.shared.open(page) }
                Button("Later", role: .cancel) {}
            case .networkUnavailable, .serverError:
                Button("Try Again") { navigation.checkForUpdates() }
                Button("OK", role: .cancel) {}
            case .invalidResponse:
                Button("Open Releases Page") { NSWorkspace.shared.open(ZAPProject.releasesPage) }
                Button("OK", role: .cancel) {}
            default:
                Button("OK", role: .cancel) {}
            }
        } message: { result in
            Text(UpdateMessage.message(result))
        }
    }
}

enum UpdateMessage {
    static var installation: InstallationSource { InstallationSource.detect(bundlePath: Bundle.main.bundlePath) }

    static func title(_ result: UpdateCheckResult) -> String {
        switch result {
        case .upToDate: return "to.zap is up to date."
        case .updateAvailable(_, let latest, _): return "to.zap \(latest) is available."
        case .noPublicRelease: return "There's no public release yet."
        case .rateLimited: return "to.zap can't check for updates right now."
        default: return "to.zap couldn't check for updates."
        }
    }

    static func message(_ result: UpdateCheckResult) -> String {
        switch result {
        case .upToDate(let installed):
            return "No newer version is available. You have to.zap \(installed)."
        case .updateAvailable(let installed, _, _):
            if installation == .homebrew {
                return "You have version \(installed). to.zap was installed with Homebrew, so update it in Terminal:\n\n\(ZAPProject.homebrewUpgradeCommand)"
            }
            return "You have version \(installed). Download the new version from its release page on GitHub."
        case .noPublicRelease:
            return "to.zap hasn't published a stable release on GitHub yet."
        case .networkUnavailable:
            return "GitHub couldn't be reached. Check your internet connection and try again."
        case .rateLimited(let retryAfter):
            guard let retryAfter, retryAfter > Date() else {
                return "GitHub is limiting requests from your network. Try again later."
            }
            return "GitHub is limiting requests from your network. Try again after \(retryAfter.formatted(date: .omitted, time: .shortened))."
        case .invalidResponse:
            return "to.zap couldn't read GitHub's response. You can check the releases page instead."
        case .serverError(let code):
            return "GitHub answered with an error (HTTP \(code)). Try again later."
        case .unknownInstalledVersion:
            return "This copy of to.zap has no readable version number."
        }
    }
}
