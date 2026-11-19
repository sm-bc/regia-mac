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
    print("\n== Residui di app cancellate")
    for r in Residui.orfani(home: m.home, simulazione: false) {
        print("\(r.delicato ? "[dati] " : "")\(r.app) · \(r.tipo.rawValue) · \(formatoByte(r.dimensione)) · \(r.percorso.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
    }
    print("\n== App installate")
    let lista = AppInstallate.elenco(home: m.home, simulazione: false)
    print("\(lista.count) app, \(lista.filter { $0.protetta }.count) protette")
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

    // 7. Riporta al predefinito (e poi Annulla)
    try? m.scriviPreferenza("com.apple.dock", "autohide", ["-bool", "true"])
    let massimo = Catalogo.ritocchi
    let rp = m.applica(massimo, predefinito: true)
    verifica(rp.errori.isEmpty, "predefinito senza errori \(rp.errori)")
    verifica(m.leggiPreferenza("com.apple.dock", "autohide").valore == nil, "predefinito: autohide tolto")
    verifica(m.leggiPreferenza("com.apple.dock", "autohide-delay").valore == nil, "predefinito: autohide-delay tolto")
    let ep = m.leggiEnergia()
    verifica(ep[.alimentatore]?["lowpowermode"] == 0 && ep[.batteria]?["powernap"] == 1 && ep[.batteria]?["displaysleep"] == 10,
             "predefinito energia: risparmio spento, Power Nap acceso, schermo non toccato")
    _ = m.annullaTutto()
    verifica(m.leggiPreferenza("com.apple.dock", "autohide").valore == "1" && m.leggiPreferenza("com.apple.dock", "autohide-delay").valore == "0.5",
             "annulla dopo predefinito: valori di prima tornati")
    verifica(m.leggiEnergia()[.alimentatore]?["lowpowermode"] == 1, "annulla dopo predefinito: energia tornata")

    // 8. Profili personali
    try? m.salvaProfilo(nome: "Ufficio", ritocchi: ["finder.estensioni", "dock.noRecenti"])
    try? m.salvaProfilo(nome: "ufficio", ritocchi: ["finder.estensioni"])
    let pp = m.profiliPersonali()
    verifica(pp.count == 1 && pp[0].ritocchi == ["finder.estensioni"] && pp[0].personale, "profilo personale salvato (stesso nome sostituito)")
    m.eliminaProfilo(pp[0])
    verifica(m.profiliPersonali().isEmpty, "profilo personale eliminato")

    // 9. App installate e residui
    let lib = base.appendingPathComponent("Library")
    func crea(_ rel: String, _ byte: Int = 1000) {
        let u = base.appendingPathComponent(rel)
        try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(count: byte).write(to: u)
    }
    let infoApp = base.appendingPathComponent("Applications/Esempio.app/Contents/Info.plist")
    try? fm.createDirectory(at: infoApp.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.esempio.installata", "CFBundleShortVersionString": "2.1"],
                                        format: .xml, options: 0).write(to: infoApp)
    let infoDis = base.appendingPathComponent("Applications/Disinstalla Esempio.app/Contents/Info.plist")
    try? fm.createDirectory(at: infoDis.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.esempio.disinstallatore"], format: .xml, options: 0).write(to: infoDis)
    crea("Library/Preferences/com.esempio.installata.plist")
    crea("Library/Caches/com.esempio.installata/c.bin", 5000)
    crea("Library/Application Support/Esempio/dati.db")
    crea("Library/Preferences/com.vecchiaditta.cancellata.plist")
    crea("Library/Caches/com.vecchiaditta.cancellata/c.bin", 3000)
    crea("Library/Application Support/com.vecchiaditta.cancellata/doc.txt")
    crea("Library/Preferences/com.apple.finder.plist")
    let orfano = lib.appendingPathComponent("LaunchAgents/com.esempio.vecchio.plist")
    try? PropertyListSerialization.data(fromPropertyList: ["Label": "com.esempio.vecchio", "Program": "/Applications/NonEsiste.app/Contents/MacOS/x"],
                                        format: .xml, options: 0).write(to: orfano)
    let elencoApp = AppInstallate.elenco(home: base, simulazione: true)
    verifica(elencoApp.count == 2 && elencoApp.contains { $0.bundleID == "com.esempio.installata" && $0.versione == "2.1" }, "elenco app: trovate 2 app")
    if let app = elencoApp.first(where: { $0.bundleID == "com.esempio.installata" }) {
        let res = Residui.trova(bundleID: app.bundleID, nome: app.nome, home: base)
        verifica(res.count == 3, "residui dell'app installata: preferenze, cache e cartella col nome (\(res.count))")
        verifica(res.first { $0.tipo == .supporto }?.delicato == true, "cartella dati segnata come delicata")
        verifica(AppInstallate.disinstallatore(per: app, tra: elencoApp)?.nome == "Disinstalla Esempio", "riconosce il programma di disinstallazione")
    }
    let orf = Residui.orfani(home: base, simulazione: true)
    let percorsiOrf = Set(orf.map { $0.percorso.lastPathComponent })
    verifica(percorsiOrf == ["com.esempio.vecchio.plist", "com.vecchiaditta.cancellata.plist", "com.vecchiaditta.cancellata"] && orf.count == 4,
             "orfani: avvio rotto + 3 file dell'app cancellata, niente di Apple o installato (\(orf.count))")
    for r in orf { try? m.mettiDaParte(r) }
    verifica(!fm.fileExists(atPath: orfano.path) && Residui.orfani(home: base, simulazione: true).isEmpty, "orfani messi da parte")
    _ = m.annullaTutto()
    verifica(fm.fileExists(atPath: orfano.path) && Residui.orfani(home: base, simulazione: true).count == 4, "annulla: orfani rimessi al loro posto")

    // 10. Latenza e tempo reale
    let pg = Manutenzione.analizzaPing("Router", "192.168.1.1",
        "10 packets transmitted, 9 packets received, 10.0% packet loss\nround-trip min/avg/max/stddev = 4.107/7.021/8.657/2.066 ms")
    verifica(pg.media == 7.021 && pg.persi == 10 && Manutenzione.giudizio(pg).contains("persi 10%"), "latenza: lettura del ping")
    verifica(Manutenzione.giudizio(Manutenzione.analizzaPing("DNS", "x", "100.0% packet loss")).contains("nessuna risposta"), "latenza: nessuna risposta")
    let dest = Manutenzione.destinazioniPing()
    verifica(dest.allSatisfy { $0.1.split(separator: ".").count == 4 }, "latenza: indirizzi letti bene \(dest.map { $0.1 })")
    let mis = Misuratore()
    _ = mis.campione(); Thread.sleep(forTimeInterval: 0.5)
    let c = mis.campione()
    verifica(c.cpu >= 0 && c.cpu <= 100 && c.memoriaUsataGB > 0.5 && c.memoriaTotaleGB > 1, String(format: "tempo reale: CPU %.0f%%, memoria %.1f GB", c.cpu, c.memoriaUsataGB))

    // 11. Aggiornamenti (tutto in locale, GitHub non viene toccato)
    verifica(Aggiornamenti.piuNuova("2.10", di: "2.9") && Aggiornamenti.piuNuova("3", di: "2.9.9") && !Aggiornamenti.piuNuova("2.1", di: "2.1.0")
             && !Aggiornamenti.piuNuova("2.0", di: "2.1"), "aggiornamenti: confronto delle versioni")
    let gh = "https://raw.githubusercontent.com/sm-bc/regia-mac/main/versione.json"
    verifica(Aggiornamenti.fidato(versione: gh, pacchetto: "https://github.com/sm-bc/regia-mac/releases/download/v2.1/Regia-Mac_2.1.zip")
             && !Aggiornamenti.fidato(versione: gh, pacchetto: "https://sito-strano.example/Regia.zip")
             && !Aggiornamenti.fidato(versione: gh, pacchetto: "http://github.com/x.zip")
             && !Aggiornamenti.fidato(versione: gh, pacchetto: "file:///tmp/x.zip"), "aggiornamenti: solo pacchetti https da GitHub")
    func creaApp(_ dove: URL, versione: String, id: String = Aggiornamenti.identificativo) {
        let c = dove.appendingPathComponent("Contents")
        try? fm.createDirectory(at: c.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try? PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleShortVersionString": versione,
                                                               "CFBundleExecutable": "Regia", "CFBundlePackageType": "APPL"],
                                            format: .xml, options: 0).write(to: c.appendingPathComponent("Info.plist"))
        try? "#!/bin/sh\necho \(versione)\n".write(to: c.appendingPathComponent("MacOS/Regia"), atomically: true, encoding: .utf8)
        esegui("/bin/chmod", ["+x", c.appendingPathComponent("MacOS/Regia").path])
        esegui("/usr/bin/codesign", ["--force", "--sign", "-", dove.path])
    }
    func versioneDi(_ app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }
    let agg = base.appendingPathComponent("Aggiornamento")
    let installata = agg.appendingPathComponent("Installata/Regia.app")
    creaApp(installata, versione: "2.0")
    creaApp(agg.appendingPathComponent("Nuova/Regia.app"), versione: "9.9")
    let zipNuovo = agg.appendingPathComponent("Regia-Mac_9.9.zip")
    esegui("/usr/bin/ditto", ["-c", "-k", "--keepParent", agg.appendingPathComponent("Nuova/Regia.app").path, zipNuovo.path])
    let sha = (try? Aggiornamenti.sha256(zipNuovo)) ?? ""
    let fileVersione = agg.appendingPathComponent("versione.json")
    func scriviVersione(_ i: Aggiornamenti.Info) { try? JSONEncoder().encode(i).write(to: fileVersione) }
    let versioni = agg.appendingPathComponent("Versioni")
    func attendi<T>(_ f: @escaping () async throws -> T) -> Result<T, Error> {
        var r: Result<T, Error>!
        let s = DispatchSemaphore(value: 0)
        Task { do { r = .success(try await f()) } catch { r = .failure(error) }; s.signal() }
        s.wait()
        return r
    }
    // impronta sbagliata → niente cambia
    scriviVersione(.init(versione: "9.9", url: zipNuovo.absoluteString, sha256: String(repeating: "a", count: 64), note: "prova"))
    let trovato = attendi { try await Aggiornamenti.controlla(da: fileVersione.absoluteString, attuale: "2.0") }
    verifica((try? trovato.get())??.versione == "9.9", "aggiornamenti: trovata la 9.9")
    verifica((try? attendi { try await Aggiornamenti.controlla(da: fileVersione.absoluteString, attuale: "9.9") }.get()) == .some(nil),
             "aggiornamenti: già aggiornata → niente pulsante")
    if case .success(let info?) = trovato {
        let r1 = attendi { try await Aggiornamenti.installa(info, da: fileVersione.absoluteString, app: installata, cartellaVersioni: versioni) { _ in } }
        verifica((try? r1.get()) == nil && versioneDi(installata) == "2.0", "aggiornamenti: impronta sbagliata → rifiutato, app invariata")
    }
    // identificativo diverso → rifiutato
    creaApp(agg.appendingPathComponent("Falsa/Regia.app"), versione: "9.9", id: "com.altro.app")
    let zipFalso = agg.appendingPathComponent("falso.zip")
    esegui("/usr/bin/ditto", ["-c", "-k", "--keepParent", agg.appendingPathComponent("Falsa/Regia.app").path, zipFalso.path])
    let infoFalsa = Aggiornamenti.Info(versione: "9.9", url: zipFalso.absoluteString, sha256: (try? Aggiornamenti.sha256(zipFalso)) ?? "")
    let r2 = attendi { try await Aggiornamenti.installa(infoFalsa, da: fileVersione.absoluteString, app: installata, cartellaVersioni: versioni) { _ in } }
    verifica((try? r2.get()) == nil && versioneDi(installata) == "2.0", "aggiornamenti: app con identificativo diverso → rifiutata")
    // tutto giusto → installata, vecchia salvata in Versioni
    let buona = Aggiornamenti.Info(versione: "9.9", url: zipNuovo.absoluteString, sha256: sha)
    let r3 = attendi { try await Aggiornamenti.installa(buona, da: fileVersione.absoluteString, app: installata, cartellaVersioni: versioni) { _ in } }
    let salvata = try? r3.get()
    verifica(versioneDi(installata) == "9.9" && salvata.map { versioneDi($0) } == "2.0", "aggiornamenti: installata la 9.9, la 2.0 è in Versioni")
    verifica(esegui("/usr/bin/codesign", ["--verify", "--deep", "--strict", installata.path]).ok, "aggiornamenti: firma dell'app nuova valida")

    // 12. Registro
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
