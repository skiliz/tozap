import Foundation
import ZAPKit

// Child process of the migration test: a fresh process, so the store's folder can point somewhere else.
if CommandLine.arguments.contains("--migration-probe") {
    PairingStore.migrateLegacyStoreIfNeeded()
    exit(PairingStore.load()?.nickname == "Office" ? 0 : 1)
}

// Dependency-free test runner (the Command Line Tools ship no XCTest). Run: scripts/build.sh test
// It never touches the network or the real pairing store.

var failures = 0
var passed = 0

func check(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failures += 1
        print("FAIL \(URL(fileURLWithPath: file).lastPathComponent):\(line) \(message)")
    }
}

// MARK: Italian commands

let apps = [
    FireTVApp(appId: "tv.maxplayer.android", name: "MaxPlayer"),
    FireTVApp(appId: "com.netflix.ninja", name: "Netflix"),
    FireTVApp(appId: "com.amazon.firetv.youtube", name: "YouTube"),
    FireTVApp(appId: "it.rainet.androidtv", name: "RaiPlay"),
]

func expect(_ phrase: String, _ expected: VoiceIntent) {
    let got = ItalianCommands.parse(phrase, apps: apps)
    check(got == expected, "«\(phrase)» -> \(got), expected \(expected)")
}

expect("Apri MaxPlayer", .action(.launch(appId: "tv.maxplayer.android", name: "MaxPlayer"), times: 1))
expect("apri max player", .action(.launch(appId: "tv.maxplayer.android", name: "MaxPlayer"), times: 1))
expect("Apri Netflix", .action(.launch(appId: "com.netflix.ninja", name: "Netflix"), times: 1))
expect("apri you tube", .action(.launch(appId: "com.amazon.firetv.youtube", name: "YouTube"), times: 1))
expect("Pausa", .action(.media(.playPause), times: 1))
expect("Riprendi", .action(.media(.playPause), times: 1))
expect("Home", .action(.key(.home), times: 1))
expect("Torna alla home", .action(.key(.home), times: 1))
expect("Casa", .action(.key(.home), times: 1))
expect("Indietro", .action(.key(.back), times: 1))
expect("Torna indietro", .action(.key(.back), times: 1))
expect("Vai a destra", .action(.key(.right), times: 1))
expect("Vai a sinistra", .action(.key(.left), times: 1))
expect("Vai sotto", .action(.key(.down), times: 1))
expect("vai giù tre volte", .action(.key(.down), times: 3))
expect("Conferma", .action(.key(.select), times: 1))
expect("Destra, per favore", .action(.key(.right), times: 1))
check(ItalianCommands.parse("canale successivo", apps: apps) != .unknown, "channel requests are refused with a reason")
if case .action = ItalianCommands.parse("canale successivo", apps: apps) { check(false, "channel must not execute") }
if case .action = ItalianCommands.parse("alza il volume", apps: apps) { check(false, "volume must not execute") }
expect("vai su youtube", .unknown)
expect("destra sinistra", .unknown)
expect("che tempo fa", .unknown)
expect("", .unknown)
if case .action = ItalianCommands.parse("apri Pippo", apps: apps) { check(false, "unknown app must not launch") }
if case .action = ItalianCommands.parse("Apri MaxPlayer", apps: []) { check(false, "no launch without the TV's app list") }

// MARK: App matching

check(apps.maxPlayer?.appId == "tv.maxplayer.android", "MaxPlayer is found by name")
check([FireTVApp(appId: "com.netflix.ninja", name: "Netflix")].maxPlayer == nil, "MaxPlayer is never assumed")
check([FireTVApp(appId: "com.ionitech.airscreen", name: "AirScreen - AirPlay & Cast")].airPlayReceivers.count == 1,
      "AirScreen is recognised as a receiver")

// MARK: Panel fits the screen (effective resolutions, menu bar and Dock excluded)

