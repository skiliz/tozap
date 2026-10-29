import Foundation

// "Now Playing" for the status capsule. Nothing here talks to the TV: these types describe what a source
// reported and decide whether it may be shown. Until a source has been verified on a real device, nothing is.

/// Playback state exactly as a source reported it. Never inferred from button presses.
public enum PlaybackState: String, Sendable, Codable {
    case playing, paused, unknown
}

/// Where a piece of playback information came from.
public enum MetadataSource: String, Sendable, Codable, CaseIterable {
    /// The Fire TV app's REST protocol (:8080). No endpoint reporting the foreground app or the playing
    /// title has been observed (status, properties and keyboard return none); pending live verification.
    case fireTVProtocol
    /// DIAL application status (:8009, `GET /apps/<name>`): at most "running"/"stopped" for apps that
    /// register with DIAL, never a title. Pending live verification.
    case dialApplicationStatus
}

/// One report from a source, kept with its provenance and the time it was observed.
public struct NowPlayingInfo: Equatable, Sendable {
    public var appID: String?
    public var appName: String?
    public var title: String?
    /// Episode, artist, album… when the source provides it.
    public var detail: String?
    public var playback: PlaybackState
    public var source: MetadataSource
    public var observedAt: Date

    public init(appID: String? = nil, appName: String? = nil, title: String? = nil, detail: String? = nil,
                playback: PlaybackState = .unknown, source: MetadataSource, observedAt: Date) {
        self.appID = appID
        self.appName = appName
        self.title = title
        self.detail = detail
        self.playback = playback
        self.source = source
        self.observedAt = observedAt
    }
}

/// What the capsule may display: only text that a verified source actually reported.
public struct NowPlayingPresentation: Equatable, Sendable {
    public let title: String
    public let detail: String?
    public let appName: String?
    public let appID: String?
    public let playback: PlaybackState
    public let source: MetadataSource
}

public enum NowPlayingPolicy {
    /// Sources whose metadata has been confirmed against a real Fire TV. Empty in this build: no source has
    /// been verified yet (see docs/PROTOCOL.md, "Now Playing"). A source is added here only after an
    /// owner-approved live test.
    public static let verifiedSources: Set<MetadataSource> = []

    /// Older reports are dropped: the TV may have moved on (the physical remote, a timeout…).
    public static let maxAge: TimeInterval = 30

    /// True when at least one verified source exists, i.e. the "Show Now Playing" setting can do something.
    public static var isAvailable: Bool { !verifiedSources.isEmpty }

    /// Returns something to show only when the setting is on, the source is verified, the report is fresh and
    /// it carries a non-empty title. Everything else — including every report today — shows nothing.
    public static func presentation(for info: NowPlayingInfo?, enabled: Bool, now: Date = Date(),
                                    verified: Set<MetadataSource> = verifiedSources) -> NowPlayingPresentation? {
        guard enabled, let info, verified.contains(info.source) else { return nil }
        let age = now.timeIntervalSince(info.observedAt)
        guard age >= -1, age <= maxAge else { return nil }
        guard let title = cleaned(info.title) else { return nil }
        return NowPlayingPresentation(title: title, detail: cleaned(info.detail), appName: cleaned(info.appName),
                                      appID: info.appID, playback: info.playback, source: info.source)
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
