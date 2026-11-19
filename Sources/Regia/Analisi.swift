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
    let id = UUID()
    let livello: Livello
    let titolo: String
    let dettaglio: String
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
        p.acceso = g > 0 ? "\(g) g \(h) h" : (h > 0 ? "\(h) h \(m) min" : "\(m) min")

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

    static func consigli(_ p: Panoramica, pulibile: Int64, avvioUtente: Int) -> [Consiglio] {
        var c: [Consiglio] = []
        let libero = p.percentoDiscoLibero
        if libero < 0.10 {
            c.append(Consiglio(livello: .problema, titolo: "Disco quasi pieno",
                               dettaglio: "Libero solo il \(Int(libero * 100))%. Sotto il 10% il Mac rallenta: usa Pulizia."))
        } else if libero < 0.20 {
            c.append(Consiglio(livello: .attenzione, titolo: "Spazio su disco in calo",
                               dettaglio: "Libero il \(Int(libero * 100))%. Meglio stare sopra il 20%."))
        } else {
            c.append(Consiglio(livello: .ok, titolo: "Spazio su disco a posto", dettaglio: "Libero il \(Int(libero * 100))%."))
        }
        if pulibile > 1_000_000_000 {
            c.append(Consiglio(livello: .attenzione, titolo: "\(formatoByte(pulibile)) di file inutili",
                               dettaglio: "Cache e log che si possono spostare nel Cestino da Pulizia."))
        }
        if let m = p.memoriaLibera {
            if m < 20 {
                c.append(Consiglio(livello: .problema, titolo: "Memoria sotto pressione",
                                   dettaglio: "Libera solo il \(m)%. Chiudi le app che usano più memoria (vedi sotto)."))
            } else {
                c.append(Consiglio(livello: .ok, titolo: "Memoria a posto", dettaglio: "Libera il \(m)%."))
            }
        }
        if p.giorniAcceso > 7 {
            c.append(Consiglio(livello: .attenzione, titolo: "Acceso da \(Int(p.giorniAcceso)) giorni",
                               dettaglio: "Un riavvio ogni tanto libera memoria e applica gli aggiornamenti."))
        }
        if let s = p.batteriaSalute {
            if s < 80 {
                c.append(Consiglio(livello: .problema, titolo: "Batteria al \(s)%",
                                   dettaglio: "Sotto l'80% Apple consiglia la sostituzione."))
            } else {
                c.append(Consiglio(livello: .ok, titolo: "Batteria in salute",
                                   dettaglio: "Capacità al \(s)% dell'originale, \(p.batteriaCicli ?? 0) cicli."))
            }
        }
        if let cpu = p.processiCPU.first, cpu.cpu > 80 {
            c.append(Consiglio(livello: .attenzione, titolo: "\(cpu.nome) usa molta CPU",
                               dettaglio: "Al \(Int(cpu.cpu))%: se non lo stai usando, chiudilo."))
        }
        if avvioUtente > 0 {
            c.append(Consiglio(livello: .attenzione, titolo: "\(avvioUtente) programmi partono da soli",
                               dettaglio: "Controlla in Avvio quali ti servono davvero."))
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
            ZonaPulizia(id: "cache", titolo: "Cache delle app",
                        spiegazione: "File temporanei che le app ricreano da sole. Escluse quelle di macOS e di Claude.",
                        icona: "archivebox", cartella: home.appendingPathComponent("Library/Caches"), selezionataDiDefault: true),
            ZonaPulizia(id: "log", titolo: "Log delle app",
                        spiegazione: "Registri di funzionamento: servono solo per diagnosticare problemi.",
                        icona: "doc.text", cartella: home.appendingPathComponent("Library/Logs"), selezionataDiDefault: true),
            ZonaPulizia(id: "xcode", titolo: "File di compilazione di Xcode",
                        spiegazione: "DerivedData: Xcode li ricrea alla prossima compilazione.",
                        icona: "hammer", cartella: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                        selezionataDiDefault: true),
            ZonaPulizia(id: "iossupporto", titolo: "Supporto iPhone/iPad di Xcode",
                        spiegazione: "File per il debug sui dispositivi: Xcode li riscarica quando colleghi l'iPhone.",
                        icona: "iphone", cartella: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"),
                        selezionataDiDefault: false, accurata: true),
            ZonaPulizia(id: "simulatori", titolo: "Cache dei simulatori",
                        spiegazione: "File temporanei dei simulatori iPhone di Xcode: si ricreano da soli.",
                        icona: "ipad.and.iphone", cartella: home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
                        selezionataDiDefault: false, accurata: true),
            ZonaPulizia(id: "download", titolo: "Download vecchi (più di 90 giorni)",
                        spiegazione: "File personali: controlla l'elenco prima di spostarli. macOS chiederà il permesso.",
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

func formatoByte(_ b: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useKB, .useMB, .useGB]
    return f.string(fromByteCount: b)
}
