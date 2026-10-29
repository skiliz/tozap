import AppKit
import ZAPKit
import Observation
import os

/// Screen Mirroring helper. macOS has no public API to start AirPlay mirroring or pick mirror vs extend,
/// so this makes sure an AirPlay receiver is running on the Fire TV (verified app-launch endpoint), checks
/// that the Mac can see it, and guides the user to Control Center → Screen Mirroring. It never claims a
/// one-click connection.
@MainActor
@Observable
final class MirroringCoordinator {
    enum Stage: Equatable {
        case idle
        case searching(String)
        /// AirPlay receivers the Mac can see (excluding the Mac's own receiver).
        case guide([String])
        case notFound
    }

    /// Free, open-source receiver (F-Droid / GitHub jqssun/android-airplay-server, v0.0.36). Verified on this
    /// AFTSSS on 2026-10-29: sideloaded, it isn't in the TV's app list, but the launch endpoint opens it, it
    /// advertises "Android AirPlay", and macOS mirrored and extended to it.
    static let freeReceiver = FireTVApp(appId: "io.github.jqssun.airplay", name: "AirPlay Server")

    private(set) var stage: Stage = .idle

    /// The connected display that belongs to an AirPlay receiver ZAP has seen: macOS is mirroring or extending
    /// to the TV right now. Read from the system's display list when it changes — nothing is polled. (In
    /// mirror mode macOS may not list the AirPlay display separately; then this stays nil, never a guess.)
    private(set) var mirroredDisplay: String?

    /// Names of AirPlay receivers found by ZAP (e.g. "Android AirPlay"), remembered between launches.
    @ObservationIgnored private var receiverNames: Set<String> =
        Set(AppDefaults.store.stringArray(forKey: "airPlayReceiverNames") ?? [])
    @ObservationIgnored private var displayObserver: NSObjectProtocol?

    func startObservingDisplays() {
        guard displayObserver == nil else { return }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMirroredDisplay() }
        }
        refreshMirroredDisplay()
    }

    private func refreshMirroredDisplay() {
        let screens = NSScreen.screens.map(\.localizedName)
        let match = screens.first { screen in receiverNames.contains { AirPlayDisplay.matches(screenName: screen, receiver: $0) } }
        if match != mirroredDisplay { mirroredDisplay = match }
    }

    /// `receivers` in order of preference; the first is launched unless the TV's own receiver is already
    /// visible. `tvHost` (the paired TV's address) tells the TV's receiver from others on the network.
    func begin(receivers: [FireTVApp], tvHost: String?, launch: (FireTVApp) -> Void) async {
        expiry?.cancel()
        stage = .searching("Looking for an AirPlay receiver…")
        var found = await visibleReceivers(seconds: 2, tvHost: tvHost)
        let needsLaunch = tvHost == nil ? found.isEmpty : !found.contains(where: \.onTV)
        if needsLaunch, let receiver = receivers.first {
            launch(receiver)
            stage = .searching("Opening \(receiver.name) on the TV…")
            found = await visibleReceivers(seconds: 10, tvHost: tvHost)
        }
        let onTV = found.filter(\.onTV)
        let shown = onTV.isEmpty ? found : onTV
        stage = shown.isEmpty ? .notFound : .guide(shown.map(\.name))
        log.notice("mirroring: \(String(describing: self.stage), privacy: .private)")
        // Only the paired TV's own receiver is remembered (for the menu bar's mirroring light) — never the
        // names of other devices on the network.
        if !onTV.isEmpty {
            receiverNames.formUnion(onTV.map(\.name))
            AppDefaults.store.set(Array(receiverNames).sorted(), forKey: "airPlayReceiverNames")
            refreshMirroredDisplay()
        }
        // A result is only current for a couple of minutes; after that the receiver is checked again.
        let settled = stage
        expiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            if !Task.isCancelled, self?.stage == settled { self?.stage = .idle }
        }
    }

    @ObservationIgnored private var expiry: Task<Void, Never>?

    @ObservationIgnored private let log = Logger(subsystem: "local.fireremote.app", category: "mirroring")

    func close() { stage = .idle }

    /// Opens System Settings → Displays, whose "+" menu lists AirPlay displays to mirror or extend to.
    /// (The pane identifier is undocumented; it only opens the page and controls nothing.)
    func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// Forget This TV: its receiver is forgotten too.
    func forgetReceivers() {
        receiverNames = []
        AppDefaults.store.removeObject(forKey: "airPlayReceiverNames")
        refreshMirroredDisplay()
    }

    private struct Receiver {
        let name: String
        let onTV: Bool
    }

    /// AirPlay receivers the Mac can see, except its own; each is checked against the TV's address.
    private func visibleReceivers(seconds: Double, tvHost: String?) async -> [Receiver] {
        let own = Host.current().localizedName ?? ""
        let services = await Bonjour.browse(Bonjour.airPlayType, seconds: seconds)
            .filter { own.isEmpty || !$0.name.hasPrefix(own) }
        guard let tvHost else { return services.map { Receiver(name: $0.name, onTV: false) } }
        return await withTaskGroup(of: Receiver.self) { group in
            for service in services {
                group.addTask { Receiver(name: service.name, onTV: await Bonjour.resolveIPv4(service, timeout: 2) == tvHost) }
            }
            var result: [Receiver] = []
            for await receiver in group { result.append(receiver) }
            return result.sorted { $0.name < $1.name }
        }
    }
}
