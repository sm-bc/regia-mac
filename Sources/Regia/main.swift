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
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button(L("Send Feedback…", "Invia una segnalazione…")) { stato.mostraFeedback = true }
                Button(L("Report a Bug on GitHub", "Segnala un problema su GitHub")) { stato.apri(Feedback.progetto + "/issues") }
                Divider()
                Button(L("Regia on GitHub", "Regia su GitHub")) { stato.apri(Feedback.progetto) }
            }
            CommandMenu(L("Language", "Lingua")) {
                ForEach(Lingua.allCases) { l in
                    Button((stato.lingua == l ? "✓ " : "    ") + l.nome) { stato.cambiaLingua(l) }
                }
            }
        }
        Settings {
            VistaImpostazioni().environmentObject(stato)
        }
    }
}

// MARK: - Comandi da Terminale

/// `Regia --analisi`: stampa lo stato del Mac senza cambiare niente.
func analisiTestuale() {
    let m = Motore(prova: false)
    let p = Analisi.panoramica()
    print("== \(p.modello) · \(p.chip) · \(p.sistema)")
    print(L("Free disk", "Disco libero") + ": \(formatoByte(p.discoLibero)) / \(formatoByte(p.discoTotale)) (\(Int(p.percentoDiscoLibero * 100))%)")
    print(L("Memory", "Memoria") + ": \(Int(p.memoriaGB.rounded())) GB, " + L("free", "libera") + " \(p.memoriaLibera.map { "\($0)%" } ?? "?")")
    print(L("Battery", "Batteria") + ": \(p.batteriaSalute.map { "\($0)%" } ?? "?"), \(p.batteriaCicli ?? 0) " + L("cycles", "cicli") + ", \(p.batteriaPercento ?? 0)%")
    print(L("On for", "Acceso da") + ": \(p.acceso)")
    print(L("Most CPU", "Più CPU") + ": " + p.processiCPU.prefix(3).map { "\($0.nome) \(Int($0.cpu))%" }.joined(separator: ", "))
    print(L("Most memory", "Più memoria") + ": " + p.processiMemoria.prefix(3).map { "\($0.nome) \(Int($0.memoriaMB)) MB" }.joined(separator: ", "))
    print("\n== " + L("Cleanup", "Pulizia"))
    var totale: Int64 = 0
    for var z in Pulizia.zone() where !z.suRichiesta {
        Pulizia.calcola(&z); totale += z.dimensione
        print("\(z.titolo): \(formatoByte(z.dimensione)) (\(z.elementi.count))")
    }
    print("\n== " + L("Startup", "Avvio"))
    let av = m.elementiAvvio()
    for e in av { print("[\(e.livello.nome)] \(e.nome)") }
    print("\n== " + L("Tweaks", "Ritocchi"))
    let e = m.leggiEnergia()
    for t in Catalogo.ritocchi {
        let s = m.statoAttuale(t, energia: e)
        print("\(s.attivo ? "✓" : "·") \(t.titolo) — \(s.testo)")
    }
    print("\n== " + L("Leftovers of deleted apps", "Residui di app cancellate"))
    for r in Residui.orfani(home: m.home, simulazione: false) {
        print("\(r.delicato ? "[" + L("data", "dati") + "] " : "")\(r.app) · \(r.tipo.nome) · \(formatoByte(r.dimensione)) · \(r.percorso.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
    }
    print("\n== " + L("Installed apps", "App installate"))
    let lista = AppInstallate.elenco(home: m.home, simulazione: false)
    print("\(lista.count) app, \(lista.filter { $0.protetta }.count) " + L("protected", "protette"))
    print("\n== " + L("Recommendations", "Consigli"))
    for c in Analisi.consigli(p, pulibile: totale, avvioUtente: av.filter { $0.livello == .utente }.count) {
        print("- \(c.titolo): \(c.dettaglio)")
    }
    print("\n== " + L("Security", "Sicurezza"))
    for c in Suggerimenti.controlli() { print("\(c.livello == .ok ? "✓" : "!") \(c.titolo)") }
}

/// `Regia --aggiornamenti-app`: controlla gli aggiornamenti delle app installate (sola lettura).
func aggiornamentiAppTestuale() {
    let s = DispatchSemaphore(value: 0)
    var r: RisultatoAggiornamentiApp?
    Task {
        let elenco = AppInstallate.elenco(home: FileManager.default.homeDirectoryForCurrentUser, simulazione: false)
        r = await AggiornamentiApp.controlla(elenco)
        s.signal()
    }
    s.wait()
    for v in r?.voci ?? [] {
        let stato: String
        switch v.esito {
        case .disponibile: stato = "⬆️  \(v.versione) → \(v.nuova ?? "?")"
        case .aggiornata: stato = "✓  \(v.versione)"
        case .nonVerificabile: stato = "·  \(v.versione)"
        }
        print("\(v.nome) [\(v.nomeFonte)] \(stato)\(v.nota.map { " — " + $0 } ?? "")")
    }
    print("\n" + L("Updates available", "Aggiornamenti disponibili") + ": \(r?.disponibili.count ?? 0)")
}

/// `Regia --autotest`: prova tutto in un'area finta. Il Mac vero non viene toccato.
func autotest() -> Bool {
    var ok = true
    func verifica(_ c: Bool, _ s: String) { print(c ? "OK   \(s)" : "ERR  \(s)"); if !c { ok = false } }
    let linguaUtente = Lingua.attuale
    Lingua.attuale = .it
    defer { Lingua.attuale = linguaUtente }
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

    // 12. Lingue: inglese di serie, italiano selezionabile, stessi ritocchi
    Lingua.attuale = .en
    let en = Catalogo.ritocchi, profEN = Catalogo.profili
    Lingua.attuale = .it
    let it = Catalogo.ritocchi
    verifica(en.map(\.id) == it.map(\.id) && Set(en.map(\.id)).count == en.count, "lingue: stessi \(en.count) ritocchi, id unici")
    verifica(en.allSatisfy { !$0.titolo.isEmpty && !$0.spiegazione.isEmpty } && zip(en, it).filter { $0.titolo != $1.titolo }.count >= en.count - 2,
             "lingue: titoli tradotti")
    verifica(Catalogo.ritocco("finder.estensioni")?.titolo == "Mostra le estensioni dei file"
             && en.first { $0.id == "finder.estensioni" }?.titolo == "Show file extensions", "lingue: esempio EN/IT")
    verifica(Catalogo.profili.map(\.id) == ["massimo", "bilanciato", "sicuro"] && profEN.map(\.nome) == ["Maximum", "Balanced", "Safe"],
             "profili: solo Massimo, Bilanciato, Sicuro")
    let tutti = Set(Catalogo.ritocchi.map(\.id))
    verifica(Catalogo.profili.allSatisfy { Set($0.ritocchi).isSubset(of: tutti) }
             && !Catalogo.idBilanciato.contains("finder.cestino30") && !Catalogo.idSicuro.contains { $0.hasPrefix("energia.") },
             "profili: ritocchi validi; Sicuro senza energia, Cestino a 30 giorni solo in Massimo")
    verifica(L("a", "b") == "b" && decimale(1.5) == "1,5", "lingue: italiano attivo nei test")

    // 13. Riavvio consigliato e consigli
    var pan = Panoramica(); pan.discoTotale = 100; pan.discoLibero = 50; pan.memoriaLibera = 60
    pan.giorniAcceso = 4
    verifica(Analisi.consigli(pan, pulibile: 0, avvioUtente: 0).contains { $0.azione == .riavvia }, "riavvio: consigliato dopo 4 giorni")
    pan.giorniAcceso = 1
    verifica(!Analisi.consigli(pan, pulibile: 0, avvioUtente: 0).contains { $0.azione == .riavvia }, "riavvio: non consigliato dopo 1 giorno")
    pan.discoLibero = 5
    verifica(Analisi.consigli(pan, pulibile: 0, avvioUtente: 0).first?.azione == .sezione(.pulizia), "consigli: disco pieno porta a Pulizia")
    let ctl = Suggerimenti.controlli()
    verifica(ctl.contains { $0.id == "aggiornamenti" } && ctl.allSatisfy { !$0.titolo.isEmpty }, "sicurezza: controlli letti (\(ctl.map(\.id)))")

    // 14. Aggiornamenti delle app (dati finti, niente rete)
    verifica(AggiornamentiApp.piuNuova("26.45.75", di: "26.45.7") && AggiornamentiApp.piuNuova("3.0b2", di: "3.0") && !AggiornamentiApp.piuNuova("1.2", di: "1.2.0"),
             "app: confronto versioni")
    let appcast = """
    <?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
    <item><title>3.4</title><sparkle:minimumSystemVersion>10.10</sparkle:minimumSystemVersion>
      <enclosure url="https://x/a.zip" sparkle:version="3804" sparkle:shortVersionString="3.4"/></item>
    <item><title>3.6</title><link>https://x/note</link><enclosure url="https://x/b.zip" sparkle:version="4070" sparkle:shortVersionString="3.6.0"/></item>
    <item><title>beta</title><sparkle:channel>beta</sparkle:channel><enclosure url="https://x/c.zip" sparkle:version="9999" sparkle:shortVersionString="4.0b1"/></item>
    <item><title>futuro</title><sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion><enclosure url="https://x/d.zip" sparkle:version="8000" sparkle:shortVersionString="5.0"/></item>
    <item><title>nuovo stile</title><sparkle:version>4100</sparkle:version><sparkle:shortVersionString>3.7</sparkle:shortVersionString><enclosure url="https://x/e.zip"/></item>
    </channel></rss>
    """
    let vc = AggiornamentiApp.analizzaAppcast(Data(appcast.utf8), sistema: "27.2")
    verifica(vc?.versione == "4100" && vc?.versioneBreve == "3.7", "app: appcast letto, esclusi beta e sistemi futuri (\(vc?.versioneBreve ?? "nil"))")
    if let vc {
        verifica(AggiornamentiApp.aggiornamentoSparkle(vc, breve: "3.6", build: "4070") == "3.7"
                 && AggiornamentiApp.aggiornamentoSparkle(vc, breve: "3.7.0", build: "4485") == nil, "app: Sparkle confronta il numero di build")
    }
    let lookup = #"{"resultCount":2,"results":[{"bundleId":"com.esempio.a","version":"2.0","trackId":123,"minimumOsVersion":"14.0"},{"bundleId":"com.esempio.b","version":"1.0","trackId":456,"kind":"software"}]}"#
    let ls = AggiornamentiApp.analizzaLookup(Data(lookup.utf8))
    verifica(ls["com.esempio.a"] == InfoStore(versione: "2.0", trackId: 123, pagina: nil, sistemaMinimo: "14.0", perMac: false)
             && ls["com.esempio.b"]?.perMac == false && ls.count == 2, "app: risposta App Store letta")
    let brewJSON = #"{"formulae":[{"name":"wget","installed_versions":["1.24"],"current_version":"1.25"}],"casks":[{"name":"firefox","installed_versions":["140.0"],"current_version":"141.0"},{"name":"bad;rm","installed_versions":["1"],"current_version":"2"}]}"#
    let br = AggiornamentiApp.analizzaBrew(Data(brewJSON.utf8))
    verifica(br.count == 2 && br.contains { $0.fonte == .homebrew(token: "firefox", formula: false) && $0.nuova == "141.0" }, "app: Homebrew letto, nomi strani scartati")

    // 15. Segnalazioni
    let corpoFb = Feedback.corpo(tipo: .problema, testo: "Non va", info: Feedback.infoSistema(nil), registro: Feedback.registroAnonimo(["[x] \(NSHomeDirectory())/file"]))
    let urlFb = Feedback.url(tipo: .problema, titolo: "Prova", corpo: corpoFb)
    verifica(urlFb?.absoluteString.hasPrefix("https://github.com/sm-bc/regia-mac/issues/new?") == true && corpoFb.contains("~/file")
             && !corpoFb.contains(NSHomeDirectory()) && urlFb?.absoluteString.contains("%5BBug%5D") == true, "segnalazioni: link GitHub, nome utente nascosto")

    // 16. Registro
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
} else if argomenti.contains("--aggiornamenti-app") {
    aggiornamentiAppTestuale()
    exit(0)
} else if argomenti.contains("--analisi") {
    analisiTestuale()
    exit(0)
} else {
    RegiaApp.main()
}
