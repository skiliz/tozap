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

// MARK: Legal notices stay complete and identical to the project's documents

let licenseSample = "MIT License\n\nCopyright (c) 2026 Cosmos Agency — Cosmos Open Source\n\nPermission is hereby granted…"
check(LegalNotices.copyrightLine(inLicense: licenseSample) == "Copyright (c) 2026 Cosmos Agency — Cosmos Open Source",
      "the copyright line is read verbatim from LICENSE")
let legal = LegalNotices.sections(license: licenseSample)
check(legal.count == 4 && legal.map(\.title) == ["Independent App", "Trademarks", "Copyright and License", "Third-Party Content"],
      "four legal sections in a stable order")
check(legal[0].body.contains("not affiliated with, endorsed by, or sponsored by Amazon"), "non-affiliation stated in full")
check(legal[1].body.contains("Amazon.com, Inc.") && legal[1].body.contains("other countries and regions")
      && legal[1].body.contains("ZAP by Checkmarx") && legal[1].body.contains("not made or certified by Apple"),
      "trademark owners, the AirPlay notice and the name notice are present")
check(legal[2].body.hasPrefix("Copyright (c) 2026 Cosmos Agency") && legal[2].body.contains("MIT License"),
      "copyright holder and license are shown")
check(LegalNotices.sections(license: nil)[2].body.contains("MIT License"), "the license is named even without the file")

/// Whitespace-collapsed text of a repository document (the runner starts in the repository root).
func repositoryText(_ name: String) -> String? {
    guard let data = FileManager.default.contents(atPath: name) else { return nil }
    return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "**", with: "")
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
if let readme = repositoryText("README.md") {
    check(readme.contains(LegalNotices.independence) && readme.contains(LegalNotices.trademarks)
          && readme.contains(LegalNotices.nameNotice) && readme.contains(LegalNotices.airPlayReceivers),
          "About's legal text matches the README disclaimer")
}
if let notices = repositoryText("THIRD_PARTY_NOTICES.md")?.lowercased() {
    check(notices.contains(LegalNotices.noThirdPartyCode.lowercased()) && notices.contains(LegalNotices.noAmazonCode.lowercased()),
          "About's third-party text matches THIRD_PARTY_NOTICES.md")
    check(notices.contains("app icons shown on shortcut tiles are not part of zap")
          && notices.contains("they belong to their respective owners, and screenshots that show them do not imply any affiliation"),
          "app icon ownership notice matches THIRD_PARTY_NOTICES.md")
}

// MARK: App IDs from the TV are validated before any use

check(FireTVApp.isValidAppID("com.netflix.ninja") && FireTVApp.isValidAppID("tv.maxplayer.android"), "package IDs accepted")
check(!FireTVApp.isValidAppID("../../Pictures/x") && !FireTVApp.isValidAppID("com") && !FireTVApp.isValidAppID("a b.c")
      && !FireTVApp.isValidAppID("com.example/evil"), "paths, spaces and single words refused")

// MARK: Pre-release files move out of the ZAP scanner's folder, leaving its own files alone

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
check(moved.terminationStatus == 0, "pre-release pairing (nickname kept) moves to ZAP Remote")
check(!FileManager.default.fileExists(atPath: scannerFolder.appendingPathComponent("device.json").path),
      "the token no longer sits in the scanner's folder")
check(FileManager.default.fileExists(atPath: scannerFolder.appendingPathComponent("config.xml").path),
      "the scanner's own files are never touched")
try? FileManager.default.removeItem(at: moveRoot)

print("\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