let screens: [(String, CGFloat)] = [
    ("1280x800", 800 - 25 - 70), ("1440x900", 900 - 25 - 70), ("1512x982 notch", 982 - 38 - 70),
    ("1728x1117 notch", 1117 - 38 - 70), ("1920x1080", 1080 - 25 - 70), ("small desktop", 520),
]
for (name, visible) in screens {
    for content: CGFloat in [420, 560, 760, 1200] {
        let page = PanelLayout.scrollHeight(content: content, visibleHeight: visible)
        let panel = page + PanelLayout.chrome
        check(panel <= max(visible, PanelLayout.minimumScrollHeight + PanelLayout.chrome),
              "\(name): panel \(panel) fits visible \(visible) (content \(content))")
        check(page <= content, "\(name): never taller than its content")
        check(page >= min(content, PanelLayout.minimumScrollHeight), "\(name): keeps a usable scroll area")
    }
}

// MARK: Pairing store (temporary folder only)

let temp = FileManager.default.temporaryDirectory.appendingPathComponent("zap-tests-\(UUID().uuidString)")
setenv("ZAP_SUPPORT_DIR", temp.path, 1)
defer { try? FileManager.default.removeItem(at: temp) }

let legacy = temp.appendingPathComponent("Fire Remote")
try! FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
let oldJSON = """
{"clientName":"Mac Remote","host":"10.0.0.9","pairedAt":"2026-10-28T23:09:53Z","rootCertificate":"AAEC","token":"t0k3n"}
"""
try! Data(oldJSON.utf8).write(to: legacy.appendingPathComponent("device.json"))

PairingStore.migrateLegacyStoreIfNeeded()
let migrated = PairingStore.load()
check(migrated?.token == "t0k3n", "legacy pairing is migrated")
check(migrated?.deviceID == nil && migrated?.nickname == nil, "old files decode with the new optional fields")
check(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("device.json").path),
      "migration copies, never moves")
let mode = (try? FileManager.default.attributesOfItem(atPath: PairingStore.deviceFile.path)[.posixPermissions]) as? Int
check(mode == 0o600, "pairing file is 0600 (got \(String(mode ?? 0, radix: 8)))")

// MARK: Display name never shows the address

var device = migrated!
check(device.displayName == "Fire TV", "no name -> generic label, not the IP")
device.deviceName = "Living Room"
check(device.displayName == "Living Room", "advertised name")
device.nickname = "  "
check(device.displayName == "Living Room", "blank nickname ignored")
device.nickname = "Bedroom"
check(device.displayName == "Bedroom", "nickname wins")
check(migrated?.softwareVersion == nil, "software version stays unknown until the TV reported it")

// MARK: Forget This TV stays forgotten (the pre-1.0 copy can't bring it back)

PairingStore.forget()
check(PairingStore.load() == nil, "Forget removes the pairing")
check(!FileManager.default.fileExists(atPath: legacy.appendingPathComponent("device.json").path),
      "Forget also removes the pre-1.0 copy of the token")
try! Data(oldJSON.utf8).write(to: legacy.appendingPathComponent("device.json"))  // even if it reappeared
PairingStore.migrateLegacyStoreIfNeeded()
check(PairingStore.load() == nil, "the old store is migrated once, never again after Forget")

// MARK: Quick actions keep the user's saved shortcuts

let savedBefore = #"[{"name":"Netflix","appId":"com.netflix.ninja"},{"name":"Prime Video"}]"#
let decoded = try! JSONDecoder().decode([QuickAction].self, from: Data(savedBefore.utf8))
check(decoded.count == 2 && decoded.allSatisfy(\.isEnabled), "shortcuts saved before 'isEnabled' stay shown")
check(decoded[1].appId == nil && decoded[1].id == "suggested:Prime Video", "unresolved suggestion keeps no ID")
var hidden = decoded
hidden[0].isEnabled = false
let roundTrip = try! JSONDecoder().decode([QuickAction].self, from: JSONEncoder().encode(hidden))
check(roundTrip == hidden, "hidden shortcut survives a save")
let four = ["a.one", "b.two", "c.three", "d.four"].map { QuickAction(name: $0, appId: $0) }
check(four.moving("d.four", to: "a.one").map(\.appId!) == ["d.four", "a.one", "b.two", "c.three"], "drag up")
check(four.moving("a.one", to: "c.three").map(\.appId!) == ["b.two", "c.three", "a.one", "d.four"], "drag down")
check(four.moving("b.two", by: -1).map(\.appId!) == ["b.two", "a.one", "c.three", "d.four"], "move up one step")
check(four.moving("d.four", by: 1) == four, "last item can't move further down")
check(four.moving("x.unknown", to: "a.one") == four, "unknown ID changes nothing")

