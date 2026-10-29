import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI
import ZAPKit
import os

/// App state. Every command goes through one ordered queue, so presses arrive in the order they were made.
@MainActor
@Observable
final class RemoteModel {
    static let shared = RemoteModel()

    /// Looking at the UI without touching anything: `open -n "build/ZAP Remote.app" --args -ZAPOfflinePreview YES`.
    /// No client is created; nothing is discovered, sent or downloaded; the microphone and the login item
    /// are left alone, and the pairing is read but never changed. (A launch argument, not a stored setting.)
    static let offlinePreview = AppDefaults.isOfflinePreview

    /// Developer check of the menu bar colours without a TV: `-ZAPMenuBarDemo YES`, only together with the
    /// offline preview. The icon cycles through every state, labelled as simulated; the app itself stays in
    /// its real "Offline preview" state and nothing is sent anywhere.
#if ZAP_DEVTOOLS
    static let menuBarDemo = offlinePreview && UserDefaults.standard.bool(forKey: "ZAPMenuBarDemo")
#else
    static let menuBarDemo = false
#endif

    enum Page { case remote, pairing, chooseApp }
    enum Source { case user, voice, automation }

    /// Short-lived messages shown in the status capsule, each one tied to something that really happened.
    enum CapsuleEvent: Equatable {
        case appOpened(name: String, appId: String)     // the TV accepted the launch
        case reconnected                                 // reachable again after an outage
        case receiverReady(String)                       // an AirPlay receiver is visible from this Mac
        case voice(String, failed: Bool)                 // what the recognizer heard / did
        case notice(String, warning: Bool)
    }

    /// What the capsule shows right now, highest priority first: the microphone recording, voice being
    /// prepared or recognised, AirPlay being set up, a transient event, active mirroring, verified Now Playing
    /// metadata, then the device and its connection.
    enum CapsuleContent: Equatable {
        case listening(alexa: Bool)
        case voiceBusy(String)
        case mirroringSetup(String)
        case event(CapsuleEvent)
        case mirroring
        case nowPlaying(NowPlayingPresentation)
        /// `link` applies the freshness rule: an old confirmation is no longer shown as connected.
        case device(name: String, link: MenuBarStatus.Link, connection: Connection)
    }

    /// What the header shows (`ConnectionState`, ZAPKit). The app never polls: it checks when the panel opens
    /// (Settings → Advanced) and after a failure.
    typealias Connection = ConnectionState

    var page: Page = .remote
    private(set) var device: PairedDevice?
    private(set) var connection: Connection = .pairingRequired
    private(set) var capsuleEvent: CapsuleEvent?
    private(set) var apps: [FireTVApp] = []
    /// Shortcut being replaced in the app chooser (nil = adding one). Kept by ID, so reordering shortcuts
    /// in Settings meanwhile can't redirect the replacement to another shortcut.
    private(set) var choosingForID: String?
    private(set) var chooserMessage: String?
    private(set) var appsFromTV = false
    private(set) var pressedKeys: Set<NavKey> = []
    var showApps = false

    // Onboarding / pairing
    private(set) var discovered: [DiscoveredTV] = []
    private(set) var discovering = false
    var selectedTVID: String?
    var manualHost = ""
    var pairingPIN = ""
    private(set) var awaitingPIN = false
    private(set) var pairingBusy = false
    /// Shown inside the pairing view itself (panel or Settings sheet), not only in the capsule.
    private(set) var pairingMessage: PairingMessage?
    /// Bumped when a pairing flow starts or ends, so a window can tell whether the flow it opened is still on.
    private(set) var pairingSession = 0

    struct PairingMessage: Equatable {
        let text: String
        let isError: Bool
    }

    var globalShortcutEnabled: Bool {
        didSet {
            AppDefaults.store.set(globalShortcutEnabled, forKey: "globalPushToTalk")
            updateHotKey()
        }
    }

    let voice = VoiceController()
    let mirroring = MirroringCoordinator()
    let quickActions = QuickActionsStore()

    var title: String { device?.displayName ?? "ZAP" }
    var isPaired: Bool { device != nil }

    /// The latest playback report and its provenance. No source fills it yet: retrieving metadata from the
    /// Fire TV is pending live verification (see `NowPlayingPolicy`), so the capsule never shows a title.
    private(set) var nowPlaying: NowPlayingInfo?
    /// Brief menu bar feedback after the TV accepted a command.
    private(set) var commandPulse = false
    /// When the TV last confirmed the connection (a check or an accepted command).
    private(set) var verifiedAt: Date?
    /// Bumped when a confirmation gets older than `MenuBarStatus.freshness`, so the icon stops showing green.
    private(set) var freshnessTick = 0
    /// Step of the amber "reconnecting" animation (0 = still).
    private(set) var reconnectPhase = 0
#if ZAP_DEVTOOLS
    /// `menuBarDemo` clock: 12 ticks of 0.25 s per state.
    private(set) var demoTick = 0

