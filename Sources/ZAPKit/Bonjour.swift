import Foundation
import Network
import os

public struct BonjourService: Hashable, Sendable {
    public let name: String
    public let type: String
    public let interface: String?
}

/// A Fire TV found on the local network. `id` and `name` come from its Bonjour TXT record
/// (keys "u" and "n"); neither is trusted for security — pairing and TLS do that.
public struct DiscoveredTV: Hashable, Sendable, Identifiable {
    public let deviceID: String?
    public let name: String
    public let services: [BonjourService]
    public var id: String { deviceID ?? name }
}

public enum Bonjour {
    /// Fire TVs advertise Amazon Whisperplay; AirPlay receivers advertise `_airplay._tcp`.
    public static let fireTVType = "_amzn-wplay._tcp"
    public static let airPlayType = "_airplay._tcp"

    /// State touched only on the private serial queue of one browse/resolve call.
    /// macOS refused Bonjour because Local Network access is off (DNS-SD "policy denied", -65570), so the app can
    /// explain it instead of reporting "not found".
    public static var localNetworkDenied: Bool { denied.withLock { $0 } }
    private static let denied = OSAllocatedUnfairLock(initialState: false)

    private static func watchPermission(_ browser: NWBrowser) {
        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                denied.withLock { $0 = false }
            case .waiting(let error), .failed(let error):
                if case .dns(let code) = error, code == -65570 { denied.withLock { $0 = true } }
            default:
                break
            }
        }
    }

    private final class QueueState<Value>: @unchecked Sendable {
        var value: Value
        var finished = false
        init(_ value: Value) { self.value = value }
    }

    /// Browses for `seconds` and returns every service seen.
    public static func browse(_ type: String, seconds: Double) async -> [BonjourService] {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "zap.bonjour")
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: NWParameters())
            let state = QueueState(Set<BonjourService>())
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    if case let .service(name, serviceType, _, interface) = result.endpoint {
                        state.value.insert(BonjourService(name: name, type: serviceType, interface: interface?.name))
                    }
                }
            }
            watchPermission(browser)
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + seconds) {
                browser.cancel()
                continuation.resume(returning: state.value.sorted { $0.name < $1.name })
            }
        }
    }

    /// Fire TVs on the network, one entry per device (a TV can advertise several instances).
    public static func discoverFireTVs(seconds: Double) async -> [DiscoveredTV] {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "zap.discover")
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: fireTVType, domain: nil), using: NWParameters())
            let state = QueueState([String: (id: String?, name: String, services: [BonjourService])]())
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    guard case let .service(serviceName, serviceType, _, interface) = result.endpoint else { continue }
                    var deviceID: String?
                    var friendly: String?
                    if case let .bonjour(txt) = result.metadata {
                        deviceID = txt["u"].flatMap { $0.isEmpty ? nil : $0 }
                        friendly = txt["n"].flatMap { $0.isEmpty ? nil : $0 }
                    }
                    let key = deviceID ?? serviceName
                    let service = BonjourService(name: serviceName, type: serviceType, interface: interface?.name)
                    var entry = state.value[key] ?? (deviceID, friendly ?? "Fire TV", [])
                    if !entry.services.contains(service) { entry.services.append(service) }
                    state.value[key] = entry
                }
            }
            watchPermission(browser)
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + seconds) {
                browser.cancel()
                let tvs = state.value.values.map { DiscoveredTV(deviceID: $0.id, name: $0.name, services: $0.services) }
                continuation.resume(returning: tvs.sorted { $0.name < $1.name })
            }
        }
    }

    /// First IPv4 address any of the TV's services resolves to.
    public static func resolveIPv4(_ tv: DiscoveredTV) async -> String? {
        for service in tv.services {
            if let address = await resolveIPv4(service) { return address }
        }
        return nil
    }

    /// Resolves a service to its IPv4 address by opening (and immediately closing) a TCP connection.
    public static func resolveIPv4(_ service: BonjourService, timeout: Double = 3) async -> String? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "zap.resolve")
            let parameters = NWParameters.tcp
            if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.version = .v4
            }
            let connection = NWConnection(to: .service(name: service.name, type: service.type,
                                                       domain: "local.", interface: nil),
                                          using: parameters)
            let state = QueueState<String?>(nil)
            let finish: @Sendable (String?) -> Void = { address in
                guard !state.finished else { return }
                state.finished = true
                connection.cancel()
                continuation.resume(returning: address)
            }
            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint,
                       case let .ipv4(address) = host {
                        finish(address.rawValue.map(String.init).joined(separator: "."))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}
