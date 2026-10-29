import CryptoKit
import Foundation
import Security

/// TLS trust for the Fire TV REST service.
///
/// The device presents leaf -> "Turnstile Server Subordinate - 5" -> "Turnstile Server" (Amazon Lab 126).
/// The leaf is re-issued (observed right after pairing), so pinning the leaf breaks; instead the root is
/// pinned and the whole chain must verify to it during the handshake, before any request or token is sent.
final class RootPinningDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var pinnedRoot: SecCertificate?
    private var allowFirstUse = false
    private var capturedRoot: Data?
    private var failure: String?

    init(pinnedRootDER: Data?) {
        pinnedRoot = pinnedRootDER.flatMap { SecCertificateCreateWithData(nil, $0 as CFData) }
    }

    /// Pairing only: trust the root the device presents if it is the known Amazon "Turnstile Server" CA (by its
    /// SHA-256) and the chain verifies to it. The captured root is then pinned for the rest of the session.
    func beginFirstUse() {
        lock.withLock {
            allowFirstUse = true
            capturedRoot = nil
        }
    }

    func pinCapturedRoot() -> Data? {
        lock.withLock {
            guard let der = capturedRoot else { return nil }
            pinnedRoot = SecCertificateCreateWithData(nil, der as CFData)
            allowFirstUse = false
            return der
        }
    }

    func takeFailure() -> String? {
        lock.withLock {
            defer { failure = nil }
            return failure
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if evaluate(trust) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func evaluate(_ trust: SecTrust) -> Bool {
        let presented = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        let (anchor, firstUse): (SecCertificate?, Bool) = lock.withLock {
            if let pinnedRoot { return (pinnedRoot, false) }
            if allowFirstUse, let root = presented.last, Self.isTurnstileRoot(root) { return (root, true) }
            return (nil, false)
        }
        guard let anchor else {
            let unknown = lock.withLock { allowFirstUse } ? presented.last.map { SecCertificateCopyData($0) as Data } : nil
            record(unknown.map { "the TV's certificate isn't the known Amazon Fire TV root (SHA-256 \(Self.sha256($0).prefix(16))…), so pairing stopped" }
                   ?? "no pinned Amazon root for this device")
            return false
        }
        // The leaf carries no host name or IP; the device's identity is the pinned root.
        SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
        SecTrustSetAnchorCertificates(trust, [anchor] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            record("certificate chain does not verify to the pinned Amazon root"
                   + (error.map { " (\(CFErrorCopyDescription($0) as String))" } ?? ""))
            return false
        }
        if firstUse {
            lock.withLock { capturedRoot = SecCertificateCopyData(anchor) as Data }
        }
        return true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    private func record(_ message: String) {
        lock.withLock { failure = message }
    }

    // MARK: WebSocket open/close signalling (voice relay)

    private var opening: [Int: CheckedContinuation<Void, Error>] = [:]

    func waitUntilOpen(_ task: URLSessionWebSocketTask, timeout: Double) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock { opening[task.taskIdentifier] = continuation }
            task.resume()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                // only a socket that never opened is cancelled here
                if self?.resolveOpen(task.taskIdentifier, with: FireTVError.network("voice socket did not open")) == true {
                    task.cancel()
                }
            }
        }
    }

    @discardableResult
    private func resolveOpen(_ id: Int, with error: Error?) -> Bool {
        guard let continuation = lock.withLock({ opening.removeValue(forKey: id) }) else { return false }
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        return true
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        resolveOpen(webSocketTask.taskIdentifier, with: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // ordinary REST tasks report their own errors in FireTVClient.send
        guard lock.withLock({ opening[task.taskIdentifier] != nil }) else { return }
        let why = takeFailure()
        resolveOpen(task.taskIdentifier, with: why.map { FireTVError.untrustedCertificate($0) }
                    ?? error ?? FireTVError.network("voice socket closed"))
    }

    /// SHA-256 (DER) of Amazon's "Turnstile Server" root presented by Fire TV's remote service, observed on a
    /// Fire TV Stick (3rd Gen) with Fire OS 7.7.1.7. A host on the network that merely uses the same name can't
    /// become the pinned root. A device with a different Amazon root is refused until its root is verified
    /// and added here.
    static let knownTurnstileRoots: Set<String> = ["42e4e4644c5c58a034a8c34ecb764157f2c7704828b44a5c8750196a42b9967a"]

    static func isTurnstileRoot(_ certificate: SecCertificate) -> Bool {
        (SecCertificateCopySubjectSummary(certificate) as String?) == "Turnstile Server"
            && knownTurnstileRoots.contains(sha256(SecCertificateCopyData(certificate) as Data))
    }

    static func sha256(_ der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }
}

extension PairedDevice {
    /// SHA-256 of the pinned root certificate (DER), for display.
    public var rootFingerprint: String { RootPinningDelegate.sha256(rootCertificate) }
}
