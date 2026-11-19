import Foundation

// MARK: - Comandi di sistema

struct Esito { let codice: Int32; let uscita: String; let errore: String; var ok: Bool { codice == 0 } }

@discardableResult
func esegui(_ programma: String, _ argomenti: [String]) -> Esito {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: programma)
    p.arguments = argomenti
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return Esito(codice: -1, uscita: "", errore: error.localizedDescription) }
    // Legge stderr in parallelo per non bloccarsi con uscite lunghe.
    var datiErr = Data()
    let gruppo = DispatchGroup()
    gruppo.enter()
    DispatchQueue.global().async { datiErr = err.fileHandleForReading.readDataToEndOfFile(); gruppo.leave() }
    let datiOut = out.fileHandleForReading.readDataToEndOfFile()
    gruppo.wait()
    p.waitUntilExit()
    return Esito(codice: p.terminationStatus,
                 uscita: String(decoding: datiOut, as: UTF8.self),
                 errore: String(decoding: datiErr, as: UTF8.self))
}

// MARK: - Registro delle modifiche (serve per "Annulla")

struct Modifica: Codable, Identifiable {
    enum Tipo: String, Codable { case preferenza, energia, avvio }
    var id = UUID()
    var data = Date()
    var tipo: Tipo
    var ritoccoID: String
    var titolo: String
    // preferenza
    var dominio: String? = nil
    var chiave: String? = nil
    var originale: String? = nil       // nil = la chiave non esisteva
    var tipoOriginale: String? = nil   // boolean, integer, float, string
    // energia
    var ambito: Ambito? = nil
    var originaleEnergia: Int? = nil
    // avvio
    var percorsoOriginale: String? = nil
    var percorsoSalvato: String? = nil

    var nuovo: String
}

enum ErroreRegia: LocalizedError {
    case messaggio(String)
    var errorDescription: String? { if case .messaggio(let m) = self { return m }; return nil }
}

// MARK: - Motore

final class Motore {
    let prova: Bool
    let cartella: URL
    let cartellaProva: URL?
    private(set) var modifiche: [Modifica] = []
    var registro: ((String) -> Void)?

    private var fileModifiche: URL { cartella.appendingPathComponent("modifiche.json") }
    private var fileRegistro: URL { cartella.appendingPathComponent("registro.txt") }
    private var fileEnergiaProva: URL { cartella.appendingPathComponent("energia-prova.json") }

    init(prova: Bool, cartellaProva: URL? = nil) {
        self.prova = prova
        let fm = FileManager.default
        if prova {
            let base = cartellaProva ?? fm.temporaryDirectory.appendingPathComponent("RegiaProva")
            self.cartellaProva = base
            self.cartella = base.appendingPathComponent("Supporto")
        } else {
            self.cartellaProva = nil
            self.cartella = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Regia")
        }
        try? fm.createDirectory(at: cartella, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: fileModifiche),
           let m = try? JSONDecoder.regia.decode([Modifica].self, from: d) { modifiche = m }
    }

    func scriviRegistro(_ riga: String) {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy HH:mm:ss"
        let testo = "[\(f.string(from: Date()))] \(riga)\n"
        if let h = try? FileHandle(forWritingTo: fileRegistro) {
            h.seekToEndOfFile(); h.write(Data(testo.utf8)); try? h.close()
        } else {
            try? Data(testo.utf8).write(to: fileRegistro)
        }
        registro?(riga)
    }

    func leggiRegistro() -> [String] {
        (try? String(contentsOf: fileRegistro, encoding: .utf8))?
            .split(separator: "\n").map(String.init).reversed() ?? []
    }

    private func salvaModifiche() throws {
        let d = try JSONEncoder.regia.encode(modifiche)
        try d.write(to: fileModifiche, options: .atomic)
    }

    func modifica(per ritoccoID: String) -> Modifica? { modifiche.first { $0.ritoccoID == ritoccoID } }

    // MARK: Preferenze (defaults)

    /// In modalità prova scrive in un dominio finto, così il Mac vero non viene toccato.
    func dominioEffettivo(_ d: String) -> String { prova ? "com.regia.prova.\(d)" : d }

