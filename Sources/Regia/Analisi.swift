import Foundation

// MARK: - Panoramica del Mac

struct Panoramica {
    var modello = ""
    var chip = ""
    var sistema = ""
    var memoriaGB = 0.0
    var memoriaLibera: Int? = nil     // percentuale
    var acceso = ""                   // da quanto tempo
    var giorniAcceso = 0.0
    var discoTotale: Int64 = 0
    var discoLibero: Int64 = 0
    var batteriaPercento: Int? = nil
    var batteriaCicli: Int? = nil
    var batteriaSalute: Int? = nil    // % della capacità originale
    var inCarica = false
    var processiCPU: [Processo] = []
    var processiMemoria: [Processo] = []

    var percentoDiscoLibero: Double { discoTotale > 0 ? Double(discoLibero) / Double(discoTotale) : 0 }
}

struct Processo: Identifiable, Hashable {
    let id: Int
    let nome: String
    let cpu: Double
    let memoriaMB: Double
}

struct Consiglio: Identifiable {
    enum Livello { case ok, attenzione, problema }
    /// Cosa succede premendo il pulsante accanto al consiglio.
    enum Azione: Equatable { case sezione(Sezione), riavvia, apri(String) }
    let id = UUID()
    let livello: Livello
    let titolo: String
    let dettaglio: String
    var azione: Azione? = nil
    var testoAzione: String? = nil
}

enum Analisi {
    static func panoramica() -> Panoramica {
        var p = Panoramica()
        let pi = ProcessInfo.processInfo
        p.modello = esegui("/usr/sbin/sysctl", ["-n", "hw.model"]).uscita.trimmingCharacters(in: .whitespacesAndNewlines)
        p.chip = esegui("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]).uscita.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = pi.operatingSystemVersion
        p.sistema = "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        p.memoriaGB = Double(pi.physicalMemory) / 1_073_741_824
        let mp = esegui("/usr/bin/memory_pressure", ["-Q"]).uscita
        if let r = mp.range(of: #"(\d+)%"#, options: .regularExpression) {
            p.memoriaLibera = Int(mp[r].dropLast())
        }
        let sec = pi.systemUptime
        p.giorniAcceso = sec / 86400
        let g = Int(sec) / 86400, h = (Int(sec) % 86400) / 3600, m = (Int(sec) % 3600) / 60
        p.acceso = g > 0 ? L("\(g) d \(h) h", "\(g) g \(h) h") : (h > 0 ? "\(h) h \(m) min" : "\(m) min")

        if let val = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            p.discoTotale = Int64(val.volumeTotalCapacity ?? 0)
            p.discoLibero = val.volumeAvailableCapacityForImportantUsage ?? 0
        }

        let io = esegui("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"]).uscita
        func numero(_ chiave: String) -> Int? {
            guard let r = io.range(of: "\"\(chiave)\"\\s*=\\s*(\\d+)", options: .regularExpression) else { return nil }
            return Int(io[r].split(separator: "=").last!.trimmingCharacters(in: .whitespaces))
        }
        if !io.isEmpty {
            p.batteriaCicli = numero("CycleCount")
            if let raw = numero("AppleRawMaxCapacity"), let des = numero("DesignCapacity"), des > 0 {
                p.batteriaSalute = min(100, Int((Double(raw) / Double(des) * 100).rounded()))
            }
            p.inCarica = io.contains("\"ExternalConnected\" = Yes")
        }
        let batt = esegui("/usr/bin/pmset", ["-g", "batt"]).uscita
        if let r = batt.range(of: #"(\d+)%"#, options: .regularExpression) { p.batteriaPercento = Int(batt[r].dropLast()) }

        p.processiCPU = processi(ordine: "-r")
        p.processiMemoria = processi(ordine: "-m")
        return p
    }

