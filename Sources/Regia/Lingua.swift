import Foundation

/// Lingua dell'interfaccia: inglese di serie, italiano selezionabile (Impostazioni o barra laterale).
enum Lingua: String, CaseIterable, Identifiable {
    case en, it
    var id: String { rawValue }
    var nome: String { self == .en ? "English" : "Italiano" }

    static let chiave = "lingua"
    /// Letta all'avvio dalle preferenze di Regia; cambia subito quando la scegli.
    nonisolated(unsafe) static var attuale: Lingua =
        Lingua(rawValue: UserDefaults.standard.string(forKey: chiave) ?? "") ?? .en

    static func salva(_ l: Lingua) {
        attuale = l
        UserDefaults.standard.set(l.rawValue, forKey: chiave)
    }
}

/// Testo nelle due lingue: prima l'inglese, poi l'italiano.
func L(_ en: String, _ it: String) -> String { Lingua.attuale == .it ? it : en }

/// Numero con decimali nel formato della lingua scelta (1.5 / 1,5).
func decimale(_ v: Double, _ cifre: Int = 1) -> String {
    let s = String(format: "%.\(cifre)f", v)
    return Lingua.attuale == .it ? s.replacingOccurrences(of: ".", with: ",") : s
}

/// Singolare o plurale: `P(n, "update", "updates", "aggiornamento", "aggiornamenti")` → "1 update" / "3 aggiornamenti".
func P(_ n: Int, _ en1: String, _ enN: String, _ it1: String, _ itN: String) -> String {
    "\(n) " + (n == 1 ? L(en1, it1) : L(enN, itN))
}
