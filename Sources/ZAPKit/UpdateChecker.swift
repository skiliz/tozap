import Foundation

/// ZAP's public project addresses. Everything the update check and About open is derived from these.
public enum ZAPProject {
    public static let repository = URL(string: "https://github.com/skiliz/zap")!
    public static let releasesPage = URL(string: "https://github.com/skiliz/zap/releases")!
    public static let mirroringGuide = URL(string: "https://github.com/skiliz/zap/blob/main/docs/MIRRORING.md")!
    /// The latest published full release: GitHub never returns drafts or prereleases here, and answers 404
    /// when there is none.
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/skiliz/zap/releases/latest")!
    public static let homebrewCask = "zap-remote"
    public static let homebrewUpgradeCommand = "brew upgrade --cask skiliz/tap/zap-remote"
}

/// A Semantic Versioning 2.0 version ("1.2.3", "v1.2.3-beta.1+5"). One or two numeric components are
/// accepted and padded with zeros; ordering follows the SemVer precedence rules, never string order.
public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Prerelease identifiers ("beta", "1"); empty for a stable version. Build metadata is ignored.
    public let prerelease: [String]

    public init?(_ text: String) {
        var core = text.trimmingCharacters(in: .whitespaces)
        if core.first == "v" || core.first == "V" { core.removeFirst() }
        if let plus = core.firstIndex(of: "+") { core = String(core[..<plus]) }
        var pre: [String] = []
        if let dash = core.firstIndex(of: "-") {
            pre = core[core.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            core = String(core[..<dash])
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
            guard !pre.isEmpty, pre.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 9 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
        else { return nil }
        let numbers = parts.compactMap { Int($0) } + Array(repeating: 0, count: 3 - parts.count)
        major = numbers[0]; minor = numbers[1]; patch = numbers[2]
        prerelease = pre
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        // A prerelease sorts before its stable version.
        switch (a.prerelease.isEmpty, b.prerelease.isEmpty) {
        case (true, true), (true, false): return false
        case (false, true): return true
        case (false, false): break
        }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (numeric(x), numeric(y)) {
            case let (i?, j?): return i < j
            case (.some, nil): return true          // numeric identifiers sort before alphanumeric ones
            case (nil, .some): return false
            case (nil, nil): return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }

    private static func numeric(_ identifier: String) -> Int? {
        identifier.allSatisfy { $0.isASCII && $0.isNumber } ? Int(identifier) : nil
    }

    public static func == (a: SemanticVersion, b: SemanticVersion) -> Bool { !(a < b) && !(b < a) }
}

/// What a check for updates found. Each case is shown to the user as it is; none is ever reported as
/// "up to date" unless GitHub confirmed a stable release no newer than the installed one.
public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(installed: SemanticVersion)
    case updateAvailable(installed: SemanticVersion, latest: SemanticVersion, releasePage: URL)
    /// GitHub has no published stable release (also the answer while the repository isn't public).
    case noPublicRelease
    case networkUnavailable
    /// GitHub's anonymous API limit was reached; `retryAfter` when GitHub said when it resets.
    case rateLimited(retryAfter: Date?)
    case invalidResponse
    case serverError(Int)
    /// The running app's own version string couldn't be read.
    case unknownInstalledVersion
}

public enum UpdateChecker {
    /// Larger answers are refused rather than parsed.
    public static let maxResponseBytes = 1_000_000

    /// Asks GitHub once, only when called (the user clicked Check for Updates): no account, no token, no
    /// cookies, no cache, no background polling, nothing downloaded or installed.
    public static func check(installedVersion: String) async -> UpdateCheckResult {
        guard let installed = SemanticVersion(installedVersion) else { return .unknownInstalledVersion }
        var request = URLRequest(url: ZAPProject.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ZAP", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .invalidResponse }
            return evaluate(statusCode: http.statusCode,
                            header: { http.value(forHTTPHeaderField: $0) },
                            body: data, installed: installed)
        } catch let error as URLError {
            return networkFailures.contains(error.code) ? .networkUnavailable : .invalidResponse
        } catch {
            return .invalidResponse
        }
    }

    static let networkFailures: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: GitHubAPIRedirectsOnly(), delegateQueue: nil)
    }()

    /// Turns GitHub's answer into a result. Pure, so every case is tested without the network.
    public static func evaluate(statusCode: Int, header: (String) -> String?, body: Data,
                                installed: SemanticVersion, now: Date = Date()) -> UpdateCheckResult {
        switch statusCode {
        case 200:
            break
        case 404:
            return .noPublicRelease
        case 403, 429:
            if let retry = header("Retry-After").flatMap(Double.init) {
                return .rateLimited(retryAfter: now.addingTimeInterval(retry))
            }
            if header("X-RateLimit-Remaining") == "0" || statusCode == 429 {
                let reset = header("X-RateLimit-Reset").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
                return .rateLimited(retryAfter: reset)
            }
            return .serverError(statusCode)
        default:
            return .serverError(statusCode)
        }
        guard body.count <= maxResponseBytes,
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: body),
              let latest = SemanticVersion(release.tagName)
        else { return .invalidResponse }
        // `releases/latest` never returns these; if it ever did, a stable user is not sent to them.
        if release.draft == true || release.prerelease == true || latest.isPrerelease { return .noPublicRelease }
        guard latest > installed else { return .upToDate(installed: installed) }
        return .updateAvailable(installed: installed, latest: latest, releasePage: releasePage(release.htmlURL))
    }

    /// The release's own page when it is one of ZAP's GitHub releases; otherwise ZAP's release list.
    public static func releasePage(_ text: String?) -> URL {
        guard let text, let url = URL(string: text), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.port == nil,
              url.path.hasPrefix(ZAPProject.releasesPage.path + "/"), !url.path.contains("..")
        else { return ZAPProject.releasesPage }
        return url
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String?
        let draft: Bool?
        let prerelease: Bool?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", htmlURL = "html_url", draft, prerelease
        }
    }
}

/// GitHub redirects renamed repositories within its API; anything else is refused.
private final class GitHubAPIRedirectsOnly: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let ok = request.url?.scheme == "https" && request.url?.host == ZAPProject.latestReleaseAPI.host
        completionHandler(ok ? request : nil)
    }
}

/// How this copy of ZAP was installed, only when that can be verified on disk.
public enum InstallationSource: Equatable, Sendable {
    /// Homebrew's Caskroom holds the zap-remote cask and the running app sits in an Applications folder.
    case homebrew
    /// Downloaded, built from source, or anything else that can't be told apart.
    case unknown

    public static func detect(bundlePath: String,
                              home: String = NSHomeDirectory(),
                              fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> InstallationSource {
        let folder = (bundlePath as NSString).deletingLastPathComponent
        let inApplications = folder == "/Applications" || folder == (home as NSString).appendingPathComponent("Applications")
        guard inApplications, (bundlePath as NSString).lastPathComponent == "ZAP Remote.app" else { return .unknown }
        let caskrooms = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
        return caskrooms.contains { fileExists("\($0)/\(ZAPProject.homebrewCask)") } ? .homebrew : .unknown
    }
}