    private static func processi(ordine: String) -> [Processo] {
        let r = esegui("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm=", ordine])
        return r.uscita.split(separator: "\n").prefix(8).compactMap { riga in
            let parti = riga.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parti.count == 4, let pid = Int(parti[0]), let cpu = Double(parti[1].replacingOccurrences(of: ",", with: ".")),
                  let rss = Double(parti[2]) else { return nil }
            return Processo(id: pid, nome: String(parti[3]), cpu: cpu, memoriaMB: rss / 1024)
        }
    }

    /// Dopo quanti giorni di accensione suggeriamo un riavvio.
    static let giorniPerRiavvio = 3.0

    static func consigli(_ p: Panoramica, pulibile: Int64, avvioUtente: Int) -> [Consiglio] {
        var c: [Consiglio] = []
        let libero = p.percentoDiscoLibero
        let pct = Int(libero * 100)
        if libero < 0.10 {
            c.append(Consiglio(livello: .problema, titolo: L("Disk almost full", "Disco quasi pieno"),
                               dettaglio: L("Only \(pct)% free. Below 10% the Mac slows down: use Cleanup.",
                                            "Libero solo il \(pct)%. Sotto il 10% il Mac rallenta: usa Pulizia."),
                               azione: .sezione(.pulizia), testoAzione: L("Clean up", "Pulisci")))
        } else if libero < 0.20 {
            c.append(Consiglio(livello: .attenzione, titolo: L("Disk space getting low", "Spazio su disco in calo"),
                               dettaglio: L("\(pct)% free. Better to stay above 20%.", "Libero il \(pct)%. Meglio stare sopra il 20%."),
                               azione: .sezione(.pulizia), testoAzione: L("Clean up", "Pulisci")))
        } else {
            c.append(Consiglio(livello: .ok, titolo: L("Disk space is fine", "Spazio su disco a posto"),
                               dettaglio: L("\(pct)% free.", "Libero il \(pct)%.")))
        }
        if pulibile > 1_000_000_000 {
            c.append(Consiglio(livello: .attenzione, titolo: L("\(formatoByte(pulibile)) of unneeded files", "\(formatoByte(pulibile)) di file inutili"),
                               dettaglio: L("Caches and logs you can move to the Trash from Cleanup.", "Cache e log che si possono spostare nel Cestino da Pulizia."),
                               azione: .sezione(.pulizia), testoAzione: L("Clean up", "Pulisci")))
        }
        if let m = p.memoriaLibera {
            if m < 20 {
                c.append(Consiglio(livello: .problema, titolo: L("Memory under pressure", "Memoria sotto pressione"),
                                   dettaglio: L("Only \(m)% free. Quit the apps using the most memory (see below).",
                                                "Libera solo il \(m)%. Chiudi le app che usano più memoria (vedi sotto).")))
            } else {
                c.append(Consiglio(livello: .ok, titolo: L("Memory is fine", "Memoria a posto"), dettaglio: L("\(m)% free.", "Libera il \(m)%.")))
            }
        }
        if p.giorniAcceso >= giorniPerRiavvio {
            let g = Int(p.giorniAcceso)
            c.append(Consiglio(livello: p.giorniAcceso > 7 ? .problema : .attenzione,
                               titolo: L("On for ", "Acceso da ") + P(g, "day", "days", "giorno", "giorni"),
                               dettaglio: L("A restart frees memory, closes stuck processes and finishes installing updates.",
                                            "Un riavvio libera memoria, chiude i processi bloccati e completa gli aggiornamenti."),
                               azione: .riavvia, testoAzione: L("Restart…", "Riavvia…")))
        }
        if let s = p.batteriaSalute {
            if s < 80 {
                c.append(Consiglio(livello: .problema, titolo: L("Battery at \(s)%", "Batteria al \(s)%"),
                                   dettaglio: L("Below 80% Apple recommends a replacement.", "Sotto l'80% Apple consiglia la sostituzione."),
                                   azione: .apri("x-apple.systempreferences:com.apple.Battery-Settings.extension"), testoAzione: L("Open", "Apri")))
            } else {
                c.append(Consiglio(livello: .ok, titolo: L("Battery is healthy", "Batteria in salute"),
                                   dettaglio: L("Capacity at \(s)% of original, \(p.batteriaCicli ?? 0) cycles.",
                                                "Capacità al \(s)% dell'originale, \(p.batteriaCicli ?? 0) cicli.")))
            }
        }
        if let cpu = p.processiCPU.first, cpu.cpu > 80 {
            c.append(Consiglio(livello: .attenzione, titolo: L("\(cpu.nome) is using a lot of CPU", "\(cpu.nome) usa molta CPU"),
                               dettaglio: L("At \(Int(cpu.cpu))%: if you're not using it, quit it.", "Al \(Int(cpu.cpu))%: se non lo stai usando, chiudilo."),
                               azione: .apri("file:///System/Applications/Utilities/Activity%20Monitor.app"), testoAzione: L("Activity Monitor", "Monitoraggio Attività")))
        }
        if avvioUtente > 0 {
            c.append(Consiglio(livello: .attenzione, titolo: P(avvioUtente, "program starts by itself", "programs start by themselves", "programma parte da solo", "programmi partono da soli"),
                               dettaglio: L("Check in Startup which ones you really need.", "Controlla in Avvio quali ti servono davvero."),
                               azione: .sezione(.avvio), testoAzione: L("Review", "Controlla")))
        }
        return c
    }
}

// MARK: - Pulizia

struct ZonaPulizia: Identifiable {
    let id: String
    let titolo: String
    let spiegazione: String
    let icona: String
    let cartella: URL
    var selezionataDiDefault: Bool
    /// true = fa parte solo della "Pulizia accurata".
    var accurata = false
    /// Per le cartelle personali (Download) il calcolo parte solo su richiesta.
    var suRichiesta = false
    var calcolata = false
    var elementi: [URL] = []
    var dimensione: Int64 = 0
}

enum Pulizia {
    /// Cache che non tocchiamo mai: app in uso adesso o gestite da macOS.
    static let escluse = ["com.apple.", "com.anthropic", "Claude", "io.github.sm-bc.regia", "CloudKit", "FamilyCircle",
                          "com.microsoft.SharePoint", "Homebrew"]

