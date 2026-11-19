import Foundation
import AppKit

struct Strumento: Identifiable {
    enum Gruppo: String, CaseIterable { case controlli = "Controlli (sola lettura)", rete = "Rete e latenza", riparazione = "Riparazione e pulizia" }
    let id: String
    let titolo: String
    let spiegazione: String
    let icona: String
    let gruppo: Gruppo
    /// false = legge soltanto: funziona anche in Modalità prova.
    let modifica: Bool
    var serveAdmin = false
    var durata: String? = nil
    var avviso: String? = nil
}

enum Manutenzione {
    static let strumenti: [Strumento] = [
        Strumento(id: "disco.salute", titolo: "Salute del disco", spiegazione: "Stato SMART dell'SSD e spazio dei volumi.",
                  icona: "internaldrive", gruppo: .controlli, modifica: false),
        Strumento(id: "disco.verifica", titolo: "Verifica il disco", spiegazione: "Controlla il file system del disco di avvio (come Utility Disco › S.O.S., solo controllo).",
                  icona: "stethoscope", gruppo: .controlli, modifica: false, durata: "circa 10 secondi"),
        Strumento(id: "batteria.report", titolo: "Report batteria", spiegazione: "Cicli, condizione, capacità massima e alimentatore.",
                  icona: "battery.100percent", gruppo: .controlli, modifica: false),
        Strumento(id: "macos.aggiornamenti", titolo: "Aggiornamenti di macOS", spiegazione: "Chiede ad Apple se ci sono aggiornamenti. Non installa niente.",
                  icona: "arrow.down.app", gruppo: .controlli, modifica: false, durata: "fino a un minuto"),
        Strumento(id: "rete.latenza", titolo: "Misura la latenza", spiegazione: "Ping verso il router e i server DNS: quanto risponde in fretta la rete.",
                  icona: "dot.radiowaves.left.and.right", gruppo: .rete, modifica: false, durata: "circa 10 secondi"),
        Strumento(id: "rete.qualita", titolo: "Test della connessione", spiegazione: "Velocità in download e upload e reattività (strumento di Apple).",
                  icona: "speedometer", gruppo: .rete, modifica: false, durata: "circa 20 secondi"),
        Strumento(id: "rete.dns", titolo: "Svuota la cache DNS", spiegazione: "Utile se alcuni siti non si aprono o puntano al posto sbagliato.",
                  icona: "network", gruppo: .rete, modifica: true, serveAdmin: true),
        Strumento(id: "ram.libera", titolo: "Libera la memoria", spiegazione: "Svuota la memoria di file usata come cache. Per pochi minuti le app possono essere più lente.",
                  icona: "memorychip", gruppo: .riparazione, modifica: true, serveAdmin: true),
        Strumento(id: "apricon.ricostruisci", titolo: "Sistema il menu \"Apri con\"", spiegazione: "Ricostruisce l'elenco delle app: toglie doppioni e app cancellate dal menu Apri con.",
                  icona: "list.bullet.rectangle", gruppo: .riparazione, modifica: true, durata: "circa 30 secondi"),
        Strumento(id: "interfaccia.riavvia", titolo: "Riavvia Dock, Finder e barra dei menu", spiegazione: "Risolve icone bloccate o Finder che non risponde. Le finestre restano.",
                  icona: "arrow.triangle.2.circlepath", gruppo: .riparazione, modifica: true),
        Strumento(id: "spotlight.indice", titolo: "Rifai l'indice di Spotlight", spiegazione: "Se la ricerca non trova i file. Per qualche ora il Mac lavora di più in background.",
                  icona: "magnifyingglass", gruppo: .riparazione, modifica: true, serveAdmin: true,
                  avviso: "Spotlight ricostruisce l'indice da zero: per qualche ora la ricerca è incompleta e il Mac scalda un po' di più."),
    ]

