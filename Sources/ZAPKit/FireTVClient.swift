import Foundation
import os

public enum FireTVError: LocalizedError, Sendable, Equatable {
    case notPaired
    case unauthorized
    case untrustedCertificate(String)
    case serviceUnavailable
    case pinRejected
    case http(Int, String)
    case network(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .notPaired: return "Not paired with a Fire TV."
        case .unauthorized: return "The Fire TV rejected the pairing token. Pair again."
        case .untrustedCertificate(let why): return "Refused an untrusted TLS connection: \(why)."
        case .serviceUnavailable: return "The Fire TV remote service did not start."
        case .pinRejected: return "The Fire TV rejected the PIN."
        case .http(let code, _): return "The Fire TV answered HTTP \(code)."
        case .network(let why): return "Cannot reach the Fire TV: \(why)"
        case .unsupported(let why): return why
        }
    }
}

/// Client for the Fire TV app's local REST protocol (HTTPS :8080, started via DIAL on :8009).
/// Every request goes over a TLS chain verified against the pinned Amazon root (see `RootPinningDelegate`).
public final class FireTVClient: @unchecked Sendable {
    /// Public constant of the Fire TV app protocol, not a secret.
    public static let apiKey = "0987654321"

    public let host: String
    private let token: String?
    private let trust: RootPinningDelegate
    private let session: URLSession
    private let log = Logger(subsystem: "local.fireremote.app", category: "client")

