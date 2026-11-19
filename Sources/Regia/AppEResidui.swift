import Foundation
import AppKit

// MARK: - Residuo: un file o una cartella lasciati da un'app

struct Residuo: Identifiable, Hashable {
    enum Tipo: String { case preferenze = "Preferenze", supporto = "Dati dell'app", cache = "Cache",
                        contenitore = "Contenitore", stato = "Stato finestre", avvio = "Avvio automatico",
                        log = "Log", web = "Dati web", altro = "Altro" }
    var id: String { percorso.path }
    let percorso: URL
    let tipo: Tipo
    let app: String          // nome o identificativo dell'app a cui appartiene
    var dimensione: Int64 = 0
    /// Può contenere documenti o impostazioni importanti: non scelto di serie.
    var delicato: Bool { tipo == .supporto || tipo == .contenitore }
    var descrizione: String { "\(app) · \(tipo.rawValue)" }
}

enum Residui {
    /// Dove le app lasciano i loro file dentro la Libreria dell'utente.
    static let posti: [(cartella: String, tipo: Residuo.Tipo)] = [
        ("Library/Preferences", .preferenze),
        ("Library/Application Support", .supporto),
        ("Library/Caches", .cache),
        ("Library/Containers", .contenitore),
        ("Library/Group Containers", .contenitore),
        ("Library/Saved Application State", .stato),
        ("Library/LaunchAgents", .avvio),
        ("Library/Logs", .log),
        ("Library/HTTPStorages", .web),
        ("Library/WebKit", .web),
        ("Library/Application Scripts", .altro),
        ("Library/Cookies", .web),
    ]

    /// Cerca i file di un'app (installata o no) per identificativo e nome esatto.
    static func trova(bundleID: String, nome: String?, home: URL) -> [Residuo] {
        let fm = FileManager.default
        let idMin = bundleID.lowercased()
        let nomeMin = nome?.lowercased()
        var trovati: [Residuo] = []
        for (cartella, tipo) in posti {
            let dir = home.appendingPathComponent(cartella)
            guard let voci = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for v in voci {
                let vm = v.lowercased()
                var corrisponde = vm == idMin || vm.hasPrefix(idMin + ".") || vm == idMin + ".plist"
                    || vm == idMin + ".savedstate" || vm == idMin + ".binarycookies"
                // Group Containers: "TEAMID.com.azienda.app"
                if tipo == .contenitore && cartella.hasSuffix("Group Containers") && vm.hasSuffix("." + idMin) { corrisponde = true }
                // Cartelle col nome esatto dell'app (es. Application Support/Steam)
                if let n = nomeMin, n.count >= 4, vm == n, tipo == .supporto || tipo == .cache || tipo == .log { corrisponde = true }
                if corrisponde {
                    let url = dir.appendingPathComponent(v)
                    trovati.append(Residuo(percorso: url, tipo: tipo, app: nome ?? bundleID, dimensione: Pulizia.dimensione(url)))
                }
            }
        }
        return trovati
    }