// MARK: Now Playing never shows unverified or invented metadata

let now = Date()
let report = NowPlayingInfo(appID: "com.netflix.ninja", appName: "Netflix", title: "Episode title",
                            detail: "S1 · E2", source: .fireTVProtocol, observedAt: now)
check(NowPlayingPolicy.verifiedSources.isEmpty && !NowPlayingPolicy.isAvailable,
      "no metadata source is verified in this build")
check(NowPlayingPolicy.presentation(for: report, enabled: true, now: now) == nil, "unverified source shows nothing")
check(NowPlayingPolicy.presentation(for: nil, enabled: true, now: now, verified: [.fireTVProtocol]) == nil,
      "no report shows nothing")
let shown = NowPlayingPolicy.presentation(for: report, enabled: true, now: now, verified: [.fireTVProtocol])
check(shown?.title == "Episode title" && shown?.detail == "S1 · E2" && shown?.playback == .unknown,
      "a verified report is shown as reported, playback state not inferred")
check(NowPlayingPolicy.presentation(for: report, enabled: false, now: now, verified: [.fireTVProtocol]) == nil,
      "the setting turns it off")
check(NowPlayingPolicy.presentation(for: report, enabled: true, now: now.addingTimeInterval(31),
                                    verified: [.fireTVProtocol]) == nil, "stale reports are dropped")
var untitled = report
untitled.title = "   "
check(NowPlayingPolicy.presentation(for: untitled, enabled: true, now: now, verified: [.fireTVProtocol]) == nil,
      "an app name alone is not 'Now Playing'")
var appOnly = report
appOnly.source = .dialApplicationStatus
appOnly.title = nil
check(NowPlayingPolicy.presentation(for: appOnly, enabled: true, now: now, verified: [.dialApplicationStatus]) == nil,
      "DIAL running state never becomes a title")

// MARK: Menu bar status shows only real state

let checkedAt = Date()
func menuStatus(_ connection: ConnectionState, paired: Bool = true, verified: Date? = checkedAt, now: Date = checkedAt,
                listening: Bool = false, display: String? = nil, preview: Bool = false) -> MenuBarStatus {
    MenuBarStatus.resolve(deviceName: paired ? "Living Room" : nil, connection: connection, verifiedAt: verified,
                          now: now, listening: listening, mirroringDisplay: display, offlinePreview: preview)
}
check(menuStatus(.connected).link == .connected, "a fresh confirmation is green")
check(menuStatus(.connected, now: checkedAt.addingTimeInterval(MenuBarStatus.freshness + 1)).link == .unknown,
      "an old confirmation is no longer green (ZAP doesn't poll)")
check(menuStatus(.connected, verified: nil).link == .unknown, "never green without a confirmation")
check(menuStatus(.connected, verified: checkedAt.addingTimeInterval(60)).link == .unknown, "a future timestamp isn't trusted")
check(menuStatus(.checking).link == .unknown && menuStatus(.notChecked).link == .unknown, "unchecked states are gray")
check(menuStatus(.unavailable).link == .unreachable, "confirmed unreachable is red")
check(menuStatus(.pairingRequired).link == .unreachable, "a rejected pairing is red")
check(menuStatus(.pairingRequired, paired: false).link == .unknown, "not paired is gray, not red")
check(menuStatus(.reconnecting).link == .reconnecting && menuStatus(.searching).link == .reconnecting,
      "looking for the TV again is amber")
check(menuStatus(.connected, preview: true).link == .preview && menuStatus(.preview).link == .preview,
      "the offline preview is never green")
check(menuStatus(.connected, listening: true).listening, "the microphone state is carried")
check(menuStatus(.connected).mirroringDisplay == nil, "no mirroring indicator without a matching display")
let described = menuStatus(.unavailable, listening: true, display: "Android AirPlay").description
check(described.hasPrefix("Living Room: Unreachable") && described.contains("Microphone on")
      && described.contains("Android AirPlay"), "the tooltip names the TV and every active state")