    /// Esegue uno strumento e restituisce un testo da leggere.
    static func esegui(_ s: Strumento) -> String {
        switch s.id {
        case "disco.salute": return saluteDisco()
        case "disco.verifica":
            let r = Regia.esegui("/usr/sbin/diskutil", ["verifyVolume", "/"])
            let ok = r.uscita.contains("appears to be OK")
            return (ok ? "✅ Il disco è a posto.\n\n" : "⚠️ Controlla il risultato: se ci sono errori usa Utility Disco › S.O.S.\n\n")
                + ultimeRighe(r.uscita + r.errore, 6)
        case "batteria.report": return reportBatteria()
        case "macos.aggiornamenti":
            let r = Regia.esegui("/usr/sbin/softwareupdate", ["-l"])
            let tutto = r.uscita + r.errore
            if tutto.contains("No new software available") { return "✅ macOS è aggiornato." }
            let voci = tutto.split(separator: "\n").filter { $0.contains("Title:") }.map { "• " + $0.replacingOccurrences(of: "Title:", with: "").trimmingCharacters(in: .whitespaces) }
            return voci.isEmpty ? ultimeRighe(tutto, 10)
                : "⬆️ Aggiornamenti disponibili:\n" + voci.joined(separator: "\n") + "\n\nSi installano da Impostazioni di Sistema › Generali › Aggiornamento Software."
        case "rete.latenza": return latenza()
        case "rete.qualita": return qualitaRete()
        case "rete.dns":
            return admin("/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder", ok: "✅ Cache DNS svuotata.")
        case "ram.libera":
            let prima = Misuratore().campione().memoriaUsataGB
            let t = admin("/usr/sbin/purge", ok: "✅ Memoria liberata.")
            let dopo = Misuratore().campione().memoriaUsataGB
            return t + String(format: "\nMemoria usata: %.1f GB → %.1f GB", prima, dopo).replacingOccurrences(of: ".", with: ",")
        case "apricon.ricostruisci":
            let r = Regia.esegui("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                                 ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])
            return r.ok ? "✅ Elenco delle app ricostruito. Il menu \"Apri con\" si aggiorna in pochi secondi." : "Non riuscito: \(r.errore)"
        case "interfaccia.riavvia":
            for p in ["Dock", "Finder", "SystemUIServer"] { Regia.esegui("/usr/bin/killall", [p]) }
            return "✅ Dock, Finder e barra dei menu riavviati."
        case "spotlight.indice":
            return admin("/usr/bin/mdutil -E /", ok: "✅ Spotlight sta ricostruendo l'indice. Puoi continuare a usare il Mac.")
        default: return "Strumento sconosciuto."
        }
    }

    /// Comandi che chiedono la password nella finestra di macOS.
    static func admin(_ comando: String, ok: String) -> String {
        let r = Regia.esegui("/usr/bin/osascript", ["-e", "do shell script \"\(comando)\" with administrator privileges"])
        if r.ok { return ok }
        if r.errore.contains("-128") { return "Annullato: hai chiuso la richiesta della password." }
        return "Non riuscito: \(r.errore.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func ultimeRighe(_ t: String, _ n: Int) -> String {
        t.split(separator: "\n").suffix(n).joined(separator: "\n")
    }

    static func saluteDisco() -> String {
        let info = Regia.esegui("/usr/sbin/diskutil", ["info", "disk0"]).uscita
        func campo(_ k: String) -> String? {
            info.split(separator: "\n").first { $0.contains(k + ":") }
                .map { $0.split(separator: ":", maxSplits: 1).last!.trimmingCharacters(in: .whitespaces) }
        }
        let smart = campo("SMART Status") ?? "non disponibile"
        var t = (smart == "Verified" ? "✅ SSD in salute (SMART: verificato)." : "⚠️ Stato SMART: \(smart)") + "\n"
        if let n = campo("Device / Media Name") { t += "Disco: \(n)\n" }
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            t += "Spazio libero: \(formatoByte(v.volumeAvailableCapacityForImportantUsage ?? 0)) su \(formatoByte(Int64(v.volumeTotalCapacity ?? 0)))"
        }
        return t
    }

