import Foundation

/// Keys accepted by `POST /v1/FireTV?action=<rawValue>`.
public enum NavKey: String, CaseIterable, Codable, Sendable {
    case up = "dpad_up", down = "dpad_down", left = "dpad_left", right = "dpad_right"
    case select, home, back, menu

    public var label: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .select: return "Select"
        case .home: return "Home"
        case .back: return "Back"
        case .menu: return "Menu"
        }
    }

    public var symbol: String {
        switch self {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .select: return "circle.fill"
        case .home: return "house"
        case .back: return "arrow.uturn.backward"
        case .menu: return "line.3.horizontal"
        }
    }
}

public enum MediaCommand: String, Codable, Sendable {
    case playPause, forward, rewind

    public var label: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .forward: return "Fast-forward"
        case .rewind: return "Rewind"
        }
    }

    public var symbol: String {
        switch self {
        case .playPause: return "playpause.fill"
        case .forward: return "forward.fill"
        case .rewind: return "backward.fill"
        }
    }
}

/// Everything the remote can send. Nothing outside these cases is ever sent to the device.
public enum RemoteAction: Codable, Sendable, Hashable {
    case key(NavKey)
    case media(MediaCommand)
    case launch(appId: String, name: String)

    public var summary: String {
        switch self {
        case .key(let k): return k.label
        case .media(let m): return m.label
        case .launch(_, let name): return "Open \(name)"
        }
    }
}

/// How far an action has been confirmed on the real device (AFTSSS, Fire OS 7.7.1.7, 2026-10-28).
public enum Verification: String, Sendable {
    /// Seen working on the TV.
    case verified
    /// Accepted by the device (HTTP 200) but the visible effect was not confirmed per command.
    case partial
}

extension RemoteAction {
    public var verification: Verification {
        switch self {
        case .key, .launch: return .verified
        case .media: return .partial
        }
    }
}

/// One entry of `GET /v1/FireTV/appsV2`.
public struct FireTVApp: Codable, Sendable, Identifiable, Hashable {
    /// A reverse-DNS package ID ("com.netflix.ninja"); anything else from the TV is ignored.
    public static func isValidAppID(_ id: String) -> Bool {
        id.count <= 255 && id.range(of: #"^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$"#, options: .regularExpression) != nil
    }

    public let appId: String
    public let name: String
    public let isInstalled: Bool?
    public let tvIconArt: String?
    public var id: String { appId }

    public init(appId: String, name: String, isInstalled: Bool? = true, tvIconArt: String? = nil) {
        self.appId = appId
        self.name = name
        self.isInstalled = isInstalled
        self.tvIconArt = tvIconArt
    }
}

public struct DeviceStatus: Codable, Sendable {
    public let osVersion: String?
    public let platformType: String?
    public let turnstileVersion: String?
}

/// Lower-cased, accent-free, punctuation-free text with single spaces: "Apri MaxPlayer!" -> "apri maxplayer".
public func normalizedText(_ s: String) -> String {
    let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                           locale: Locale(identifier: "it_IT"))
    let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
    return String(cleaned).split(separator: " ").joined(separator: " ")
}

extension Array where Element == FireTVApp {
    /// Installed apps whose name matches `query` (accent/case-insensitive). Never invents IDs:
    /// results always come from the device's own app list.
    public func matching(_ query: String) -> [FireTVApp] {
        let q = normalizedText(query).replacingOccurrences(of: " ", with: "")
        guard q.count >= 3 else { return [] }
        return filter { app in
            let name = normalizedText(app.name)
            let compact = name.replacingOccurrences(of: " ", with: "")
            let firstWord = name.split(separator: " ").first.map(String.init) ?? ""
            return compact.hasPrefix(q) || firstWord == q
        }
        .sorted { $0.name.count < $1.name.count }
    }

    public var maxPlayer: FireTVApp? { matching("maxplayer").first }

    /// AirPlay receiver apps present on the TV, preferred first.
    public var airPlayReceivers: [FireTVApp] {
        matching("airscreen") + matching("firemirror")
    }
}