    public init(host: String, token: String?, pinnedRoot: Data?) {
        self.host = host
        self.token = token
        trust = RootPinningDelegate(pinnedRootDER: pinnedRoot)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: trust, delegateQueue: nil)
    }

    public convenience init(device: PairedDevice) {
        self.init(host: device.host, token: device.token, pinnedRoot: device.rootCertificate)
    }

    deinit { session.invalidateAndCancel() }

    // MARK: Commands

    public func perform(_ action: RemoteAction) async throws {
        switch action {
        case .key(let key): try await press(key)
        case .media(let command): try await media(command)
        case .launch(let appId, _): try await launch(appId: appId)
        }
    }

    /// One press: no body (an empty JSON body made older Fire OS answer 500).
    public func press(_ key: NavKey) async throws {
        try await rest("POST", "/v1/FireTV?action=\(key.rawValue)")
    }

    /// Hold: the TV auto-repeats between keyDown and keyUp (verified with DOWN).
    public func keyDown(_ key: NavKey) async throws {
        try await rest("POST", "/v1/FireTV?action=\(key.rawValue)", json: ["keyActionType": "keyDown"])
    }

    /// Retried, because a lost keyUp would leave the key repeating on the TV.
    public func keyUp(_ key: NavKey) async throws {
        try await rest("POST", "/v1/FireTV?action=\(key.rawValue)", json: ["keyActionType": "keyUp"],
                       wakeIfNeeded: false, retries: 3)
    }

    public func media(_ command: MediaCommand) async throws {
        switch command {
        case .playPause:
            try await rest("POST", "/v1/media?action=play")
        case .forward, .rewind:
            let direction = command == .forward ? "forward" : "back"
            try await rest("POST", "/v1/media?action=scan",
                           json: ["direction": direction, "keyAction": ["keyActionType": "keyDown"]])
            try? await Task.sleep(nanoseconds: 150_000_000)
            try await rest("POST", "/v1/media?action=scan",
                           json: ["direction": direction, "keyAction": ["keyActionType": "keyUp"]],
                           wakeIfNeeded: false, retries: 3)
        }
    }

    /// Launches an app by the package ID the device itself reported in `apps()`.
    public func launch(appId: String) async throws {
        guard FireTVApp.isValidAppID(appId) else {
            throw FireTVError.unsupported("Not a valid app ID: \(appId)")
        }
        try await rest("POST", "/v1/FireTV/app/\(appId)")
    }

    public func apps() async throws -> [FireTVApp] {
        let data = try await rest("GET", "/v1/FireTV/appsV2", retries: 1)
        return try JSONDecoder().decode([FireTVApp].self, from: data)
            .filter { $0.isInstalled != false && FireTVApp.isValidAppID($0.appId) }
    }

    public func status() async throws -> DeviceStatus {
        try JSONDecoder().decode(DeviceStatus.self, from: try await rest("GET", "/v1/FireTV/status", retries: 1))
    }

    /// Read-only. With `wakeIfNeeded: false` an idle remote service is reported as unavailable instead of
    /// being started (starting it may switch the TV on through HDMI-CEC).
    public func properties(wakeIfNeeded: Bool = true) async throws -> [String: String] {
        let data = try await rest("GET", "/v1/FireTV/properties", wakeIfNeeded: wakeIfNeeded, retries: 1)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return object.compactMapValues { $0 as? String }
    }

    /// Device serial from the authenticated properties call; only the paired TV answers it with our token.
    public func serialNumber() async throws -> String? {
        try await properties()["dsn"]
    }

    // MARK: Pairing

    /// Shows a PIN on the TV. Trusts the presented Amazon Turnstile root on first use (chain-verified)
    /// and pins it for `verifyPIN`.
    public func requestPIN(clientName: String) async throws {
        trust.beginFirstUse()
        try await rest("POST", "/v1/FireTV/pin/display", json: ["friendlyName": clientName], auth: false)
    }

    /// Diagnostics: runs the first-use trust path with an unauthenticated request (the TV answers 403;
    /// no token is sent, no PIN is shown) and returns the Amazon root that pairing would pin.
    public func probeFirstUseRoot() async throws -> Data? {
        trust.beginFirstUse()
        do {
            try await rest("GET", "/v1/FireTV/status", auth: false)
        } catch FireTVError.unauthorized {
            // expected
        }
        return trust.pinCapturedRoot()
    }

    /// Returns the client token and the pinned root to store with the pairing.
    public func verifyPIN(_ pin: String) async throws -> (token: String, rootCertificate: Data) {
        guard let root = trust.pinCapturedRoot() else {
            throw FireTVError.untrustedCertificate("no verified Amazon root from the PIN request")
        }
        let data = try await rest("POST", "/v1/FireTV/pin/verify", json: ["pin": pin], auth: false)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = object?["description"] as? String, !token.isEmpty else { throw FireTVError.pinRejected }
        return (token, root)
    }

    // MARK: Voice socket

    /// `wss://<tv>:9090/` with the pairing headers, over the same root-pinned TLS as :8080.
    func openVoiceSocket() async throws -> URLSessionWebSocketTask {
        guard let token else { throw FireTVError.notPaired }
        var request = URLRequest(url: URL(string: "wss://\(host):9090/")!)
        request.setValue(Self.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(token, forHTTPHeaderField: "x-client-token")
        request.timeoutInterval = 10
        let task = session.webSocketTask(with: request)
        try await trust.waitUntilOpen(task, timeout: 5)
        return task
    }

    // MARK: DIAL

    /// Is the TV reachable on this network? A read-only DIAL status request: it never starts the remote
    /// service, so it can't switch the TV on.
    public func isReachable(timeout: Double = 2) async -> Bool {
        (try? await dial("GET", timeout: timeout)) != nil
    }

    /// Read-only: "running" / "stopped". Not a reliable liveness signal (seen "stopped" while :8080 served).
    public func dialState() async throws -> String {
        let (data, _) = try await dial("GET")
        let xml = String(decoding: data, as: UTF8.self)
        guard let start = xml.range(of: "<state>"),
              let end = xml.range(of: "</state>", range: start.upperBound..<xml.endIndex) else { return "unknown" }
        return String(xml[start.upperBound..<end.lowerBound])
    }

    /// Starts the remote service. May switch the TV on through HDMI-CEC.
    public func wake() async throws {
        let (_, response) = try await dial("POST")
        guard let http = response as? HTTPURLResponse, [200, 201].contains(http.statusCode) else {
            throw FireTVError.serviceUnavailable
        }
        log.notice("DIAL wake sent")
    }

    private func dial(_ method: String, timeout: Double = 6) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: "http://\(host):8009/apps/FireTVRemote")!)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if method == "POST" {
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data()
        }
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw FireTVError.network(error.localizedDescription)
        }
    }

    // MARK: Transport

    @discardableResult
    func rest(_ method: String, _ path: String, json: [String: Any]? = nil, auth: Bool = true,
              wakeIfNeeded: Bool = true, retries: Int = 0) async throws -> Data {
        if auth && token == nil { throw FireTVError.notPaired }
        var request = URLRequest(url: URL(string: "https://\(host):8080\(path)")!)
        request.httpMethod = method
        request.setValue(Self.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if auth, let token { request.setValue(token, forHTTPHeaderField: "x-client-token") }
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if method == "POST" {
            request.httpBody = Data()
        }

        var attempt = 0
        while true {
            do {
                return try await send(request)
            } catch FireTVError.serviceUnavailable where wakeIfNeeded {
                // The service stops when idle; DIAL start, then it listens again after ~2-4 s.
                try await wake()
                for _ in 0..<15 {
                    try await Task.sleep(nanoseconds: 700_000_000)
                    do { return try await send(request) } catch FireTVError.serviceUnavailable { continue }
                }
                throw FireTVError.serviceUnavailable
            } catch FireTVError.network(let why) where attempt < retries {
                // e.g. macOS Internet Sharing rebuilding its network for a few seconds
                attempt += 1
                log.notice("retrying \(path, privacy: .private) after network error: \(why, privacy: .public)")
                try await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if let why = trust.takeFailure() { throw FireTVError.untrustedCertificate(why) }
            if error.code == .cannotConnectToHost { throw FireTVError.serviceUnavailable }
            throw FireTVError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw FireTVError.network("no HTTP response") }
        switch http.statusCode {
        case 200..<300: return data
        case 403: throw FireTVError.unauthorized
        default: throw FireTVError.http(http.statusCode, String(decoding: data.prefix(200), as: UTF8.self))
        }
    }
}