check(AirPlayDisplay.matches(screenName: "Android AirPlay", receiver: "android airplay"), "AirPlay display matched by name")
check(!AirPlayDisplay.matches(screenName: "Built-in Retina Display", receiver: "Android AirPlay"), "built-in display never matches")
check(!AirPlayDisplay.matches(screenName: "LG TV", receiver: "TV"), "too-short receiver names never match")

// MARK: Legal notices stay in the public documents (About no longer shows them)

/// Whitespace-collapsed text of a repository document (the runner starts in the repository root).
func repositoryText(_ name: String) -> String? {
    guard let data = FileManager.default.contents(atPath: name) else { return nil }
    return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "**", with: "")
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
check(repositoryText("README.md") != nil && repositoryText("LICENSE") != nil && repositoryText("THIRD_PARTY_NOTICES.md") != nil,
      "README, LICENSE and THIRD_PARTY_NOTICES.md exist (missing files fail instead of skipping)")
if let readme = repositoryText("README.md") {
    for notice in [
        "to.zap is an independent third-party application and is not affiliated with, endorsed by, or sponsored by Amazon.",
        "Amazon, Fire TV, Fire OS and Alexa are trademarks of Amazon.com, Inc. or its affiliates.",
        "Apple, AirPlay and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.",
        "AirPlay receiver apps for Fire TV are third-party apps, not made or certified by Apple.",
        "to.zap is unrelated to the ZAP web security scanner (ZAP by Checkmarx, formerly OWASP ZAP) and to other products named ZAP or Tozap.",
    ] {
        check(readme.contains(notice), "README keeps the notice: \(notice.prefix(40))…")
    }
}
if let license = repositoryText("LICENSE") {
    check(license.hasPrefix("MIT License") && license.contains("Copyright (c) 2026 Cosmos Agency"),
          "LICENSE keeps the MIT text and the copyright line")
}
if let notices = repositoryText("THIRD_PARTY_NOTICES.md")?.lowercased() {
    check(notices.contains("to.zap contains no third-party code and has no package dependencies")
          && notices.contains("no amazon software was decompiled and no amazon code, keys, firmware, apks or assets are included"),
          "THIRD_PARTY_NOTICES.md keeps the code and Amazon statements")
    check(notices.contains("app icons shown on shortcut tiles are not part of to.zap")
          && notices.contains("they belong to their respective owners, and screenshots that show them do not imply any affiliation"),
          "app icon ownership notice stays in THIRD_PARTY_NOTICES.md")
}
// MARK: Bundle identifier and the one-time move of pre-release preferences

if let plist = NSDictionary(contentsOfFile: "Resources/Info.plist") {
    check(plist["CFBundleIdentifier"] as? String == "local.tozap.app", "the bundle identifier is local.tozap.app")
    check(plist["CFBundleName"] as? String == "to.zap" && plist["CFBundleDisplayName"] as? String == "to.zap"
          && plist["CFBundleExecutable"] as? String == "to.zap", "the product is named to.zap")
    check(PreferencesMigration.currentDomain == plist["CFBundleIdentifier"] as? String, "preferences migrate into the bundle identifier's domain")
} else {
    check(false, "Resources/Info.plist is readable")
}
/// In-memory defaults, so the tests never write to ~/Library/Preferences.
final class MemoryStore: PreferenceStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
}
let legacyDefaults = MemoryStore(), targetDefaults = MemoryStore()
legacyDefaults.set(["Netflix", "MaxPlayer"], forKey: "quickActions")
legacyDefaults.set(false, forKey: "showAppIcons")
legacyDefaults.set("alexa", forKey: "voiceMode")
legacyDefaults.set(true, forKey: "automationURLs")
targetDefaults.set("apple", forKey: "voiceMode")           // already chosen in the new domain: kept
var legacyRemoved = false
let movedKeys = PreferencesMigration.migrate(from: legacyDefaults, to: targetDefaults,
                                             keys: ["quickActions", "showAppIcons", "voiceMode"]) { legacyRemoved = true }
check(movedKeys == ["quickActions", "showAppIcons"], "existing pre-release settings are copied")
check(targetDefaults.object(forKey: "quickActions") as? [String] == ["Netflix", "MaxPlayer"]
      && targetDefaults.object(forKey: "showAppIcons") as? Bool == false, "copied values are identical")