    static func zone(base: URL? = nil) -> [ZonaPulizia] {
        let home = base ?? FileManager.default.homeDirectoryForCurrentUser
        return [
            ZonaPulizia(id: "cache", titolo: L("App caches", "Cache delle app"),
                        spiegazione: L("Temporary files that apps recreate by themselves. macOS and Claude caches are excluded.", "File temporanei che le app ricreano da sole. Escluse quelle di macOS e di Claude."),
                        icona: "archivebox", cartella: home.appendingPathComponent("Library/Caches"), selezionataDiDefault: true),
            ZonaPulizia(id: "log", titolo: L("App logs", "Log delle app"),
                        spiegazione: L("Activity records: only needed to diagnose problems.", "Registri di funzionamento: servono solo per diagnosticare problemi."),
                        icona: "doc.text", cartella: home.appendingPathComponent("Library/Logs"), selezionataDiDefault: true),
            ZonaPulizia(id: "xcode", titolo: L("Xcode build files", "File di compilazione di Xcode"),
                        spiegazione: L("DerivedData: Xcode recreates them at the next build.", "DerivedData: Xcode li ricrea alla prossima compilazione."),
                        icona: "hammer", cartella: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                        selezionataDiDefault: true),
            ZonaPulizia(id: "iossupporto", titolo: L("Xcode iPhone/iPad support", "Supporto iPhone/iPad di Xcode"),
                        spiegazione: L("Device debugging files: Xcode downloads them again when you connect the iPhone.", "File per il debug sui dispositivi: Xcode li riscarica quando colleghi l'iPhone."),
                        icona: "iphone", cartella: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"),
                        selezionataDiDefault: false, accurata: true),
            ZonaPulizia(id: "simulatori", titolo: L("Simulator caches", "Cache dei simulatori"),
                        spiegazione: L("Temporary files of Xcode's iPhone simulators: they are recreated automatically.", "File temporanei dei simulatori iPhone di Xcode: si ricreano da soli."),
                        icona: "ipad.and.iphone", cartella: home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
                        selezionataDiDefault: false, accurata: true),
            ZonaPulizia(id: "download", titolo: L("Old downloads (over 90 days)", "Download vecchi (più di 90 giorni)"),
                        spiegazione: L("Personal files: check the list before moving them. macOS will ask for permission.", "File personali: controlla l'elenco prima di spostarli. macOS chiederà il permesso."),
                        icona: "arrow.down.circle", cartella: home.appendingPathComponent("Downloads"),
                        selezionataDiDefault: false, accurata: true, suRichiesta: true),
        ]
    }

    static func calcola(_ z: inout ZonaPulizia) {
        let fm = FileManager.default
        var elementi = (try? fm.contentsOfDirectory(at: z.cartella, includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [])) ?? []
        elementi.removeAll { url in escluse.contains { url.lastPathComponent.hasPrefix($0) } || url.lastPathComponent == ".DS_Store" }
        if z.id == "download" {
            let limite = Date().addingTimeInterval(-90 * 86400)
            elementi = elementi.filter { url in
                let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                return d < limite && !url.lastPathComponent.hasPrefix(".")
            }
        }
        var totale: Int64 = 0
        var conDimensione: [(URL, Int64)] = []
        for e in elementi {
            let d = dimensione(e)
            totale += d
            conDimensione.append((e, d))
        }
        z.elementi = conDimensione.sorted { $0.1 > $1.1 }.map { $0.0 }
        z.dimensione = totale
        z.calcolata = true
    }

    static func dimensione(_ url: URL) -> Int64 {
        let chiavi: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let v = try? url.resourceValues(forKeys: Set(chiavi)) else { return 0 }
        if v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? 0) }
        var totale: Int64 = 0
        if let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: chiavi, options: [], errorHandler: { _, _ in true }) {
            for case let f as URL in en {
                totale += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
            }
        }
        return totale
    }

    /// Sposta nel Cestino (recuperabile). Restituisce byte spostati, quanti e gli errori.
    static func spostaNelCestino(_ elementi: [URL]) -> (byte: Int64, spostati: [URL], errori: Int) {
        var byte: Int64 = 0, errori = 0
        var spostati: [URL] = []
        for e in elementi {
            let d = dimensione(e)
            var risultato: NSURL?
            do {
                try FileManager.default.trashItem(at: e, resultingItemURL: &risultato)
                byte += d
                if let r = risultato as URL? { spostati.append(r) }
            } catch { errori += 1 }
        }
        return (byte, spostati, errori)
    }
}

/// Dimensione come nel Finder (1 GB = 1.000.000.000 byte), con i decimali della lingua scelta.
func formatoByte(_ b: Int64) -> String {
    let v = Double(b)
    if v < 1_000_000 { return "\(Int((v / 1000).rounded())) KB" }
    if v < 1_000_000_000 { return decimale(v / 1_000_000) + " MB" }
    if v < 1_000_000_000_000 { return decimale(v / 1_000_000_000) + " GB" }
    return decimale(v / 1_000_000_000_000, 2) + " TB"
}
