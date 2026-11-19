import SwiftUI
import AppKit

struct RegiaApp: App {
    @StateObject private var stato = Stato(motore: Motore(prova: ProcessInfo.processInfo.environment["REGIA_PROVA"] == "1"))

    var body: some Scene {
        WindowGroup("Regia") {
            FinestraPrincipale()
                .environmentObject(stato)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowToolbarStyle(.unified)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

// MARK: - Comandi da Terminale

/// `Regia --analisi`: stampa lo stato del Mac senza cambiare niente.
func analisiTestuale() {
    let m = Motore(prova: false)
    let p = Analisi.panoramica()
    print("== \(p.modello) · \(p.chip) · \(p.sistema)")
    print("Disco libero: \(formatoByte(p.discoLibero)) su \(formatoByte(p.discoTotale)) (\(Int(p.percentoDiscoLibero * 100))%)")
    print("Memoria: \(Int(p.memoriaGB.rounded())) GB, libera \(p.memoriaLibera.map { "\($0)%" } ?? "?")")
    print("Batteria: salute \(p.batteriaSalute.map { "\($0)%" } ?? "?"), cicli \(p.batteriaCicli ?? 0), carica \(p.batteriaPercento ?? 0)%")
    print("Acceso da: \(p.acceso)")
    print("Più CPU: " + p.processiCPU.prefix(3).map { "\($0.nome) \(Int($0.cpu))%" }.joined(separator: ", "))
    print("Più memoria: " + p.processiMemoria.prefix(3).map { "\($0.nome) \(Int($0.memoriaMB)) MB" }.joined(separator: ", "))
    print("\n== Pulizia")
    var totale: Int64 = 0
    for var z in Pulizia.zone() where !z.suRichiesta {
        Pulizia.calcola(&z); totale += z.dimensione
        print("\(z.titolo): \(formatoByte(z.dimensione)) (\(z.elementi.count) elementi)")
    }
    print("\n== Avvio")
    let av = m.elementiAvvio()
    for e in av { print("[\(e.livello.nome)] \(e.nome)") }
    print("\n== Ritocchi")
    let e = m.leggiEnergia()
    for t in Catalogo.ritocchi {
        let s = m.statoAttuale(t, energia: e)
        print("\(s.attivo ? "✓" : "·") \(t.titolo) — ora: \(s.testo)")
    }
    print("\n== Consigli")
    for c in Analisi.consigli(p, pulibile: totale, avvioUtente: av.filter { $0.livello == .utente }.count) {
        print("- \(c.titolo): \(c.dettaglio)")
    }
}

/// `Regia --autotest`: prova tutto in un'area finta. Il Mac vero non viene toccato.
func autotest() -> Bool {
    var ok = true
    func verifica(_ c: Bool, _ s: String) { print(c ? "OK   \(s)" : "ERR  \(s)"); if !c { ok = false } }
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("RegiaAutotest-\(UUID().uuidString.prefix(8))")
    try? fm.createDirectory(at: base, withIntermediateDirectories: true)
    let m = Motore(prova: true, cartellaProva: base)
    let domini = Set(Catalogo.ritocchi.compactMap { t -> String? in if case .preferenza(let d, _, _) = t.azione { return d }; return nil })
    func pulisciDomini() { for d in domini { esegui("/usr/bin/defaults", ["delete", m.dominioEffettivo(d)]) } }
    pulisciDomini()

    // Un valore già presente prima di Regia, per vedere che torni identico.
    try? m.scriviPreferenza("com.apple.dock", "autohide-delay", ["-float", "0.5"])
    try? m.scriviPreferenza("com.apple.finder", "ShowPathbar", ["-bool", "false"])

    // 1. Applica tutti i profili insieme
    let ids = Set(Catalogo.profili.flatMap(\.ritocchi))
    let scelti = Catalogo.ritocchi.filter { ids.contains($0.id) }
    let r = m.applica(scelti)
    verifica(r.errori.isEmpty, "applica \(scelti.count) ritocchi senza errori \(r.errori)")
    let e = m.leggiEnergia()
    let nonAttivi = scelti.filter { !m.statoAttuale($0, energia: e).attivo }.map(\.id)
    verifica(nonAttivi.isEmpty, "tutti risultano attivi \(nonAttivi)")
    verifica(m.modifiche.count == scelti.count, "registro modifiche: \(m.modifiche.count) voci")

    // 2. Riapplicare non deve perdere il valore originale
    m.applica(scelti)
    verifica(m.modifica(per: "dock.ritardo0")?.originale == "0.5", "il valore originale resta 0.5 dopo una seconda applicazione")

    // 3. Annulla una sola modifica
    if let x = m.modifica(per: "finder.barraPercorso") { try? m.annulla(x) }
    verifica(m.leggiPreferenza("com.apple.finder", "ShowPathbar").valore == "0", "annulla singolo: barra percorso tornata a no")

    // 4. Annulla tutto
    let err = m.annullaTutto()
    verifica(err.isEmpty, "annulla tutto senza errori \(err)")
    let dopo = m.leggiPreferenza("com.apple.dock", "autohide-delay")
    verifica(dopo.valore == "0.5" && dopo.tipo == "float", "autohide-delay tornato 0.5 (float)")
    verifica(m.leggiPreferenza("com.apple.dock", "autohide").valore == nil, "chiave che non esisteva: rimossa")
    verifica(m.leggiPreferenza("NSGlobalDomain", "KeyRepeat").valore == nil, "KeyRepeat rimosso")
    let e2 = m.leggiEnergia()
    verifica(e2[.batteria]?["lowpowermode"] == 0 && e2[.batteria]?["displaysleep"] == 10 && e2[.alimentatore]?["lowpowermode"] == 1,
             "energia tornata ai valori di prima")
    verifica(m.modifiche.isEmpty, "nessuna modifica rimasta")

    // 5. Avvio
    try? fm.createDirectory(at: m.cartellaAgentiUtente, withIntermediateDirectories: true)
    let agente = m.cartellaAgentiUtente.appendingPathComponent("com.esempio.prova.plist")
    let plist: [String: Any] = ["Label": "com.esempio.prova", "ProgramArguments": ["/usr/bin/true"]]
    try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agente)
    let el = m.elementiAvvio()
    verifica(el.count == 1 && el[0].nome == "com.esempio.prova" && el[0].programma == "/usr/bin/true", "legge l'elemento di avvio")
    try? m.disattivaAvvio(el[0])
    verifica(!fm.fileExists(atPath: agente.path) && m.elementiAvvio().first?.disattivato == true, "disattiva: file messo da parte")
    _ = m.annullaTutto()
    verifica(fm.fileExists(atPath: agente.path) && m.elementiAvvio().first?.disattivato == false, "riattiva: file rimesso a posto")

    // 6. Pulizia
    let cache = base.appendingPathComponent("Library/Caches")
    try? fm.createDirectory(at: cache.appendingPathComponent("com.esempio.app"), withIntermediateDirectories: true)
    try? fm.createDirectory(at: cache.appendingPathComponent("com.apple.Safari"), withIntermediateDirectories: true)
    try? Data(count: 2_000_000).write(to: cache.appendingPathComponent("com.esempio.app/dati.bin"))
    try? Data(count: 1000).write(to: cache.appendingPathComponent("com.apple.Safari/x.bin"))
    var z = Pulizia.zone(base: base)[0]
    Pulizia.calcola(&z)
    verifica(z.elementi.count == 1 && z.dimensione >= 2_000_000, "pulizia: trovata 1 cartella da 2 MB, esclusa quella di Apple")
    let p = Pulizia.spostaNelCestino(z.elementi)
    verifica(p.errori == 0 && !fm.fileExists(atPath: cache.appendingPathComponent("com.esempio.app").path),
             "pulizia: spostata nel Cestino")
    for u in p.spostati { try? fm.removeItem(at: u) }   // togliamo dal Cestino il file di prova
    verifica(fm.fileExists(atPath: cache.appendingPathComponent("com.apple.Safari").path), "pulizia: cache Apple non toccata")

    // 7. Registro
    verifica(m.leggiRegistro().count > 10, "registro scritto (\(m.leggiRegistro().count) righe)")

    pulisciDomini()
    try? fm.removeItem(at: base)
    print(ok ? "\nTUTTO OK" : "\nCI SONO ERRORI")
    return ok
}

// MARK: - Avvio

let argomenti = CommandLine.arguments
if argomenti.contains("--autotest") {
    exit(autotest() ? 0 : 1)
} else if argomenti.contains("--analisi") {
    analisiTestuale()
    exit(0)
} else {
    RegiaApp.main()
}