    private static let demoSteps: [(title: String, link: MenuBarStatus.Link, listening: Bool, mirroring: Bool, command: Bool)] = [
        ("Connected", .connected, false, false, false),
        ("Command accepted", .connected, false, false, true),
        ("Unreachable", .unreachable, false, false, false),
        ("Reconnecting", .reconnecting, false, false, false),
        ("Not checked", .unknown, false, false, false),
        ("Offline preview", .preview, false, false, false),
        ("Microphone on", .connected, true, false, false),
        ("Screen shared to the TV", .connected, false, true, false),
    ]
    private var demoStep: Int { (demoTick / 12) % Self.demoSteps.count }
#endif

    /// Entry point for a verified metadata source (none exists yet). Reports expire after
    /// `NowPlayingPolicy.maxAge`, so a title never outlives what the TV reported.
    func updateNowPlaying(_ info: NowPlayingInfo?) {
        nowPlaying = info
        nowPlayingExpiry?.cancel()
        guard let info else { return }
        nowPlayingExpiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(NowPlayingPolicy.maxAge * 1_000_000_000))
            if !Task.isCancelled, self?.nowPlaying == info { self?.nowPlaying = nil }
        }
    }

    var nowPlayingPresentation: NowPlayingPresentation? {
        NowPlayingPolicy.presentation(for: nowPlaying, enabled: AppPreferences.shared.showNowPlaying)
    }

    var capsuleContent: CapsuleContent {
        if voice.isCapturing { return .listening(alexa: voice.mode == .alexa) }
        if let busy = voice.busyDescription { return .voiceBusy(busy) }
        if case .searching(let message) = mirroring.stage { return .mirroringSetup(message) }
        if let capsuleEvent { return .event(capsuleEvent) }
        if mirroring.mirroredDisplay != nil { return .mirroring }
        let status = menuBarStatus
        if status.link == .connected, let playing = nowPlayingPresentation { return .nowPlaying(playing) }
        return .device(name: device?.displayName ?? "Not paired", link: status.link, connection: connection)
    }

    /// The connection as Settings shows it: "Connected" only while the confirmation is recent.
    var connectionLabel: String {
        connection == .connected && menuBarStatus.link != .connected ? "Not checked recently" : connection.label
    }

    /// What the menu bar icon reports, from real state only (see `MenuBarStatus`).
    var menuBarStatus: MenuBarStatus {
        _ = freshnessTick  // re-evaluated when a confirmation gets old
        return MenuBarStatus.resolve(deviceName: device?.displayName, connection: connection, verifiedAt: verifiedAt,
                                     listening: voice.isCapturing, mirroringDisplay: mirroring.mirroredDisplay,
                                     offlinePreview: Self.offlinePreview)
    }

    /// Tooltip and VoiceOver text for the menu bar icon.
    var menuBarDescription: String {
#if ZAP_DEVTOOLS
        if Self.menuBarDemo {
            return "Menu bar demo: \(Self.demoSteps[demoStep].title) (simulated — nothing is sent to the TV)"
        }
#endif
        return menuBarStatus.description
    }

    /// The menu bar glyph for `menuBarStatus`, plus the brief command pulse and the reconnecting animation.
    var menuBarState: MenuBarIcon.State {
#if ZAP_DEVTOOLS
        if Self.menuBarDemo {
            let step = Self.demoSteps[demoStep]
            let tick = demoTick % 12
            let blink = step.link == .reconnecting && !AccessibilityPrefs.shared.motionReduced
            return MenuBarIcon.State(link: step.link, listening: step.listening, command: step.command && tick % 4 == 0,
                                     mirroring: step.mirroring, phase: blink ? tick % 4 : 0)
        }
#endif
        let status = menuBarStatus
        return MenuBarIcon.State(link: status.link, listening: status.listening, command: commandPulse,
                                 mirroring: status.mirroringDisplay != nil,
                                 phase: status.link == .reconnecting ? reconnectPhase : 0)
    }

    /// A shortcut whose app isn't on this TV (only decided once the TV's own list has been read).
    func isMissing(_ item: QuickAction) -> Bool {
        guard appsFromTV || !apps.isEmpty else { return false }
        return quickActions.app(for: item, in: apps) == nil
    }

    @ObservationIgnored private(set) var client: FireTVClient?
    @ObservationIgnored private var queue: AsyncStream<Queued>.Continuation?
    @ObservationIgnored private var holdTimers: [NavKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var holding: Set<NavKey> = []
    @ObservationIgnored private var pointerReleasedAt: [NavKey: Date] = [:]
    @ObservationIgnored private var pairingClient: FireTVClient?
    @ObservationIgnored private var pairingTV: DiscoveredTV?
    /// Set when rediscovery moved the device to a new address: the next authenticated call must
    /// return the stored serial before anything else is sent.
    @ObservationIgnored private var identityPending = false
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var pulseTask: Task<Void, Never>?
    @ObservationIgnored private var freshnessTask: Task<Void, Never>?
    @ObservationIgnored private var identityLookupTried = false
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var nowPlayingExpiry: Task<Void, Never>?
    /// Set while the TV was unreachable, so its return can be confirmed once ("Reconnected").
    @ObservationIgnored private var hadOutage = false
    @ObservationIgnored private var lastCheck = Date.distantPast
    @ObservationIgnored private var panelOpen = false
    @ObservationIgnored private let hotKey = PushToTalkHotKey()
    @ObservationIgnored private(set) var automationEnabled = false
    @ObservationIgnored private let log = Logger(subsystem: "local.fireremote.app", category: "app")

    private enum Op {
        case action(RemoteAction)
        case keyDown(NavKey)
        case keyUp(NavKey)
    }
    private struct Queued {
        let op: Op
        let at: Date
    }

    private init() {
        globalShortcutEnabled = AppDefaults.store.bool(forKey: "globalPushToTalk")
    }

    func start() {
        // ZAP's windows are dark on their own (Settings window, remote panel), so the menu bar icon still
        // follows the real menu bar appearance.
        // Hidden developer switch: `defaults write local.fireremote.app automationURLs -bool true`
#if ZAP_DEVTOOLS
        automationEnabled = UserDefaults.standard.bool(forKey: "automationURLs") && !Self.offlinePreview
#endif
        let (stream, continuation) = AsyncStream.makeStream(of: Queued.self)
        queue = continuation
        Task { for await item in stream { await self.execute(item) } }

        if !Self.offlinePreview { PairingStore.migrateLegacyStoreIfNeeded() }
        apps = PairingStore.loadApps()
        if !Self.offlinePreview { quickActions.resolve(with: apps) }
        AppIconStore.shared.prefetch(apps)
        if let saved = PairingStore.load() {
            adopt(saved)
            connection = Self.offlinePreview ? .preview : .notChecked
        } else {
            page = .pairing
        }
        voice.model = self
        mirroring.startObservingDisplays()
        // After sleep a confirmation may have expired: re-evaluate the green light at once.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated { RemoteModel.shared.freshnessTick += 1 }
        }
        updateHotKey()
        installKeyMonitor()
#if ZAP_DEVTOOLS
        if Self.menuBarDemo { runMenuBarDemo() }
#endif
    }