check(targetDefaults.object(forKey: "voiceMode") as? String == "apple", "a value already set in the new domain is never overwritten")
check(targetDefaults.object(forKey: "automationURLs") == nil, "the developer automation switch is never migrated")
check(legacyRemoved && targetDefaults.bool(forKey: PreferencesMigration.markerKey), "the old domain is removed only after the copy")
check(PreferencesMigration.migrate(from: legacyDefaults, to: targetDefaults, keys: ["quickActions"]) { legacyRemoved = false } == nil
      && legacyRemoved, "the migration runs once")
check(PreferencesMigration.migrate(from: MemoryStore(), to: MemoryStore(), keys: ["quickActions"]) {} == [],
      "a new user has nothing to migrate")
/// A store whose writes don't stick, to prove the legacy copy is kept when verification fails.
final class LossyStore: PreferenceStore {
    var written: Set<String> = []
    func object(forKey key: String) -> Any? { written.contains(key) ? ["changed"] : nil }
    func set(_ value: Any?, forKey key: String) { written.insert(key) }
    func bool(forKey key: String) -> Bool { false }
}
var removedDespiteLoss = false
check(PreferencesMigration.migrate(from: legacyDefaults, to: LossyStore(), keys: ["quickActions"]) { removedDespiteLoss = true } == nil
      && !removedDespiteLoss, "if a copied value doesn't read back identical, the old domain is kept")
check(PreferencesMigration.migratedKeys.contains("NSWindow Frame \(PreferencesMigration.settingsWindowAutosaveName)"),
      "the window position is migrated under AppKit's real autosave key")
check(!PreferencesMigration.migratedKeys.contains("automationURLs") && PreferencesMigration.migratedKeys.contains("quickActions")
      && PreferencesMigration.migratedKeys.contains("airPlayReceiverNames"),
      "the real key list moves the settings and never the developer automation switch")

// MARK: One product identity across code, packaging and the Homebrew cask

check(ZAPProject.appBundleName == "to.zap.app" && ZAPProject.homebrewCask == "tozap-remote"
      && ZAPProject.repository.absoluteString == "https://github.com/skiliz/tozap", "to.zap's bundle, cask and repository")
if let package = repositoryText("scripts/package.sh"), let release = repositoryText("scripts/release.sh"),
   let build = repositoryText("scripts/build.sh") {
    check(build.contains("APP=\"$OUT/to.zap.app\"") && build.contains("Contents/MacOS/to.zap\""), "build.sh makes to.zap.app")
    check(package.contains("APP=\"build/to.zap.app\"") && package.contains("tozap-$VERSION.zip") && package.contains("tozap-$VERSION.dmg"),
          "package.sh packages to.zap.app as tozap-<version>.zip/.dmg")
    check(release.contains("\"local.tozap.app\"") && release.contains("Casks/tozap-remote.rb"), "release.sh checks local.tozap.app and writes the tozap-remote cask")
} else {
    check(false, "the build scripts are readable")
}
if let cask = repositoryText("../homebrew-tap/templates/tozap-remote-adhoc.rb.in") {
    check(cask.contains("cask \"tozap-remote\" do") && cask.contains("app \"to.zap.app\"")
          && cask.contains("https://github.com/skiliz/tozap/releases/download/v#{version}/tozap-#{version}.zip")
          && cask.contains("~/Library/Application Support/to.zap") && cask.contains("~/Library/Preferences/local.tozap.app.plist"),
          "the Homebrew cask installs to.zap.app from the tozap release and removes only its own data with --zap")
}
check(PairingStore.directory.lastPathComponent == "to.zap", "pairing data lives in Application Support/to.zap")

// MARK: Media buttons say what they send (the Fire TV interface has no previous/next)

check(MediaCommand.allCases == [.playPause, .forward, .rewind], "only Play/Pause, Fast-forward and Rewind exist")
check(FireTVClient.mediaPath(.playPause) == "/v1/media?action=play" && FireTVClient.scanDirection(.playPause) == nil,
      "Play/Pause is unchanged: the play toggle, no body")
