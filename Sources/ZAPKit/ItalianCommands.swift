import Foundation

/// Result of turning a spoken Italian phrase into a remote action.
public enum VoiceIntent: Sendable, Equatable {
    /// A verified action (possibly repeated, e.g. "destra tre volte").
    case action(RemoteAction, times: Int)
    /// Understood, but deliberately not executed (e.g. channel switching not yet verified).
    case unsupported(String)
    /// Not a known command. Nothing is sent.
    case unknown
}

/// Maps Italian commands to remote actions. The whole phrase must be a known command (after dropping
/// filler words), so partial matches never trigger a guessed action.
public enum ItalianCommands {
    static let phrases: [(String, String)] = [
        ("in alto", "su"), ("in basso", "giu"), ("verso l alto", "su"), ("verso il basso", "giu"),
        ("schermata principale", "home"), ("schermata iniziale", "home"), ("pagina iniziale", "home"),
        ("torna indietro", "indietro"), ("metti in pausa", "pausa"), ("max player", "maxplayer"),
        ("you tube", "youtube"), ("rai play", "raiplay"), ("per favore", ""),
    ]
    static let fillers: Set<String> = [
        "vai", "va", "a", "ad", "al", "alla", "allo", "verso", "la", "il", "lo", "l", "ora", "adesso",
        "dai", "e", "torna", "metti", "sul", "sulla", "fire", "tv", "firetv", "per", "favore", "perfavore",
        "volte", "volta",
    ]
    static let counts: [String: Int] = [
        "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6, "sette": 7, "otto": 8, "nove": 9,
        "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
    ]
    static let words: [String: RemoteAction] = [
        "home": .key(.home), "casa": .key(.home),
        "indietro": .key(.back), "back": .key(.back),
        "conferma": .key(.select), "ok": .key(.select), "okay": .key(.select), "seleziona": .key(.select),
        "invio": .key(.select), "scegli": .key(.select),
        "menu": .key(.menu), "opzioni": .key(.menu),
        "destra": .key(.right), "sinistra": .key(.left),
        "su": .key(.up), "sopra": .key(.up), "sali": .key(.up),
        "giu": .key(.down), "sotto": .key(.down), "scendi": .key(.down),
        // The Fire TV API only has a play/pause toggle, so both words send the same toggle.
        "pausa": .media(.playPause), "riprendi": .media(.playPause), "play": .media(.playPause),
        "riproduci": .media(.playPause), "continua": .media(.playPause),
    ]
    static let launchVerbs: Set<String> = ["apri", "avvia", "lancia", "apriamo"]

    public static func parse(_ utterance: String, apps: [FireTVApp]) -> VoiceIntent {
        var text = " " + normalizedText(utterance) + " "
        for (from, to) in phrases { text = text.replacingOccurrences(of: " \(from) ", with: " \(to) ") }
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return .unknown }

        if tokens.contains("canale") || tokens.contains("canali") {
            return .unsupported("Channel switching in MaxPlayer is not verified yet")
        }
        if tokens.contains(where: { ["volume", "alza", "abbassa", "muto"].contains($0) }) {
            return .unsupported("Volume can't be controlled over the network on this Fire TV")
        }

        if let verb = tokens.firstIndex(where: launchVerbs.contains) {
            let name = tokens[(verb + 1)...].filter { !fillers.contains($0) }.joined(separator: " ")
            guard !name.isEmpty else { return .unknown }
            if apps.isEmpty { return .unsupported("The Fire TV app list hasn't been loaded yet") }
            guard let app = apps.matching(name).first else { return .unsupported("No installed app named “\(name)”") }
            return .action(.launch(appId: app.appId, name: app.name), times: 1)
        }
        if tokens == ["maxplayer"], let app = apps.maxPlayer {
            return .action(.launch(appId: app.appId, name: app.name), times: 1)
        }

        var action: RemoteAction?
        var times = 1
        for token in tokens where !fillers.contains(token) {
            if let n = counts[token] {
                times = n
            } else if let a = words[token], action == nil || action == a {
                action = a
            } else {
                return .unknown  // an extra or conflicting word: don't guess
            }
        }
        guard let action else { return .unknown }
        if case .media = action { times = 1 }
        return .action(action, times: times)
    }
}