    func leggiPreferenza(_ dominio: String, _ chiave: String) -> (valore: String?, tipo: String?) {
        let dom = dominioEffettivo(dominio)
        let r = esegui("/usr/bin/defaults", ["read", dom, chiave])
        guard r.ok else { return (nil, nil) }
        let t = esegui("/usr/bin/defaults", ["read-type", dom, chiave])
        let tipo = t.uscita.replacingOccurrences(of: "Type is ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (r.uscita.trimmingCharacters(in: .whitespacesAndNewlines), tipo)
    }

    func scriviPreferenza(_ dominio: String, _ chiave: String, _ argomenti: [String]) throws {
        let r = esegui("/usr/bin/defaults", ["write", dominioEffettivo(dominio), chiave] + argomenti)
        if !r.ok { throw ErroreRegia.messaggio("Non riesco a scrivere \(dominio) \(chiave): \(r.errore)") }
    }

    func cancellaPreferenza(_ dominio: String, _ chiave: String) {
        esegui("/usr/bin/defaults", ["delete", dominioEffettivo(dominio), chiave])
    }

    // MARK: Energia (pmset)

    func leggiEnergia() -> [Ambito: [String: Int]] {
        if prova {
            if let d = try? Data(contentsOf: fileEnergiaProva),
               let m = try? JSONDecoder().decode([String: [String: Int]].self, from: d) {
                var r: [Ambito: [String: Int]] = [:]
                for (k, v) in m { if let a = Ambito(rawValue: k) { r[a] = v } }
                return r
            }
            return [.batteria: ["lowpowermode": 0, "displaysleep": 10, "powernap": 1],
                    .alimentatore: ["lowpowermode": 1, "displaysleep": 10, "powernap": 1]]
        }
        let r = esegui("/usr/bin/pmset", ["-g", "custom"])
        var risultato: [Ambito: [String: Int]] = [:]
        var corrente: Ambito?
        for riga in r.uscita.split(separator: "\n").map(String.init) {
            if riga.hasPrefix("Battery Power:") { corrente = .batteria; continue }
            if riga.hasPrefix("AC Power:") { corrente = .alimentatore; continue }
            guard let a = corrente else { continue }
            let parti = riga.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
            guard parti.count >= 2, let v = Int(parti.last!) else { continue }
            let chiave = parti.dropLast().joined(separator: " ")
            risultato[a, default: [:]][chiave] = v
        }
        return risultato
    }

    /// Applica comandi pmset con UNA sola richiesta della password (finestra di macOS).
    func applicaEnergia(_ comandi: [(Ambito, String, Int)]) throws {
        guard !comandi.isEmpty else { return }
        if prova {
            var stato = leggiEnergia()
            for (a, k, v) in comandi { stato[a, default: [:]][k] = v }
            var m: [String: [String: Int]] = [:]
            for (a, v) in stato { m[a.rawValue] = v }
            try JSONEncoder().encode(m).write(to: fileEnergiaProva)
            return
        }
        let shell = comandi.map { "/usr/bin/pmset \($0.0.rawValue) \($0.1) \($0.2)" }.joined(separator: " && ")
        let script = "do shell script \"\(shell)\" with administrator privileges"
        let r = esegui("/usr/bin/osascript", ["-e", script])
        if !r.ok {
            if r.errore.contains("-128") { throw ErroreRegia.messaggio("Hai annullato la richiesta della password: impostazioni energia non cambiate.") }
            throw ErroreRegia.messaggio("Impostazioni energia non applicate: \(r.errore)")
        }
    }

    // MARK: Stato dei ritocchi

    func statoAttuale(_ t: Ritocco, energia: [Ambito: [String: Int]]? = nil) -> (testo: String, attivo: Bool) {
        switch t.azione {
        case .preferenza(let dom, let chiave, let valore):
            let letto = leggiPreferenza(dom, chiave).valore
            let testo: String
            if let l = letto {
                if case .bool = valore { testo = ["1", "true", "yes"].contains(l.lowercased()) ? "sì" : "no" }
                else if case .float = valore, let d = Double(l) { testo = Valore.float((d * 100).rounded() / 100).testo }
                else { testo = l }
            } else { testo = "predefinito di macOS" }
            return (testo, valore.coincide(con: letto))
        case .energia(let a, let chiave, let valore):
            let e = energia ?? leggiEnergia()
            let v = e[a]?[chiave]
            // Per lo spegnimento dello schermo va bene anche un tempo più breve di quello proposto.
            if chiave == "displaysleep", let v, v > 0, v <= valore { return (Catalogo.testoEnergia(chiave: chiave, valore: v), true) }
            return (Catalogo.testoEnergia(chiave: chiave, valore: v), v == valore)
        }
    }

    // MARK: Applica

    /// Applica i ritocchi scelti. Salva prima i valori originali per poter annullare.
    @discardableResult
    func applica(_ ritocchi: [Ritocco]) -> (applicati: Int, errori: [String]) {
        var errori: [String] = []
        var applicati = 0
        var daRiavviare = Set<String>()
        backupDomini(ritocchi)

        // 1. Preferenze
        for t in ritocchi {
            guard case .preferenza(let dom, let chiave, let valore) = t.azione else { continue }
            let prima = leggiPreferenza(dom, chiave)
            if let tipo = prima.tipo, !["boolean", "integer", "float", "string"].contains(tipo) {
                errori.append("\(t.titolo): valore attuale di tipo \(tipo), lo lascio com'è.")
                continue
            }
            do {
                try scriviPreferenza(dom, chiave, valore.argomenti)
                if modifica(per: t.id) == nil {
                    modifiche.append(Modifica(tipo: .preferenza, ritoccoID: t.id, titolo: t.titolo,
                                              dominio: dom, chiave: chiave, originale: prima.valore,
                                              tipoOriginale: prima.tipo, nuovo: valore.testo))
                }
                applicati += 1
                if let r = t.riavvia { daRiavviare.insert(r) }
                scriviRegistro("Applicato: \(t.titolo) (prima: \(prima.valore ?? "predefinito"), ora: \(valore.testo))")
            } catch {
                errori.append(error.localizedDescription)
            }
        }

        // 2. Energia: tutti insieme, una sola password
        let energetici = ritocchi.compactMap { t -> (Ritocco, Ambito, String, Int)? in
            if case .energia(let a, let k, let v) = t.azione { return (t, a, k, v) }; return nil
        }
        if !energetici.isEmpty {
            let prima = leggiEnergia()
            do {
                try applicaEnergia(energetici.map { ($0.1, $0.2, $0.3) })
                for (t, a, k, v) in energetici {
                    if modifica(per: t.id) == nil {
                        modifiche.append(Modifica(tipo: .energia, ritoccoID: t.id, titolo: t.titolo, chiave: k,
                                                  ambito: a, originaleEnergia: prima[a]?[k],
                                                  nuovo: Catalogo.testoEnergia(chiave: k, valore: v)))
                    }
                    applicati += 1
                    scriviRegistro("Applicato: \(t.titolo) (prima: \(Catalogo.testoEnergia(chiave: k, valore: prima[a]?[k])))")
                }
            } catch {
                errori.append(error.localizedDescription)
                scriviRegistro("Errore energia: \(error.localizedDescription)")
            }
        }

        try? salvaModifiche()
        riavvia(daRiavviare)
        return (applicati, errori)
    }

    private func riavvia(_ processi: Set<String>) {
        guard !prova else { return }
        for p in processi.sorted() { esegui("/usr/bin/killall", [p]) }
    }

    /// Copia completa dei domini toccati, prima di ogni modifica (come un punto di ripristino).
    private func backupDomini(_ ritocchi: [Ritocco]) {
        let domini = Set(ritocchi.compactMap { t -> String? in
            if case .preferenza(let d, _, _) = t.azione { return d }; return nil
        })
        guard !domini.isEmpty else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dir = cartella.appendingPathComponent("Backup/\(f.string(from: Date()))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for d in domini {
            esegui("/usr/bin/defaults", ["export", dominioEffettivo(d), dir.appendingPathComponent("\(d).plist").path])
        }
        scriviRegistro("Backup delle impostazioni in \(dir.path)")
    }

    // MARK: Annulla

    func annulla(_ m: Modifica) throws {
        switch m.tipo {
        case .preferenza:
            guard let dom = m.dominio, let chiave = m.chiave else { break }
            if let orig = m.originale, let tipo = m.tipoOriginale {
                let arg: [String]
                switch tipo {
                case "boolean": arg = ["-bool", ["1", "true", "yes"].contains(orig.lowercased()) ? "true" : "false"]
                case "integer": arg = ["-int", orig]
                case "float": arg = ["-float", orig]
                default: arg = ["-string", orig]
                }
                try scriviPreferenza(dom, chiave, arg)
            } else {
                cancellaPreferenza(dom, chiave)
            }
            if let t = Catalogo.ritocco(m.ritoccoID), let r = t.riavvia { riavvia([r]) }
        case .energia:
            if let a = m.ambito, let k = m.chiave, let v = m.originaleEnergia {
                try applicaEnergia([(a, k, v)])
            }
        case .avvio:
            try riattivaAvvio(m)
        }
        modifiche.removeAll { $0.id == m.id }
        try salvaModifiche()
        scriviRegistro("Annullato: \(m.titolo)")
    }

    /// Riporta tutto com'era, dall'ultima modifica alla prima. Le impostazioni energia
    /// vengono rimesse con una sola password.
    func annullaTutto() -> [String] {
        var errori: [String] = []
        let energia = modifiche.filter { $0.tipo == .energia }
        if !energia.isEmpty {
            let comandi = energia.compactMap { m -> (Ambito, String, Int)? in
                guard let a = m.ambito, let k = m.chiave, let v = m.originaleEnergia else { return nil }
                return (a, k, v)
            }
            do {
                try applicaEnergia(comandi)
                for m in energia { scriviRegistro("Annullato: \(m.titolo)") }
                modifiche.removeAll { $0.tipo == .energia }
                try? salvaModifiche()
            } catch { errori.append(error.localizedDescription) }
        }
        for m in modifiche.reversed() where m.tipo != .energia {
            do { try annulla(m) } catch { errori.append("\(m.titolo): \(error.localizedDescription)") }
        }
        scriviRegistro(errori.isEmpty ? "Annulla tutto: completato." : "Annulla tutto: \(errori.count) errori.")
        return errori
    }

    // MARK: Avvio automatico (LaunchAgents)

    var cartellaAgentiUtente: URL {
        if let p = cartellaProva { return p.appendingPathComponent("LaunchAgents") }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    }
    var cartellaDisattivati: URL { cartella.appendingPathComponent("Avvio disattivato") }

    func elementiAvvio() -> [ElementoAvvio] {
        var lista: [ElementoAvvio] = []
        let sorgenti: [(URL, ElementoAvvio.Livello)] = prova
            ? [(cartellaAgentiUtente, .utente)]
            : [(cartellaAgentiUtente, .utente),
               (URL(fileURLWithPath: "/Library/LaunchAgents"), .sistemaAgente),
               (URL(fileURLWithPath: "/Library/LaunchDaemons"), .sistemaServizio)]
        for (dir, livello) in sorgenti {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for f in files where f.pathExtension == "plist" {
                lista.append(ElementoAvvio.da(file: f, livello: livello, disattivato: false))
            }
        }
        for m in modifiche where m.tipo == .avvio {
            if let s = m.percorsoSalvato {
                lista.append(ElementoAvvio.da(file: URL(fileURLWithPath: s), livello: .utente, disattivato: true,
                                              ritoccoID: m.ritoccoID))
            }
        }
        return lista.sorted { ($0.livello.rawValue, $0.nome) < ($1.livello.rawValue, $1.nome) }
    }

    func disattivaAvvio(_ e: ElementoAvvio) throws {
        guard e.livello == .utente, !e.disattivato else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: cartellaDisattivati, withIntermediateDirectories: true)
        let destinazione = cartellaDisattivati.appendingPathComponent(e.file.lastPathComponent)
        if fm.fileExists(atPath: destinazione.path) { try fm.removeItem(at: destinazione) }
        if !prova { esegui("/bin/launchctl", ["bootout", "gui/\(getuid())", e.file.path]) }
        try fm.moveItem(at: e.file, to: destinazione)
        modifiche.append(Modifica(tipo: .avvio, ritoccoID: "avvio.\(e.file.lastPathComponent)", titolo: "Avvio: \(e.nome)",
                                  percorsoOriginale: e.file.path, percorsoSalvato: destinazione.path, nuovo: "disattivato"))
        try salvaModifiche()
        scriviRegistro("Disattivato all'avvio: \(e.nome) (file spostato in \(cartellaDisattivati.path))")
    }