check(FireTVClient.mediaPath(.forward) == "/v1/media?action=scan" && FireTVClient.scanDirection(.forward) == "forward"
      && FireTVClient.mediaPath(.rewind) == "/v1/media?action=scan" && FireTVClient.scanDirection(.rewind) == "back",
      "Fast-forward and Rewind send scan, the interface's seek")
check(MediaCommand.forward.label == "Fast-forward" && MediaCommand.rewind.label == "Rewind"
      && MediaCommand.forward.symbol == "forward.fill" && MediaCommand.rewind.symbol == "backward.fill",
      "seek buttons are never labelled or drawn as previous/next")
check(MediaCommand.allCases.allSatisfy { !$0.label.lowercased().contains("next") && !$0.label.lowercased().contains("previous") },
      "no media label claims previous/next")

// MARK: Check for Updates

func semver(_ text: String) -> SemanticVersion { SemanticVersion(text)! }
check(semver("1.0.10") > semver("1.0.9"), "versions compare numerically, not as text")
check(semver("v1.2") == semver("1.2.0") && semver("1") == semver("1.0.0"), "a leading v and missing parts are accepted")
check(semver("1.0.0-beta.2") < semver("1.0.0") && semver("1.0.0-alpha") < semver("1.0.0-alpha.1")
      && semver("1.0.0-alpha.1") < semver("1.0.0-beta") && semver("1.0.0-beta.2") < semver("1.0.0-beta.11")
      && semver("1.0.0-1") < semver("1.0.0-alpha"),
      "prereleases follow SemVer precedence")
check(semver("1.0.0+5") == semver("1.0.0"), "build metadata is ignored")
check(semver("2.0.0-rc.1").isPrerelease && !semver("2.0.0").isPrerelease, "prereleases are recognised")
for bad in ["", "abc", "1.2.3.4", "1..2", "1.2.x", "1.0.0-", "1.0.0-be..ta", "１.0.0", "1.0.0-beta!", "1.0.0-bèta"] {
    check(SemanticVersion(bad) == nil, "invalid version rejected: \(bad)")
}

func release(_ tag: String, url: String = "https://github.com/skiliz/tozap/releases/tag/v1.1.0",
             prerelease: Bool = false, draft: Bool = false) -> Data {
    let object: [String: Any] = ["tag_name": tag, "html_url": url, "prerelease": prerelease, "draft": draft]
    return try! JSONSerialization.data(withJSONObject: object)
}
func evaluate(_ status: Int, _ body: Data = Data(), headers: [String: String] = [:],
              installed: String = "1.0.0") -> UpdateCheckResult {
    UpdateChecker.evaluate(statusCode: status, header: { headers[$0] }, body: body,
                           installed: semver(installed), now: Date(timeIntervalSince1970: 1_000))
}
let releasePage = URL(string: "https://github.com/skiliz/tozap/releases/tag/v1.1.0")!
check(evaluate(200, release("v1.0.0")) == .upToDate(installed: semver("1.0.0")), "same version: up to date")
check(evaluate(200, release("v1.0.0"), installed: "1.2.0") == .upToDate(installed: semver("1.2.0")),
      "an installed build newer than the release is up to date")
check(evaluate(200, release("v1.1.0")) == .updateAvailable(installed: semver("1.0.0"), latest: semver("1.1.0"), releasePage: releasePage),
      "newer stable release: update available with its release page")
check(evaluate(200, release("v1.0.10"), installed: "1.0.9") != .upToDate(installed: semver("1.0.9")),
      "1.0.10 is newer than 1.0.9")
check(evaluate(404) == .noPublicRelease, "no release (or no public repository): explained, not an error")
check(evaluate(200, release("v1.1.0-beta.1")) == .noPublicRelease, "a prerelease tag is never offered to stable users")
check(evaluate(200, release("v1.1.0", prerelease: true)) == .noPublicRelease, "a release flagged prerelease is never offered")
check(evaluate(200, release("v1.1.0", draft: true)) == .noPublicRelease, "a draft is never offered")
check(evaluate(200, release("v1.1.0", url: "https://evil.example/skiliz/tozap/releases/tag/v1.1.0"))
      == .updateAvailable(installed: semver("1.0.0"), latest: semver("1.1.0"), releasePage: ZAPProject.releasesPage),
      "a release link off github.com is replaced by ZAP's release list")