    static func reportBatteria() -> String {
        let r = Regia.esegui("/usr/sbin/system_profiler", ["SPPowerDataType"]).uscita
        func campo(_ k: String) -> String? {
            r.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(k + ":") }
                .map { $0.split(separator: ":", maxSplits: 1).last!.trimmingCharacters(in: .whitespaces) }
        }
        guard let cicli = campo("Cycle Count") else { return "Questo Mac non ha una batteria." }
        let condizione = campo("Condition") ?? "?"
        let capacita = campo("Maximum Capacity") ?? "?"
        let tradotta = ["Normal": "normale ✅", "Service Recommended": "assistenza consigliata ⚠️",
                        "Replace Soon": "da sostituire presto ⚠️", "Replace Now": "da sostituire ❌"][condizione] ?? condizione
        var t = "Condizione: \(tradotta)\nCapacità massima: \(capacita) dell'originale\nCicli di carica: \(cicli) (le batterie Apple sono pensate per 1.000 cicli)"
        if let w = campo("Wattage (W)") { t += "\nAlimentatore collegato: \(w) W" }
        return t
    }

    // MARK: Latenza

    struct Ping { let nome: String; let indirizzo: String; let media: Double?; let variazione: Double?; let persi: Double }

    static func destinazioniPing() -> [(String, String)] {
        var d: [(String, String)] = []
        let route = Regia.esegui("/sbin/route", ["-n", "get", "default"]).uscita
        if let g = route.split(separator: "\n").first(where: { $0.contains("gateway:") })?.split(separator: ":").last?
            .trimmingCharacters(in: .whitespaces) { d.append(("Router", g)) }
        let dns = Regia.esegui("/usr/sbin/scutil", ["--dns"]).uscita.split(separator: "\n")
            .filter { $0.contains("nameserver[") }.compactMap { $0.components(separatedBy: " : ").last?.trimmingCharacters(in: .whitespaces) }
        var visti = Set(d.map { $0.1 })
        for s in dns where !visti.contains(s) && !s.contains(":") {   // solo IPv4
            visti.insert(s); d.append(("DNS", s))
            if d.count >= 3 { break }
        }
        return d
    }

    static func ping(_ nome: String, _ indirizzo: String) -> Ping {
        let r = Regia.esegui("/sbin/ping", ["-c", "10", "-i", "0.2", "-q", "-t", "8", indirizzo]).uscita
        return analizzaPing(nome, indirizzo, r)
    }

    static func analizzaPing(_ nome: String, _ indirizzo: String, _ testo: String) -> Ping {
        var media: Double?, variazione: Double?, persi = 100.0
        if let riga = testo.split(separator: "\n").first(where: { $0.contains("packet loss") }),
           let r = riga.range(of: #"([\d.]+)% packet loss"#, options: .regularExpression) {
            persi = Double(riga[r].split(separator: "%").first ?? "100") ?? 100
        }
        if let riga = testo.split(separator: "\n").first(where: { $0.contains("min/avg/max") }),
           let valori = riga.split(separator: "=").last?.trimmingCharacters(in: .whitespaces).split(separator: " ").first {
            let n = valori.split(separator: "/").compactMap { Double($0) }
            if n.count >= 4 { media = n[1]; variazione = n[3] }
        }
        return Ping(nome: nome, indirizzo: indirizzo, media: media, variazione: variazione, persi: persi)
    }

    static func giudizio(_ p: Ping) -> String {
        guard let m = p.media else { return "❌ nessuna risposta" }
        let locale = p.nome == "Router"
        let soglie: (Double, Double) = locale ? (5, 20) : (30, 80)
        let voto = m <= soglie.0 ? "ottima ✅" : (m <= soglie.1 ? "buona" : "alta ⚠️")
        var t = String(format: "%.1f ms (±%.1f) — %@", m, p.variazione ?? 0, voto)
        if p.persi > 0 { t += String(format: ", persi %.0f%% ⚠️", p.persi) }
        return t.replacingOccurrences(of: ".", with: ",")
    }

    static func latenza() -> String {
        let dest = destinazioniPing()
        guard !dest.isEmpty else { return "❌ Nessuna rete collegata." }
        var righe: [String] = []
        for (nome, ind) in dest { righe.append("\(nome) \(ind): " + giudizio(ping(nome, ind))) }
        righe.append("\nRouter sotto 5 ms = Wi-Fi in forma. Se è alto o perde pacchetti: avvicinati al router o usa il cavo.")
        return righe.joined(separator: "\n")
    }

    static func qualitaRete() -> String {
        let r = Regia.esegui("/usr/bin/networkQuality", ["-c"])
        guard let d = try? JSONSerialization.jsonObject(with: Data(r.uscita.utf8)) as? [String: Any] else {
            return "❌ Test non riuscito: \(r.errore.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        let giu = ((d["dl_throughput"] as? Double) ?? 0) / 1_000_000
        let su = ((d["ul_throughput"] as? Double) ?? 0) / 1_000_000
        let rpm = (d["responsiveness"] as? Double) ?? 0
        let reattivita = rpm >= 800 ? "alta ✅" : (rpm >= 200 ? "media" : "bassa ⚠️ (videochiamate e giochi online ne risentono)")
        return String(format: "Download: %.0f Mbit/s\nUpload: %.0f Mbit/s\nReattività sotto carico: %@ (%.0f RPM)", giu, su, reattivita, rpm)
    }

    // MARK: Riavvio

    /// App aperte con finestre (per avvisare di salvare il lavoro).
    static func appAperte() -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { $0.localizedName }.sorted()
    }

    /// Riavvio normale di macOS: le app chiedono di salvare i documenti aperti.
    static func riavvia() -> String? {
        let r = Regia.esegui("/usr/bin/osascript", ["-e", "tell application \"loginwindow\" to «event aevtrrst»"])
        return r.ok ? nil : r.errore
    }
}