#if ZAP_DEVTOOLS
    /// See `menuBarDemo`. Logs each state and, with `-ZAPMenuBarDemoCapture <folder>`, saves a picture of ZAP's
    /// own status item for each one (no permission needed for an app's own windows).
    private func runMenuBarDemo() {
        let captureFolder = UserDefaults.standard.string(forKey: "ZAPMenuBarDemoCapture").map { URL(fileURLWithPath: $0) }
        Task { [weak self] in
            var captured = Set<Int>()
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                self.demoTick += 1
                let tick = self.demoTick % 12
                if tick == 0 {
                    self.log.notice("menu bar demo: \(Self.demoSteps[self.demoStep].title, privacy: .public) — \(MenuBarStatusText.debugSummary(expected: MenuBarIcon.image(self.menuBarState)), privacy: .public)")
                }
                if tick == 6, let captureFolder, captured.insert(self.demoStep).inserted {
                    let name = String(format: "%02d-%@.png", self.demoStep, Self.demoSteps[self.demoStep].title.replacingOccurrences(of: " ", with: "-"))
                    MenuBarStatusText.snapshot(to: captureFolder.appendingPathComponent(name))
                }
            }
        }
    }
#endif

    private func adopt(_ paired: PairedDevice) {
        device = paired
        client = Self.offlinePreview ? nil : FireTVClient(device: paired)
    }

    /// Opens the Settings window (a separate window, not part of the menu bar panel).
    func openSettings(_ section: SettingsSection? = nil) {
        SettingsWindowController.shared.show(section)
    }

    /// The menu bar icon pulses once when the TV accepted a command (Settings → General).
    private func pulseMenuBar() {
        guard AppPreferences.shared.animationFeedback else { return }
        commandPulse = true
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { self?.commandPulse = false }
        }
    }

    private func persist(_ updated: PairedDevice) {
        device = updated
        try? PairingStore.save(updated)
    }

    /// Shows a capsule event, then returns the capsule to the device name.
    func flash(_ event: CapsuleEvent, for seconds: Double = 2.6) {
        capsuleEvent = event
        announce(event.text)
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled, self?.capsuleEvent == event { self?.capsuleEvent = nil }
        }
    }

    private func say(_ text: String?, for seconds: Double = 4, warning: Bool = true) {
        if let text {
            flash(.notice(text, warning: warning), for: seconds)
        } else if case .notice? = capsuleEvent {
            capsuleEvent = nil
        }
    }

    /// Speaks short status changes for VoiceOver users (no effect otherwise).
    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    /// Connection state changes, confirming a return after an outage exactly once.
    private func setConnection(_ new: Connection) {
        switch new {
        case .searching, .reconnecting, .unavailable:
            if !hadOutage { announce(new == .unavailable ? "Fire TV unavailable" : "Reconnecting to the Fire TV") }
            hadOutage = true
        case .connected where hadOutage:
            hadOutage = false
            flash(.reconnected, for: 1.8)
        default:
            break
        }
        connection = new
        if new == .connected { markVerified() }
        updateReconnectAnimation()
    }

    /// Green in the menu bar only while this confirmation is recent; ZAP never polls to keep it green.
    private func markVerified() {
        verifiedAt = Date()
        freshnessTask?.cancel()
        freshnessTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MenuBarStatus.freshness + 0.5), clock: .continuous)
            if !Task.isCancelled { self?.freshnessTick += 1 }
        }
    }

    /// A gentle amber blink while reconnecting: four steps per second, at most 30 s, and none with Reduce
    /// Motion or "Animation feedback" off (the amber dot then stays still).
    private func updateReconnectAnimation() {
        let reconnecting = connection == .searching || connection == .reconnecting
        guard reconnecting, !AccessibilityPrefs.shared.motionReduced else {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectPhase = 0
            return
        }
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            for step in 1...120 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled,
                      self.connection == .searching || self.connection == .reconnecting,
                      !AccessibilityPrefs.shared.motionReduced else { break }
                self.reconnectPhase = step % 4
            }
            guard !Task.isCancelled else { return }  // a newer animation owns the state now
            self?.reconnectPhase = 0
            self?.reconnectTask = nil
        }
    }

    func voiceFinished(_ text: String, failed: Bool) {
        flash(.voice(text, failed: failed), for: 3.2)
    }

    // MARK: Connection

    /// Called when the panel opens and after network failures. Never wakes the TV: the reachability
    /// check is a read-only DIAL request.
    func refreshConnection(force: Bool = false) {
        guard let client else {
            connection = Self.offlinePreview && device != nil ? .preview : .pairingRequired
            return
        }
        guard checkTask == nil else { return }
        if !force, connection == .connected, Date().timeIntervalSince(lastCheck) < 20 { return }
        checkTask = Task {
            defer {
                checkTask = nil
                lastCheck = Date()
            }
            if connection != .connected || menuBarStatus.link != .connected { connection = .checking }
            let reachable = await client.isReachable()
            guard self.client === client else { return }  // forgotten or re-paired meanwhile
            if reachable {
                setConnection(.connected)
                if !identityLookupTried, device?.deviceID == nil || device?.deviceName == nil {
                    identityLookupTried = true
                    await learnIdentity()
                }
                return
            }
            await rediscover()
        }
    }

    /// Records the Bonjour ID and name of the paired TV (by matching its current address).
    private func learnIdentity() async {
        guard var current = device else { return }
        for tv in await Bonjour.discoverFireTVs(seconds: 2) where tv.deviceID != nil {
            if await Bonjour.resolveIPv4(tv) == current.host {
                current.deviceID = tv.deviceID
                if current.deviceName == nil { current.deviceName = tv.name }
                persist(current)
                return
            }
        }
    }

    /// The TV moved (DHCP, new network): find the device with the same Bonjour ID. The new address is
    /// only used over the pinned TLS chain with the stored token, and its serial must match.
    private func rediscover() async {
        guard var current = device else { return }
        guard let wanted = current.deviceID else {
            setConnection(.unavailable)
            say(Bonjour.localNetworkDenied ? Self.localNetworkHint : "Fire TV not found", for: 6)
            return
        }
        setConnection(.searching)
        let tvs = await Bonjour.discoverFireTVs(seconds: 3)
        guard let tv = tvs.first(where: { $0.deviceID == wanted }), let host = await Bonjour.resolveIPv4(tv) else {
            setConnection(.unavailable)
            say(Bonjour.localNetworkDenied ? Self.localNetworkHint : "Fire TV not found", for: 6)
            return
        }
        if host != current.host {
            log.notice("paired Fire TV found at a new address")
            current.host = host
            identityPending = true
            device = current  // saved to disk only after the TV proves the same serial (confirmIdentity)
            client = FireTVClient(device: current)
        }
        setConnection(await client?.isReachable() == true ? .connected : .unavailable)
    }

    private func confirmIdentity(using client: FireTVClient) async throws {
        let properties = try await client.properties()
        let serial = properties["dsn"]
        if let known = device?.serial, serial != known {
            // Fails closed: a missing serial is treated like a different one.
            throw FireTVError.unsupported("A different Fire TV answered at this address. Pair again to use it.")
        }
        if var current = device {
            var changed = identityPending  // a new address is saved only now
            if current.serial == nil, let serial {
                current.serial = serial
                changed = true
            }
            if let version = properties["osVersion"], !version.isEmpty, current.softwareVersion != version {
                current.softwareVersion = version
                changed = true
            }
            if changed { persist(current) }
        }
        identityPending = false
    }

    private(set) var deviceInfoLoading = false
    private(set) var deviceInfoMessage: String?

    /// Settings → Device → "Load from TV": one read-only authenticated properties call, only when the user
    /// asks. It doesn't start an idle remote service, so it can't switch the TV on.
    func refreshDeviceInfo() {
        guard let client, !deviceInfoLoading else { return }
        deviceInfoLoading = true
        deviceInfoMessage = nil
        Task {
            defer { deviceInfoLoading = false }
            do {
                let properties = try await client.properties(wakeIfNeeded: false)
                if let known = device?.serial, let serial = properties["dsn"], serial != known {
                    deviceInfoMessage = "A different Fire TV answered at this address."
                    return
                }
                if var current = device {
                    if let version = properties["osVersion"], !version.isEmpty { current.softwareVersion = version }
                    if current.serial == nil { current.serial = properties["dsn"] }
                    persist(current)
                }
                setConnection(.connected)
            } catch FireTVError.serviceUnavailable {
                deviceInfoMessage = "The TV's remote service is asleep. Use the remote once, then try again."
            } catch {
                deviceInfoMessage = error.localizedDescription
            }
        }
    }

    // MARK: Commands

    func send(_ action: RemoteAction, source: Source = .user) {
        guard client != nil else {
            say(Self.offlinePreview ? "Offline preview — nothing sent" : "Pair with a Fire TV first")
            return
        }
        queue?.yield(Queued(op: .action(action), at: Date()))
    }

    /// Press-and-hold: a short tap sends one press; holding past 350 ms sends keyDown, release sends keyUp.
    func keyPressBegan(_ key: NavKey) {
        guard client != nil, !pressedKeys.contains(key) else { return }
        pressedKeys.insert(key)
        holdTimers[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled, self.pressedKeys.contains(key) else { return }
            self.holding.insert(key)
            self.queue?.yield(Queued(op: .keyDown(key), at: Date()))
        }
    }

    /// A remote key's button action. A pointer press already sent the key through `keyPressBegan/Ended`;
    /// keyboard activation (Full Keyboard Access) has no press, so the key is sent here instead.
    func keyActivated(_ key: NavKey) {
        if pressedKeys.contains(key) { return }
        if let released = pointerReleasedAt[key], Date().timeIntervalSince(released) < 0.4 { return }
        send(.key(key))
    }

    func keyPressEnded(_ key: NavKey) {
        guard pressedKeys.remove(key) != nil else { return }
        pointerReleasedAt[key] = Date()
        holdTimers.removeValue(forKey: key)?.cancel()
        if holding.remove(key) != nil {
            queue?.yield(Queued(op: .keyUp(key), at: Date()))
        } else {
            send(.key(key))
        }
    }

    /// The panel closed: release anything still held so no key keeps repeating and the mic turns off.
    func releaseEverything() {
        for key in pressedKeys { keyPressEnded(key) }
        voice.pushToTalkEnded()
    }

    private func execute(_ item: Queued) async {
        guard let client else { return }
        let label: String
        switch item.op {
        case .action(let action): label = action.summary
        case .keyDown(let key): label = "Hold \(key.label)"
        case .keyUp(let key): label = "Release \(key.label)"
        }
        if case .keyUp = item.op {
            // always delivered, or the TV keeps repeating the key
        } else if Date().timeIntervalSince(item.at) > 4 {
            log.notice("dropped stale command \(label, privacy: .private)")
            return
        }
        let started = Date()
        do {
            if identityPending { try await confirmIdentity(using: client) }
            switch item.op {
            case .action(let action): try await client.perform(action)
            case .keyDown(let key): try await client.keyDown(key)
            case .keyUp(let key): try await client.keyUp(key)
            }
            setConnection(.connected)
            pulseMenuBar()
            if case .notice? = capsuleEvent { say(nil) }
            if case .action(.launch(let appId, let name)) = item.op, !silentLaunches.contains(appId) {
                flash(.appOpened(name: shortAppName(name), appId: appId))
            }
            log.notice("sent \(label, privacy: .private) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            if device?.serial == nil { try? await confirmIdentity(using: client) }
        } catch {
            handle(error, while: label)
        }
    }

    private func handle(_ error: Error, while label: String) {
        log.error("\(label, privacy: .private) failed: \(error.localizedDescription, privacy: .public)")
        switch error as? FireTVError {
        case .unauthorized?:
            connection = .pairingRequired
            say("Pairing expired — pair again", for: 8)
        case .untrustedCertificate?:
            setConnection(.unavailable)
            say("Untrusted device refused", for: 8)
        case .network?, .serviceUnavailable?:
            setConnection(.reconnecting)
            refreshConnection(force: true)
        default:
            say(error.localizedDescription)
        }
    }

    // MARK: Apps

    func refreshApps() async {
        guard let client else { return }
        do {
            apps = try await client.apps()
            appsFromTV = true
            PairingStore.saveApps(apps)
            quickActions.resolve(with: apps)
            AppIconStore.shared.prefetch(apps)
        } catch {
            handle(error, while: "Load apps")
        }
    }

    /// Opens a shortcut's app — or, when it isn't installed on this TV, the chooser to replace it.
    func openQuickAction(_ item: QuickAction) {
        if let app = quickActions.app(for: item, in: apps) {
            send(.launch(appId: app.appId, name: app.name))
            return
        }
        Task {
            if !appsFromTV { await refreshApps() }
            if let app = quickActions.app(for: item, in: apps) {
                send(.launch(appId: app.appId, name: app.name))
            } else if appsFromTV, let index = quickActions.index(matching: item.id) {
                beginChoosing(replacing: index, message: "\(item.name) isn't in this TV's app list. Choose another app.")
            }
        }
    }

    func beginChoosing(replacing index: Int?, message: String? = nil) {
        choosingForID = index.flatMap { quickActions.items.indices.contains($0) ? quickActions.items[$0].id : nil }
        chooserMessage = message
        page = .chooseApp
        if !appsFromTV { Task { await refreshApps() } }
    }

    func choose(_ app: FireTVApp) {
        if let id = choosingForID, let index = quickActions.index(matching: id) {
            quickActions.replace(at: index, with: app)
        } else {
            quickActions.add(app)
        }
        choosingForID = nil
        chooserMessage = nil
        page = .remote
    }

    func cancelChoosing() {
        choosingForID = nil
        chooserMessage = nil
        page = .remote
    }

    /// Receiver launches are part of the mirroring flow, which reports its own outcome.
    @ObservationIgnored private var silentLaunches: Set<String> = []

    /// Opens AirPlay Server on the TV (the receiver verified with ZAP) unless a receiver on the TV is already
    /// visible, then reports what the Mac can see. Other receiver apps are used only when already running.
    /// While a receiver was just found, the Mirror button opens Displays settings instead; `recheck` (Settings)
    /// always opens and checks the receiver again.
    func startMirroring(recheck: Bool = false) {
        guard !Self.offlinePreview else {
            say("Offline preview — nothing sent")
            return
        }
        if !recheck, case .guide = mirroring.stage {
            mirroring.openDisplaySettings()
            return
        }
        Task {
            let receivers = [MirroringCoordinator.freeReceiver]
            silentLaunches = Set(receivers.map(\.appId))
            await mirroring.begin(receivers: receivers, tvHost: device?.host) { [weak self] app in
                self?.send(.launch(appId: app.appId, name: app.name))
            }
            switch mirroring.stage {
            case .guide(let targets):
                flash(.receiverReady(targets.first ?? "AirPlay receiver"), for: 5)
            case .notFound:
                say("No AirPlay receiver", for: 5)
            default:
                break
            }
        }
    }

    // MARK: Pairing

    func discoverTVs() async {
        guard !Self.offlinePreview else { return }
        discovering = true
        defer { discovering = false }
        discovered = await Bonjour.discoverFireTVs(seconds: 3)
        if selectedTVID == nil || !discovered.contains(where: { $0.id == selectedTVID }) {
            selectedTVID = discovered.first?.id
        }
        if discovered.isEmpty, Bonjour.localNetworkDenied { pairingNotice(Self.localNetworkHint, error: true, for: 10) }
    }

    /// A pairing status for the pairing view, repeated in the capsule.
    private func pairingNotice(_ text: String, error: Bool, for seconds: Double = 6) {
        pairingMessage = PairingMessage(text: text, isError: error)
        say(text, for: seconds, warning: error)
    }

    static let localNetworkHint =
        "ZAP can't see your network: allow ZAP in System Settings → Privacy & Security → Local Network."

    func requestPIN() async {
        guard !Self.offlinePreview else {
            pairingNotice("Offline preview — nothing sent", error: true)
            return
        }
        pairingBusy = true
        defer { pairingBusy = false }
        let session = pairingSession
        let manual = manualHost.trimmingCharacters(in: .whitespaces)
        var host: String?
        pairingTV = nil
        if !manual.isEmpty {
            guard Self.isIPv4(manual) else {
                pairingNotice("Check the address: it should look like 192.168.1.20.", error: true)
                return
            }
            host = manual
        } else if let tv = discovered.first(where: { $0.id == selectedTVID }) {
            pairingTV = tv
            host = await Bonjour.resolveIPv4(tv)
            guard session == pairingSession else { return }
        }
        guard let host else {
            pairingNotice("Choose a Fire TV first, or enter its address.", error: true)
            return
        }
        let candidate = FireTVClient(host: host, token: nil, pinnedRoot: nil)
        pairingClient = candidate
        do {
            try await candidate.requestPIN(clientName: "ZAP for Mac")
            guard session == pairingSession else { return }  // cancelled while the TV answered
            awaitingPIN = true
            pairingNotice("Enter the PIN shown on the TV.", error: false, for: 30)
        } catch {
            guard session == pairingSession else { return }
            pairingNotice(Bonjour.localNetworkDenied ? Self.localNetworkHint : error.localizedDescription,
                          error: true, for: 8)
        }
    }

    func submitPIN() async {
        guard let candidate = pairingClient else { return }
        pairingBusy = true
        defer { pairingBusy = false }
        do {
            let (token, root) = try await candidate.verifyPIN(pairingPIN.filter(\.isNumber))
            var paired = PairedDevice(host: candidate.host, token: token, rootCertificate: root,
                                      deviceName: pairingTV?.name, deviceID: pairingTV?.deviceID,
                                      clientName: "ZAP for Mac", pairedAt: Date())
            let verified = FireTVClient(device: paired)
            let properties = (try? await verified.properties()) ?? [:]
            paired.serial = properties["dsn"]
            paired.softwareVersion = properties["osVersion"]
            // Pairing the same TV again keeps the name the user gave it.
            if let previous = device, previous.nickname != nil,
               (previous.deviceID != nil && previous.deviceID == paired.deviceID)
                || (previous.serial != nil && previous.serial == paired.serial) {
                paired.nickname = previous.nickname
            }
            persist(paired)
            client = verified
            identityPending = false
            awaitingPIN = false
            pairingPIN = ""
            pairingClient = nil
            page = .remote
            setConnection(.connected)
            pairingMessage = nil
            pairingSession += 1
            say("Paired with \(paired.displayName)", warning: false)
            await refreshApps()
            if paired.deviceID == nil { await learnIdentity() }
        } catch {
            pairingNotice(error.localizedDescription, error: true, for: 8)
        }
    }

    /// Settings → Device → "Pair Again…" (after confirmation). The current pairing stays until a new one succeeds.
    func beginPairing() {
        guard !Self.offlinePreview else { return }
        awaitingPIN = false
        pairingPIN = ""
        manualHost = ""
        pairingMessage = nil
        pairingSession += 1
        page = .pairing
    }

    /// Leaves the pairing flow without changing the stored pairing.
    func cancelPairing() {
        awaitingPIN = false
        pairingPIN = ""
        pairingClient = nil
        pairingMessage = nil
        pairingSession += 1
        if isPaired { page = .remote }
    }

    func forgetDevice() {
        guard !Self.offlinePreview else { return }
        checkTask?.cancel()
        checkTask = nil
        PairingStore.forget()
        AppIconStore.shared.clearCache()
        mirroring.forgetReceivers()
        device = nil
        client = nil
        apps = []
        appsFromTV = false
        connection = .pairingRequired
        page = .pairing
    }

    func setNickname(_ name: String) {
        guard !Self.offlinePreview, var current = device else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        current.nickname = trimmed.isEmpty ? nil : trimmed
        persist(current)
    }

    static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            (1...3).contains(part.count) && part.allSatisfy { ("0"..."9").contains($0) }
                && (part == "0" || part.first != "0") && UInt8(part) != nil
        }
    }

    // MARK: Panel & keyboard

    func panelVisible(_ visible: Bool) {
        panelOpen = visible
        if visible {
            if AppPreferences.shared.checkConnectionOnOpen { refreshConnection() }
        } else {
            releaseEverything()
        }
    }

    /// App-local key monitor: only sees keys typed into ZAP's own panel and needs no permission.
    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            MainActor.assumeIsolated { RemoteModel.shared.handleKeyEvent(event) } ? nil : event
        }
    }

    /// Arrows = D-pad (hold repeats), Return = OK, Esc/Delete = Back, Space = Play/Pause,
    /// H = Home, M = Menu, hold V = push-to-talk. Returns true when the event was consumed.
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Only keys typed into the open panel: never keystrokes without a window or meant for another app.
        guard panelOpen, let window = event.window, window.isKeyWindow, window.isVisible,
              !String(describing: type(of: window)).contains("StatusBar") else { return false }
        if event.type == .keyDown, event.modifierFlags.contains(.command), Int(event.keyCode) == kVK_ANSI_Comma {
            openSettings()
            return true
        }
        if page != .remote {
            guard event.type == .keyDown, Int(event.keyCode) == kVK_Escape,
                  !(NSApp.keyWindow?.firstResponder is NSTextView) else { return false }
            if page == .chooseApp { cancelChoosing() } else { cancelPairing() }
            return true
        }
        guard client != nil,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              !(NSApp.keyWindow?.firstResponder is NSTextView) else { return false }
        let down = event.type == .keyDown
        let arrows: [Int: NavKey] = [kVK_UpArrow: .up, kVK_DownArrow: .down,
                                     kVK_LeftArrow: .left, kVK_RightArrow: .right]
        if let key = arrows[Int(event.keyCode)] {
            if event.isARepeat { return true }  // the TV repeats while held
            if down { keyPressBegan(key) } else { keyPressEnded(key) }
            return true
        }
        if Int(event.keyCode) == kVK_ANSI_V {
            if !event.isARepeat {
                if down { voice.pushToTalkBegan() } else { voice.pushToTalkEnded() }
            }
            return true
        }
        guard down else { return false }
        if event.isARepeat { return true }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4]
        if let slot = digits.firstIndex(of: Int(event.keyCode)) {
            let shown = quickActions.visibleItems
            if shown.indices.contains(slot) { openQuickAction(shown[slot]) }
            return true
        }
        // With Full Keyboard Access, Space and Return activate the focused control instead.
        if NSApp.isFullKeyboardAccessEnabled, [kVK_Space, kVK_Return].contains(Int(event.keyCode)) { return false }
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: send(.key(.select))
        case kVK_Escape, kVK_Delete: send(.key(.back))
        case kVK_Space: send(.media(.playPause))
        case kVK_ANSI_LeftBracket: send(.media(.rewind))
        case kVK_ANSI_RightBracket: send(.media(.forward))
        case kVK_ANSI_H: send(.key(.home))
        case kVK_ANSI_M: send(.key(.menu))
        default: return false
        }
        return true
    }

    private func updateHotKey() {
        if globalShortcutEnabled, !Self.offlinePreview {
            hotKeyUnavailable = !hotKey.register(onPress: { RemoteModel.shared.voice.pushToTalkBegan() },
                                                 onRelease: { RemoteModel.shared.voice.pushToTalkEnded() })
        } else {
            hotKey.unregister()
            hotKeyUnavailable = false
        }
    }

    /// True when "Push-to-talk anywhere" is on but macOS refused the shortcut (another app uses it).
    private(set) var hotKeyUnavailable = false

