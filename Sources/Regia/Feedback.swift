import Foundation

/// Segnalazioni e idee: Regia prepara il testo e apre la pagina "New issue" del progetto su GitHub.
/// Niente viene inviato finché non premi tu "Submit" su GitHub.
enum Feedback {
    static let progetto = "https://github.com/sm-bc/regia-mac"

    enum Tipo: String, CaseIterable, Identifiable {
        case problema, idea, domanda
        var id: String { rawValue }
        var nome: String {
            switch self {
            case .problema: return L("Bug report", "Problema")
            case .idea: return L("Idea or request", "Idea o richiesta")
            case .domanda: return L("Question", "Domanda")
            }
        }
        var icona: String {
            switch self {
            case .problema: return "ladybug"
            case .idea: return "lightbulb"
            case .domanda: return "questionmark.bubble"
            }
        }
        /// Sempre in inglese: così le segnalazioni si ordinano facilmente su GitHub.
        var prefisso: String {
            switch self {
            case .problema: return "[Bug]"
            case .idea: return "[Idea]"
            case .domanda: return "[Question]"
            }
        }
    }

    /// Informazioni tecniche, senza dati personali: versione di Regia e di macOS, modello, lingua.
    static func infoSistema(_ p: Panoramica?) -> String {
        var righe = ["Regia \(Aggiornamenti.versioneAttuale)", "macOS \(AggiornamentiApp.versioneSistema())"]
        if let p, !p.modello.isEmpty { righe.append([p.modello, p.chip].filter { !$0.isEmpty }.joined(separator: " · ")) }
        righe.append("Language: \(Lingua.attuale.nome)")
        return righe.map { "- " + $0 }.joined(separator: "\n")
    }

    /// Ultime righe del registro con la cartella Inizio sostituita da "~" (niente nome utente).
    static func registroAnonimo(_ righe: [String], quante: Int = 15) -> String {
        righe.prefix(quante).reversed()
            .map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
            .joined(separator: "\n")
    }

    static func corpo(tipo: Tipo, testo: String, info: String?, registro: String?) -> String {
        var c = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.isEmpty { c = "_(no description)_" }
        if let i = info { c += "\n\n---\n**System**\n\(i)" }
        if let r = registro, !r.isEmpty {
            c += "\n\n<details><summary>Log</summary>\n\n```\n\(r)\n```\n</details>"
        }
        return c
    }

    /// Indirizzo della pagina GitHub con titolo e testo già compilati (testo accorciato se troppo lungo per un link).
    static func url(tipo: Tipo, titolo: String, corpo: String) -> URL? {
        let t = titolo.trimmingCharacters(in: .whitespacesAndNewlines)
        var c = URLComponents(string: progetto + "/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: "\(tipo.prefisso) \(t.isEmpty ? tipo.nome : t)"),
                        URLQueryItem(name: "body", value: String(corpo.prefix(6000)))]
        return c.url
    }
}