    /// Residui di app che non sono più sul Mac + avvii automatici che puntano a programmi cancellati.
    static func orfani(home: URL, simulazione: Bool) -> [Residuo] {
        let fm = FileManager.default
        var risultato: [Residuo] = []
        var visti = Set<String>()

        // 1. Avvii automatici con il programma che non esiste più
        let agenti = home.appendingPathComponent("Library/LaunchAgents")
        for f in (try? fm.contentsOfDirectory(at: agenti, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "plist" {
            let e = ElementoAvvio.da(file: f, livello: .utente, disattivato: false)
            if !e.programma.isEmpty, e.programma.hasPrefix("/"), !fm.fileExists(atPath: e.programma) {
                risultato.append(Residuo(percorso: f, tipo: .avvio, app: e.nome, dimensione: Pulizia.dimensione(f)))
                visti.insert(f.path)
            }
        }

        // 2. Identificativi di app (com.azienda.app) senza app installata
        let elenco = AppInstallate.elenco(home: home, simulazione: simulazione)
        let installate = Set(elenco.map { $0.bundleID.lowercased() })
        let aziende = Set(installate.map(azienda))
        let parole = paroleDelleApp(home: home, simulazione: simulazione)
        var candidati = Set<String>()
        for cartella in ["Library/Preferences", "Library/Saved Application State", "Library/Containers", "Library/Caches", "Library/HTTPStorages"] {
            for v in (try? fm.contentsOfDirectory(atPath: home.appendingPathComponent(cartella).path)) ?? [] {
                var id = v
                for est in [".plist", ".savedState", ".binarycookies"] where id.hasSuffix(est) { id = String(id.dropLast(est.count)) }
                if sembraIdentificativo(id) { candidati.insert(id) }
            }
        }
        for id in candidati.sorted() {
            let idMin = id.lowercased()
            if escluso(idMin) || installate.contains(idMin) { continue }
            if installate.contains(where: { idMin.hasPrefix($0 + ".") }) { continue }   // componenti di app installate
            // Prudenza: stessa azienda di un'app installata, o col nome di un'app installata → non è un residuo
            if aziende.contains(azienda(idMin)) { continue }
            if !Set(idMin.split(whereSeparator: { ".-_ ".contains($0) }).map(String.init)).isDisjoint(with: parole) { continue }
            if !simulazione, NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { continue }
            for r in trova(bundleID: id, nome: nil, home: home) where !visti.contains(r.id) {
                visti.insert(r.id)
                risultato.append(r)
            }
        }
        return risultato
    }

    /// "com.google.Chrome" → "com.google"
    static func azienda(_ id: String) -> String { id.lowercased().split(separator: ".").prefix(2).joined(separator: ".") }

    /// Parole significative nei nomi delle app installate (anche quelle senza Info.plist leggibile).
    static func paroleDelleApp(home: URL, simulazione: Bool) -> Set<String> {
        let generiche: Set<String> = ["app", "the", "for", "and", "mac", "macos", "pro", "plus", "lite", "free", "studio", "assistant",
                                      "series", "service", "services", "utility", "helper", "update", "updater", "manager", "player",
                                      "desktop", "consumer", "drones", "launcher", "new", "rimuovi", "disinstalla", "uninstall", "remove",
                                      "google", "microsoft", "apple", "com", "org", "net"]
        let fm = FileManager.default
        let cartelle = simulazione ? [home.appendingPathComponent("Applications")]
            : [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var nomi: [String] = []
        for dir in cartelle {
            for v in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                if v.hasSuffix(".app") { nomi.append(v) }
                else { nomi += ((try? fm.contentsOfDirectory(atPath: dir.appendingPathComponent(v).path)) ?? []).filter { $0.hasSuffix(".app") } }
            }
        }
        var parole = Set<String>()
        for n in nomi {
            for p in n.dropLast(4).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where p.count >= 3 && !generiche.contains(String(p)) {
                parole.insert(String(p))
            }
        }
        return parole
    }

    static func sembraIdentificativo(_ s: String) -> Bool {
        let parti = s.split(separator: ".")
        guard parti.count >= 3, let primo = parti.first else { return false }
        return ["com", "org", "net", "io", "de", "it", "us", "co", "app", "dev", "jp", "fr", "uk", "ru", "cn", "me", "tv"]
            .contains(primo.lowercased()) && !s.contains(" ")
    }

    /// Mai toccare: macOS, Apple, Claude, Regia e strumenti di sistema.
    static func escluso(_ id: String) -> Bool {
        let protetti = ["com.apple.", "com.anthropic", "com.samuele.regia", "com.regia.", "org.cups", "com.openssh",
                        "org.python", "org.mozilla.updater", "com.microsoft.autoupdate", "com.google.keystone",
                        "com.google.googleupdater", "group.com.apple", "systemgroup.", "org.swift.", "org.llvm.",
                        "com.github.", "org.cocoapods", "org.nodejs", "org.homebrew"]
        return protetti.contains { id.hasPrefix($0) }
    }
}

// MARK: - App installate

struct AppInstallata: Identifiable, Hashable {
    var id: String { percorso.path }
    let percorso: URL
    let nome: String
    let bundleID: String
    let versione: String
    let daAppStore: Bool
    var dimensione: Int64? = nil
    var protetta: Bool { Residui.escluso(bundleID.lowercased()) || percorso.path.hasPrefix("/System") }
}

enum AppInstallate {
    static func elenco(home: URL, simulazione: Bool) -> [AppInstallata] {
        let fm = FileManager.default
        let cartelle: [URL] = simulazione
            ? [home.appendingPathComponent("Applications")]
            : [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var lista: [AppInstallata] = []
        for dir in cartelle {
            guard let voci = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for v in voci {
                if v.pathExtension == "app" { if let a = leggi(v) { lista.append(a) } }
                else if (try? v.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true, v.lastPathComponent != "Utilities" {
                    // App dentro una cartella (es. /Applications/Python 3.15/IDLE.app)
                    for w in (try? fm.contentsOfDirectory(at: v, includingPropertiesForKeys: nil)) ?? [] where w.pathExtension == "app" {
                        if let a = leggi(w) { lista.append(a) }
                    }
                }
            }
        }
        return lista.sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    static func leggi(_ url: URL) -> AppInstallata? {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String else { return nil }
        var nome = FileManager.default.displayName(atPath: url.path)
        if nome.hasSuffix(".app") { nome = String(nome.dropLast(4)) }
        let versione = (info["CFBundleShortVersionString"] as? String) ?? ""
        let store = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path)
        return AppInstallata(percorso: url, nome: nome, bundleID: id, versione: versione, daAppStore: store)
    }

    /// Un programma di disinstallazione fornito dall'azienda (es. "Disinstalla ArubaSign", "Rimuovi Autodesk Fusion").
    static func disinstallatore(per app: AppInstallata, tra tutte: [AppInstallata]) -> AppInstallata? {
        let parole = ["disinstalla", "uninstall", "rimuovi", "remove"]
        let nome = app.nome.lowercased()
        return tutte.first { a in
            let n = a.nome.lowercased()
            return a.id != app.id && parole.contains { n.hasPrefix($0) } && n.contains(nome)
        }
    }

    static func inUso(_ app: AppInstallata) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).contains { !$0.isTerminated }
    }

    /// Sposta l'app nel Cestino. Se è di sistema (installata con password) chiede al Finder, che chiede la password.
    static func spostaNelCestino(_ app: AppInstallata) -> String? {
        var risultato: NSURL?
        do { try FileManager.default.trashItem(at: app.percorso, resultingItemURL: &risultato); return nil } catch {}
        let percorso = app.percorso.path.replacingOccurrences(of: "\"", with: "\\\"")
        let r = esegui("/usr/bin/osascript", ["-e", "tell application \"Finder\" to delete (POSIX file \"\(percorso)\" as alias)"])
        return r.ok ? nil : "Non sono riuscito a spostare \(app.nome) nel Cestino: \(r.errore.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
