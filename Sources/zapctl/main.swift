import AVFoundation
import Foundation
import ZAPKit

// Developer CLI over ZAPKit (the same code the app uses). Reads the app's pairing store.
// It is not part of the distributed app.
//   zapctl status | apps | dial | bench [n] | trust-check | discover | browse <_type._tcp> [secs]
//   zapctl parse "<frase>" …
//   zapctl key <up|down|left|right|select|home|back|menu> | hold <key> <secs>
//   zapctl media <playPause|forward|rewind> | launch <appId> | voice-file <audio file>
// Commands in the last two lines act on the TV: run them only with someone watching it.

let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func ms(since start: Date) -> String { String(format: "%4.0f ms", Date().timeIntervalSince(start) * 1000) }

func client() -> FireTVClient {
    PairingStore.migrateLegacyStoreIfNeeded()
    guard let device = PairingStore.load() else { fail("not paired: pair in the to.zap app first") }
    return FireTVClient(device: device)
}

func key(_ name: String) -> NavKey {
    guard let key = NavKey.allCases.first(where: { $0.label.lowercased() == name.lowercased() }) else {
        fail("unknown key \(name)")
    }
    return key
}

guard let command = args.first else { fail("usage: see the header of Sources/zapctl/main.swift") }

do {
    switch command {
    case "status":
        let start = Date()
        let status = try await client().status()
        print("status \(ms(since: start)): os \(status.osVersion ?? "?") turnstile \(status.turnstileVersion ?? "?")")

    case "apps":
        let apps = try await client().apps()
        PairingStore.saveApps(apps)
        for app in apps { print(app.appId.padding(toLength: 34, withPad: " ", startingAt: 0), app.name.prefix(60)) }
        print("MaxPlayer ->", apps.maxPlayer?.appId ?? "not installed")

    case "dial":
        let c = client()
        print("reachable:", await c.isReachable(), "| DIAL state:", (try? await c.dialState()) ?? "-")

    case "bench":
        let n = args.count > 1 ? Int(args[1]) ?? 5 : 5
        let c = client()
        for i in 1...n {
            let start = Date()
            _ = try await c.status()
            print("GET status #\(i): \(ms(since: start))")
        }

    case "trust-check":
        // The pairing path: capture the presented Amazon root on first use (no token sent, no PIN shown).
        guard let device = PairingStore.load() else { fail("not paired") }
        let probe = FireTVClient(host: device.host, token: nil, pinnedRoot: nil)
        guard let root = try await probe.probeFirstUseRoot() else { fail("no root captured") }
        let captured = PairedDevice(host: device.host, token: "", rootCertificate: root, deviceName: nil,
                                    clientName: "", pairedAt: Date())
        print(captured.rootFingerprint == device.rootFingerprint ? "first-use root MATCHES the pinned root"
              : "first-use root DIFFERS from the pinned root")

    case "parse":
        let apps = PairingStore.loadApps()
        for phrase in args.dropFirst() { print("«\(phrase)» ->", ItalianCommands.parse(phrase, apps: apps)) }

    case "browse":
        let type = args.count > 1 ? args[1] : Bonjour.airPlayType
        let seconds = args.count > 2 ? Double(args[2]) ?? 4 : 4
        for service in await Bonjour.browse(type, seconds: seconds) { print(service.name, "|", service.type) }

    case "discover":
        for tv in await Bonjour.discoverFireTVs(seconds: 4) {
            print(tv.name, "| id", tv.deviceID == nil ? "-" : "present", "|", await Bonjour.resolveIPv4(tv) ?? "unresolved")
        }

    case "key":
        guard args.count >= 2 else { fail("key <name>") }
        let start = Date()
        try await client().press(key(args[1]))
        print("\(args[1]): \(ms(since: start))")

    case "hold":
        guard args.count == 3, let seconds = Double(args[2]) else { fail("hold <key> <secs>") }
        let c = client()
        try await c.keyDown(key(args[1]))
        try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
        try await c.keyUp(key(args[1]))
        print("held \(args[1]) \(seconds)s")

    case "media":
        guard args.count == 2, let m = MediaCommand(rawValue: args[1]) else { fail("media <playPause|forward|rewind>") }
        try await client().media(m)
        print(m.label)

    case "probe":
        // Undocumented-action testing, only with someone watching the TV: probe POST "/v1/media?action=next"
        guard args.count >= 3 else { fail("probe <GET|POST> </v1/path> [json]") }
        let json = args.count > 3 ? (try? JSONSerialization.jsonObject(with: Data(args[3].utf8))) as? [String: Any] : nil
        let (status, body) = await client().probe(args[1], args[2], json: json)
        print("\(args[1]) \(args[2]) → \(status.map(String.init) ?? "no HTTP answer") \(body)")

    case "launch":
        guard args.count == 2 else { fail("launch <appId>") }
        try await client().launch(appId: args[1])
        print("launched \(args[1])")

    case "voice-file":
        // Streams an audio file to Alexa through the Fire TV, paced at real time, like push-to-talk.
        guard args.count == 2 else { fail("voice-file <audio file>") }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[1]))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else { fail("bad audio") }
        try file.read(into: buffer)
        let pcm = PCM16kConverter().convert(buffer)
        let relay = AlexaVoiceRelay(client: client())
        try await relay.open()
        var offset = 0
        while offset < pcm.count {
            let end = min(offset + AlexaVoiceRelay.frameBytes, pcm.count)
            relay.append(pcm.subdata(in: offset..<end))
            offset = end
            if let error = relay.failure { await relay.abort(); throw error }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        await relay.finish()
        print("streamed \(Double(pcm.count) / 32000) s")

    default:
        fail("unknown command \(command)")
    }
} catch {
    fail("error: \(error.localizedDescription)")
}