for link in ["http://github.com/skiliz/tozap/releases/tag/v1", "https://github.com/other/zap/releases/tag/v1",
             "https://github.com/skiliz/tozap/releases/../../other", "https://user@github.com/skiliz/tozap/releases/tag/v1",
             "https://github.com:444/skiliz/tozap/releases/tag/v1", "javascript:alert(1)"] {
    check(UpdateChecker.releasePage(link) == ZAPProject.releasesPage, "unsafe release link refused: \(link)")
}
check(evaluate(403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "5000"])
      == .rateLimited(retryAfter: Date(timeIntervalSince1970: 5000)), "rate limit with its reset time")
check(evaluate(429, headers: ["Retry-After": "60"]) == .rateLimited(retryAfter: Date(timeIntervalSince1970: 1060)),
      "secondary rate limit with Retry-After")
check(evaluate(429) == .rateLimited(retryAfter: nil), "429 without headers is still a rate limit")
check(evaluate(429, headers: ["Retry-After": "inf"]) == .rateLimited(retryAfter: nil)
      && evaluate(403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "nan"]) == .rateLimited(retryAfter: nil),
      "non-finite rate-limit times are ignored")
check(evaluate(403) == .serverError(403), "a plain 403 is not mistaken for a rate limit")
check(evaluate(500) == .serverError(500) && evaluate(301) == .serverError(301), "other statuses are server errors")
check(evaluate(200, Data("not json".utf8)) == .invalidResponse, "invalid JSON is never a success")
check(evaluate(200, Data(#"{"html_url":"https://github.com/skiliz/tozap/releases"}"#.utf8)) == .invalidResponse,
      "a release without a tag is invalid")
check(evaluate(200, release("latest")) == .invalidResponse, "a tag that isn't a version is invalid")
check(evaluate(200, Data(count: UpdateChecker.maxResponseBytes + 1)) == .invalidResponse, "oversized answers are refused")
check(ZAPProject.latestReleaseAPI.absoluteString == "https://api.github.com/repos/skiliz/tozap/releases/latest"
      && ZAPProject.repository.absoluteString == "https://github.com/skiliz/tozap",
      "the official repository and its latest-release endpoint")
check(ZAPProject.homebrewUpgradeCommand == "brew upgrade --cask skiliz/tap/tozap-remote", "the Homebrew upgrade command")
let semaphore = DispatchSemaphore(value: 0)
var unknownVersionResult: UpdateCheckResult?
Task { unknownVersionResult = await UpdateChecker.check(installedVersion: "—"); semaphore.signal() }
semaphore.wait()
check(unknownVersionResult == .unknownInstalledVersion, "an unreadable installed version stops before any request")
check([URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed]
      .allSatisfy(UpdateChecker.networkFailures.contains)
      && !UpdateChecker.networkFailures.contains(.serverCertificateUntrusted)
      && !UpdateChecker.networkFailures.contains(.badServerResponse),
      "offline and timeouts are 'network unavailable'; TLS and protocol errors are not")

typealias Seen = (name: String, onTV: Bool)
let seen: [Seen] = [("Android AirPlay", true), ("Living Room Apple TV", false)]
check(AirPlayReceiverChoice.shown(seen, tvPaired: true) == ["Android AirPlay"], "with a paired TV, only its own receiver is shown")
check(AirPlayReceiverChoice.shown([("Living Room Apple TV", false)], tvPaired: true).isEmpty,
      "another AirPlay device is never presented as the TV's receiver")
check(AirPlayReceiverChoice.shown(seen, tvPaired: false) == ["Android AirPlay", "Living Room Apple TV"],
      "without a paired TV, every visible receiver is listed")

let caskroom: Set<String> = ["/opt/homebrew/Caskroom/tozap-remote"]
check(InstallationSource.detect(bundlePath: "/Applications/to.zap.app", home: "/Users/u",
                                fileExists: caskroom.contains) == .homebrew, "Homebrew cask in /Applications")
check(InstallationSource.detect(bundlePath: "/Users/u/Applications/to.zap.app", home: "/Users/u",
                                fileExists: caskroom.contains) == .homebrew, "Homebrew cask in ~/Applications")
check(InstallationSource.detect(bundlePath: "/Applications/to.zap.app", home: "/Users/u",
                                fileExists: { _ in false }) == .unknown, "no Caskroom entry: origin unknown")
check(InstallationSource.detect(bundlePath: "/Users/u/Downloads/to.zap.app", home: "/Users/u",
                                fileExists: caskroom.contains) == .unknown, "a copy outside Applications isn't claimed by Homebrew")

// MARK: App IDs from the TV are validated before any use

check(FireTVApp.isValidAppID("com.netflix.ninja") && FireTVApp.isValidAppID("tv.maxplayer.android"), "package IDs accepted")
check(!FireTVApp.isValidAppID("../../Pictures/x") && !FireTVApp.isValidAppID("com") && !FireTVApp.isValidAppID("a b.c")
      && !FireTVApp.isValidAppID("com.example/evil"), "paths, spaces and single words refused")

// MARK: Pre-release pairing data moves to "to.zap" (from "ZAP" without touching the scanner's own files)

let moveRoot = FileManager.default.temporaryDirectory.appendingPathComponent("zap-move-\(UUID().uuidString)")
let scannerFolder = moveRoot.appendingPathComponent("ZAP")
try! FileManager.default.createDirectory(at: scannerFolder, withIntermediateDirectories: true)
let pairedJSON = """
{"clientName":"ZAP for Mac","host":"10.0.0.9","pairedAt":"2026-10-29T09:00:00Z","rootCertificate":"AAEC","token":"t0k3n","nickname":"Office"}
"""
try! Data(pairedJSON.utf8).write(to: scannerFolder.appendingPathComponent("device.json"))
try! Data("[]".utf8).write(to: scannerFolder.appendingPathComponent("apps.json"))
try! Data("scanner".utf8).write(to: scannerFolder.appendingPathComponent("config.xml"))
let moved = Process()
moved.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
moved.arguments = ["--migration-probe"]
moved.environment = ["ZAP_SUPPORT_DIR": moveRoot.path]
try! moved.run()
moved.waitUntilExit()
check(moved.terminationStatus == 0, "pre-release pairing (nickname kept) moves to to.zap")
check(!FileManager.default.fileExists(atPath: scannerFolder.appendingPathComponent("device.json").path),
      "the token no longer sits in the scanner's folder")
check(FileManager.default.fileExists(atPath: scannerFolder.appendingPathComponent("config.xml").path),
      "the scanner's own files are never touched")
try? FileManager.default.removeItem(at: moveRoot)

// The latest pre-release folder, "ZAP Remote": pairing, app list and icon cache all move; the empty folder goes.
let remoteRoot = FileManager.default.temporaryDirectory.appendingPathComponent("zap-move-\(UUID().uuidString)")
let remoteFolder = remoteRoot.appendingPathComponent("ZAP Remote")
try! FileManager.default.createDirectory(at: remoteFolder.appendingPathComponent("icons-v2"), withIntermediateDirectories: true)
try! Data(pairedJSON.utf8).write(to: remoteFolder.appendingPathComponent("device.json"))
try! Data("[]".utf8).write(to: remoteFolder.appendingPathComponent("apps.json"))
try! Data("png".utf8).write(to: remoteFolder.appendingPathComponent("icons-v2/abc.png"))
let movedRemote = Process()
movedRemote.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
movedRemote.arguments = ["--migration-probe"]
movedRemote.environment = ["ZAP_SUPPORT_DIR": remoteRoot.path]
try! movedRemote.run()
movedRemote.waitUntilExit()
let newFolder = remoteRoot.appendingPathComponent("to.zap")
check(movedRemote.terminationStatus == 0, "the ZAP Remote pairing (nickname kept) moves to to.zap")
check(FileManager.default.fileExists(atPath: newFolder.appendingPathComponent("icons-v2/abc.png").path),
      "the icon cache moves with it")
check(!FileManager.default.fileExists(atPath: remoteFolder.path), "the emptied ZAP Remote folder is removed")
try? FileManager.default.removeItem(at: remoteRoot)

print("\(passed) passed, \(failures) failed")
try? FileManager.default.removeItem(at: temp)  // `exit` skips the top-level defer
exit(failures == 0 ? 0 : 1)