    private func riattivaAvvio(_ m: Modifica) throws {
        guard let o = m.percorsoOriginale, let s = m.percorsoSalvato else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: s) {
            if fm.fileExists(atPath: o) { try fm.removeItem(atPath: s) } else { try fm.moveItem(atPath: s, toPath: o) }
        }
        if !prova { esegui("/bin/launchctl", ["bootstrap", "gui/\(getuid())", o]) }
    }
}

// MARK: - Elementi di avvio

struct ElementoAvvio: Identifiable, Hashable {
    enum Livello: Int { case utente = 0, sistemaAgente = 1, sistemaServizio = 2
        var nome: String {
            switch self {
            case .utente: return "Tuo account"
            case .sistemaAgente: return "Tutti gli utenti"
            case .sistemaServizio: return "Servizio di sistema"
            }
        }
    }
    var id: String { file.path }
    let file: URL
    let nome: String
    let programma: String
    let livello: Livello
    let disattivato: Bool
    var ritoccoID: String? = nil

    static func da(file: URL, livello: Livello, disattivato: Bool, ritoccoID: String? = nil) -> ElementoAvvio {
        var etichetta = file.deletingPathExtension().lastPathComponent
        var programma = ""
        if let d = try? Data(contentsOf: file),
           let p = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] {
            etichetta = (p["Label"] as? String) ?? etichetta
            programma = (p["Program"] as? String) ?? ((p["ProgramArguments"] as? [String])?.first ?? "")
        }
        return ElementoAvvio(file: file, nome: etichetta, programma: programma, livello: livello,
                             disattivato: disattivato, ritoccoID: ritoccoID)
    }
}

extension JSONEncoder {
    static var regia: JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }
}
extension JSONDecoder {
    static var regia: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