#if ZAP_DEVTOOLS
    // MARK: Developer automation (hidden, off by default)

    /// `zapremote://key/<name>`, `media/<playPause|forward|rewind>`, `launch/<appId from the TV's list>`,
    /// `maxplayer`, `mirroring`, `ptt?seconds=3`, `voice-test?file=…&dry=1`, `ui?page=…&apps=1&nickname=…`,
    /// `snapshot?path=…`. Enabled only with `defaults write local.fireremote.app automationURLs -bool true`.
    func handleURL(_ url: URL) {
        guard url.scheme == "zapremote" else { return }
        guard automationEnabled else {
            log.notice("ignored \(url.absoluteString, privacy: .public): automation is off")
            return
        }
        log.notice("automation \(url.absoluteString, privacy: .public)")
        let parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
        let argument = parts.count > 1 ? parts[1] : ""
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []).map { ($0.name, $0.value ?? "") })
        switch parts[0] {
        case "key":
            if let key = NavKey.allCases.first(where: { $0.label.lowercased() == argument.lowercased() }) {
                send(.key(key), source: .automation)
            }
        case "media":
            if let command = MediaCommand(rawValue: argument) { send(.media(command), source: .automation) }
        case "launch":
            if let app = apps.first(where: { $0.appId == argument }) {
                send(.launch(appId: app.appId, name: app.name), source: .automation)
            }
        case "maxplayer":
            if let app = apps.maxPlayer { send(.launch(appId: app.appId, name: app.name), source: .automation) }
        case "mirroring":
            startMirroring()
        case "ptt":
            let seconds = min(max(Double(query["seconds"] ?? "") ?? 3, 1), 10)
            voice.pushToTalkBegan()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                voice.pushToTalkEnded()
            }
        case "voice-test":
            if let path = query["file"] {
                voice.recognizeFile(URL(fileURLWithPath: path), execute: query["dry"] != "1")
            }
        case "ui":
            switch query["page"] {
            case "settings": openSettings(query["section"].flatMap(SettingsSection.init(rawValue:)))
            case "remote": page = .remote
            case "choose": beginChoosing(replacing: nil)
            default: break
            }
            // Layout QA only (synthetic, never used for published screenshots).
            switch query["qa-capsule"] {
            case "reconnecting": connection = .reconnecting
            case "unavailable": connection = .unavailable
            case "connected": connection = .connected
            case "opened": flash(.appOpened(name: "Netflix", appId: "com.netflix.ninja"), for: 30)
            case "ready": flash(.receiverReady("Android AirPlay"), for: 30)
            case "long": flash(.notice("No AirPlay receiver was found on the television in the living room", warning: true), for: 30)
            default: break
            }
            if let flag = query["apps"] {
                showApps = flag == "1"
                if showApps, apps.isEmpty { Task { await refreshApps() } }
            }
            if let name = query["nickname"] { setNickname(name) }
            if let mode = query["voice"].flatMap(VoiceController.Mode.init(rawValue:)) { voice.mode = mode }
            // QA only: pretend the TV moved to another address, to exercise rediscovery end to end.
            if let host = query["qa-host"], Self.isIPv4(host), var current = device {
                current.host = host
                persist(current)
                client = FireTVClient(device: current)
                refreshConnection(force: true)
            }
            if let flag = query["preview"] { PanelCapture.showPreview(flag == "1") }
        case "snapshot":
            if let path = query["path"] { Task { await PanelCapture.capture(to: URL(fileURLWithPath: path)) } }
        default:
            break
        }
    }
#endif
}

extension RemoteModel.CapsuleEvent {
    /// The short text shown in the capsule and spoken to VoiceOver.
    var text: String {
        switch self {
        case .appOpened(let name, _): return "\(name) opened"
        case .reconnected: return "Reconnected"
        case .receiverReady(let name): return "\(name) ready"
        case .voice(let text, _): return text
        case .notice(let text, _): return text
        }
    }
}
