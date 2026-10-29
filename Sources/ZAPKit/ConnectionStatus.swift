import Foundation

/// The TV connection as ZAP last established it. ZAP never polls: it checks when the remote opens (Settings →
/// Advanced) and after a failure, and every command the TV accepts confirms the connection again.
public enum ConnectionState: Equatable, Sendable {
    case pairingRequired, checking, connected, searching, reconnecting, unavailable
    /// Automatic checks are off and nothing has been sent yet.
    case notChecked
    /// Offline preview: no connection is ever attempted.
    case preview

    public var label: String {
        switch self {
        case .pairingRequired: return "Pairing required"
        case .checking: return "Checking…"
        case .connected: return "Connected"
        case .searching: return "Searching…"
        case .reconnecting: return "Reconnecting…"
        case .unavailable: return "Fire TV unavailable"
        case .notChecked: return "Not checked"
        case .preview: return "Offline preview"
        }
    }
}

/// What the menu bar icon says about the TV, derived only from real app state. Green needs a recent
/// confirmation; anything unconfirmed is gray, never green.
public struct MenuBarStatus: Equatable, Sendable {
    public enum Link: String, Sendable {
        /// Confirmed within `freshness`.
        case connected
        /// Confirmed failure: unreachable after a check, untrusted, or the TV rejected the pairing.
        case unreachable
        /// Looking for the TV again after a failure.
        case reconnecting
        /// Not paired, not checked yet, or not confirmed recently.
        case unknown
        /// Offline preview.
        case preview
    }

    public let link: Link
    public let listening: Bool
    /// The display macOS is mirroring or extending to, when it belongs to a known AirPlay receiver.
    public let mirroringDisplay: String?
    /// For the tooltip and VoiceOver, e.g. "Living Room: Connected (checked at 21:04)".
    public let description: String

    /// ZAP doesn't poll, so after this long a confirmation no longer proves the TV is still there.
    public static let freshness: TimeInterval = 10 * 60

    public static func resolve(deviceName: String?, connection: ConnectionState, verifiedAt: Date?, now: Date = Date(),
                               listening: Bool, mirroringDisplay: String?, offlinePreview: Bool) -> MenuBarStatus {
        let link: Link
        let state: String
        if offlinePreview {
            link = .preview
            state = "Offline preview — nothing is sent to the TV"
        } else if deviceName == nil {
            link = .unknown
            state = "Not paired — open the remote to pair a Fire TV"
        } else {
            switch connection {
            case .connected:
                if let verifiedAt, verifiedAt <= now.addingTimeInterval(1), now.timeIntervalSince(verifiedAt) <= freshness {
                    link = .connected
                    state = "Connected (checked at \(verifiedAt.formatted(date: .omitted, time: .shortened)))"
                } else {
                    link = .unknown
                    state = "Not checked recently — open the remote to check"
                }
            case .searching:
                link = .reconnecting
                state = "Looking for the TV on the network…"
            case .reconnecting:
                link = .reconnecting
                state = "Reconnecting…"
            case .unavailable:
                link = .unreachable
                state = "Unreachable — open the remote to try again"
            case .pairingRequired:
                link = .unreachable
                state = "Pairing expired — pair again in Settings → Device"
            case .checking:
                link = .unknown
                state = "Checking the connection…"
            case .notChecked:
                link = .unknown
                state = "Not checked yet — open the remote to check"
            case .preview:
                link = .preview
                state = "Offline preview — nothing is sent to the TV"
            }
        }
        var parts = ["\(deviceName ?? "ZAP"): \(state)"]
        if listening { parts.append("Microphone on") }
        if let mirroringDisplay { parts.append("Screen shared to \(mirroringDisplay)") }
        return MenuBarStatus(link: link, listening: listening, mirroringDisplay: mirroringDisplay,
                             description: parts.joined(separator: " · "))
    }
}

/// Which AirPlay receivers Mirroring presents. With a paired TV only receivers at the TV's own address count,
/// so another AirPlay device (an Apple TV, a speaker) is never shown as the TV's receiver; without one, any
/// receiver the Mac can see.
public enum AirPlayReceiverChoice {
    public static func shown(_ receivers: [(name: String, onTV: Bool)], tvPaired: Bool) -> [String] {
        (tvPaired ? receivers.filter(\.onTV) : receivers).map(\.name)
    }
}

/// Matching a connected display to an AirPlay receiver ZAP has seen: macOS names an AirPlay display after the
/// receiver it streams to.
public enum AirPlayDisplay {
    public static func matches(screenName: String, receiver: String) -> Bool {
        let receiver = receiver.trimmingCharacters(in: .whitespaces)
        guard receiver.count >= 4 else { return false }
        return screenName.range(of: receiver, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
