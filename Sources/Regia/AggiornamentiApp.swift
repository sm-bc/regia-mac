import Foundation
import AppKit

/// Un'app installata vista dal controllo aggiornamenti.
struct AppAggiornabile: Identifiable, Equatable {
    enum Fonte: Equatable {
        case appStore(trackId: Int)
        case sparkle
        case homebrew(token: String, formula: Bool)
        case automatica
        case sconosciuta
    }
    enum Esito: Equatable { case disponibile, aggiornata, nonVerificabile }

    let id: String
    let nome: String
    let percorso: URL?
    let bundleID: String
    let versione: String
    var nuova: String? = nil
    var fonte: Fonte
    var esito: Esito
    var nota: String? = nil
    var pagina: URL? = nil

    var nomeFonte: String {
        switch fonte {
        case .appStore: return "App Store"
        case .sparkle: return L("Developer site", "Sito dello sviluppatore")
        case .homebrew: return "Homebrew"
        case .automatica: return L("Updates itself", "Si aggiorna da sola")
        case .sconosciuta: return L("Unknown", "Sconosciuta")
        }
    }
}

struct RisultatoAggiornamentiApp {
    var voci: [AppAggiornabile]
    var data: Date
    var disponibili: [AppAggiornabile] { voci.filter { $0.esito == .disponibile } }
}

/// Dati di un'app nell'App Store (servizio pubblico di ricerca di Apple).
struct InfoStore: Equatable {
    let versione: String; let trackId: Int; let pagina: String?; let sistemaMinimo: String?
    /// false = scheda unica iPhone/iPad/Mac: la versione indicata può essere quella per iPhone.
    var perMac = true
}

/// L'ultima versione annunciata nel feed Sparkle (appcast) di un'app.
struct VoceAppcast: Equatable { let versione: String?; let versioneBreve: String?; let link: String? }

enum AggiornamentiApp {
    /// Controlla tutte le app: App Store, feed Sparkle degli sviluppatori e Homebrew. Non installa niente.
    static func controlla(_ app: [AppInstallata]) async -> RisultatoAggiornamentiApp {
        let sistema = versioneSistema()
        var voci: [AppAggiornabile] = []

        let candidate = app.filter { $0.bundleID != Aggiornamenti.identificativo && !$0.percorso.path.hasPrefix("/System") }
        let store = candidate.filter(\.daAppStore)
        let altre = candidate.filter { !$0.daAppStore }

        // 1. App Store: una sola richiesta ad Apple per gruppi di 50 app
        var infoStore: [String: InfoStore] = [:]
        for gruppo in stride(from: 0, to: store.count, by: 50).map({ Array(store[$0..<min($0 + 50, store.count)]) }) {
            infoStore.merge(await cercaAppStore(gruppo.map(\.bundleID), entita: "macSoftware")) { a, _ in a }
        }
        let mancanti = store.map(\.bundleID).filter { infoStore[$0] == nil }
        if !mancanti.isEmpty { infoStore.merge(await cercaAppStore(mancanti, entita: nil)) { a, _ in a } }   // app per iPad su Mac
        for a in store {
            var v = AppAggiornabile(id: a.id, nome: a.nome, percorso: a.percorso, bundleID: a.bundleID, versione: a.versione,
                                    fonte: .appStore(trackId: 0), esito: .nonVerificabile)
            if let i = infoStore[a.bundleID] {
                v.fonte = .appStore(trackId: i.trackId)
                v.pagina = URL(string: "macappstore://apps.apple.com/app/id\(i.trackId)")
                let primo = { (s: String) in s.split(separator: ".").first.map(String.init) ?? s }
                if !i.perMac && primo(i.versione) != primo(a.versione) {
                    // Es. CapCut: l'App Store indica la versione per iPhone (20.x), sul Mac c'è la 9.x
                    v.nota = L("The App Store lists the iPhone version (\(i.versione)): check the Mac version there",
                               "L'App Store indica la versione per iPhone (\(i.versione)): controlla lì quella per Mac")
                } else if piuNuova(i.versione, di: a.versione) {
                    if let m = i.sistemaMinimo, piuNuova(m, di: sistema) {
                        v.esito = .aggiornata
                        v.nota = L("Version \(i.versione) requires macOS \(m)", "La versione \(i.versione) richiede macOS \(m)")
                    } else {
                        v.esito = .disponibile; v.nuova = i.versione
                    }
                } else { v.esito = .aggiornata }
            } else {
                v.nota = L("Not found in the App Store of your country", "Non trovata nell'App Store del tuo paese")
            }
            voci.append(v)
        }

        // 2. Feed Sparkle degli sviluppatori (in parallelo, al massimo 10 secondi ciascuno)
        let conFeed = altre.compactMap { a -> (AppInstallata, URL, String?)? in
            guard let f = feedSparkle(a) else { return nil }
            return (a, f, versioneBuild(a))
        }
        let risposte = await withTaskGroup(of: (String, VoceAppcast?).self) { g -> [String: VoceAppcast?] in
            for (a, feed, _) in conFeed {
                g.addTask { (a.id, await scaricaAppcast(feed, sistema: sistema)) }
            }
            var r: [String: VoceAppcast?] = [:]
            for await (id, v) in g { r[id] = v }
            return r
        }
        let idFeed = Set(conFeed.map { $0.0.id })
        for (a, _, build) in conFeed {
            var v = AppAggiornabile(id: a.id, nome: a.nome, percorso: a.percorso, bundleID: a.bundleID, versione: a.versione,
                                    fonte: .sparkle, esito: .nonVerificabile)
            if let voce = risposte[a.id] ?? nil {
                v.pagina = voce.link.flatMap(URL.init(string:))
                if let nuova = aggiornamentoSparkle(voce, breve: a.versione, build: build) {
                    v.esito = .disponibile; v.nuova = nuova
                } else { v.esito = .aggiornata }
            } else {
                v.nota = L("The developer's update feed didn't respond", "Il sito degli aggiornamenti dello sviluppatore non ha risposto")
            }
            voci.append(v)
        }

        // 3. App che si aggiornano da sole, o che non si possono controllare
        for a in altre where !idFeed.contains(a.id) {
            let auto = siAggiornaDaSola(a)
            voci.append(AppAggiornabile(id: a.id, nome: a.nome, percorso: a.percorso, bundleID: a.bundleID, versione: a.versione,
                                        fonte: auto == nil ? .sconosciuta : .automatica, esito: .nonVerificabile,
                                        nota: auto ?? L("Check the developer's website", "Controlla sul sito dello sviluppatore")))
        }

        // 4. Homebrew (se installato)
        voci += await homebrew()

        voci.sort { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
        return RisultatoAggiornamentiApp(voci: voci, data: Date())
    }

    // MARK: Versioni

    /// "2.10" > "2.9"; "26.45.75" > "26.45.7"; ignora lettere e suffissi ("3.0b2" → 3.0.2).
    static func piuNuova(_ a: String, di b: String) -> Bool {
        func numeri(_ s: String) -> [Int] { s.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 } }
        let x = numeri(a), y = numeri(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func versioneSistema() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static func infoPlist(_ a: AppInstallata) -> [String: Any] {
        (NSDictionary(contentsOf: a.percorso.appendingPathComponent("Contents/Info.plist")) as? [String: Any]) ?? [:]
    }

    static func versioneBuild(_ a: AppInstallata) -> String? { infoPlist(a)["CFBundleVersion"] as? String }

    /// Sparkle confronta sparkle:version con CFBundleVersion; se manca usa la versione "breve".
    static func aggiornamentoSparkle(_ v: VoceAppcast, breve: String, build: String?) -> String? {
        if let nv = v.versione, let b = build, !b.isEmpty {
            return piuNuova(nv, di: b) ? (v.versioneBreve ?? nv) : nil
        }
        if let nb = v.versioneBreve ?? v.versione, !breve.isEmpty {
            return piuNuova(nb, di: breve) ? nb : nil
        }
        return nil
    }

    // MARK: App Store

    static func cercaAppStore(_ ids: [String], entita: String?) async -> [String: InfoStore] {
        guard !ids.isEmpty else { return [:] }
        let paese = (Locale.current.region?.identifier ?? "US").lowercased()
        var c = URLComponents(string: "https://itunes.apple.com/lookup")!
        c.queryItems = [URLQueryItem(name: "bundleId", value: ids.joined(separator: ",")), URLQueryItem(name: "country", value: paese)]
        if let e = entita { c.queryItems?.append(URLQueryItem(name: "entity", value: e)) }
        guard let url = c.url,
              let r = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15)),
              (r.1 as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
        return analizzaLookup(r.0)
    }

    static func analizzaLookup(_ dati: Data) -> [String: InfoStore] {
        guard let d = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
              let risultati = d["results"] as? [[String: Any]] else { return [:] }
        var r: [String: InfoStore] = [:]
        for x in risultati {
            guard let id = x["bundleId"] as? String, let v = x["version"] as? String, let t = x["trackId"] as? Int else { continue }
            r[id] = InfoStore(versione: v, trackId: t, pagina: x["trackViewUrl"] as? String, sistemaMinimo: x["minimumOsVersion"] as? String,
                              perMac: (x["kind"] as? String) == "mac-software")
        }
        return r
    }

    // MARK: Sparkle

    /// Indirizzo del feed: nell'Info.plist o nelle preferenze dell'app. Solo https.
    static func feedSparkle(_ a: AppInstallata) -> URL? {
        var feed = infoPlist(a)["SUFeedURL"] as? String
        if feed == nil { feed = CFPreferencesCopyAppValue("SUFeedURL" as CFString, a.bundleID as CFString) as? String }
        guard let f = feed?.trimmingCharacters(in: .whitespaces), let u = URL(string: f), u.scheme == "https" else { return nil }
        return u
    }

    static func scaricaAppcast(_ url: URL, sistema: String) async -> VoceAppcast? {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        r.setValue("Regia/\(Aggiornamenti.versioneAttuale)", forHTTPHeaderField: "User-Agent")
        guard let x = try? await URLSession.shared.data(for: r),
              (x.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return analizzaAppcast(x.0, sistema: sistema)
    }

    /// Legge l'appcast e restituisce la versione più alta adatta a questo Mac (esclusi canali beta e altri sistemi).
    static func analizzaAppcast(_ dati: Data, sistema: String) -> VoceAppcast? {
        let lettore = LettoreAppcast()
        let p = XMLParser(data: dati)
        p.delegate = lettore
        guard p.parse() else { return nil }
        let adatte = lettore.voci.filter { v in
            v.canale == nil && v.os != "windows" && !(v.sistemaMinimo.map { piuNuova($0, di: sistema) } ?? false)
                && (v.versione != nil || v.versioneBreve != nil)
        }
        let migliore = adatte.max { a, b in
            piuNuova(b.versione ?? b.versioneBreve ?? "0", di: a.versione ?? a.versioneBreve ?? "0")
        }
        return migliore.map { VoceAppcast(versione: $0.versione, versioneBreve: $0.versioneBreve, link: $0.link) }
    }

    private final class LettoreAppcast: NSObject, XMLParserDelegate {
        struct Voce { var versione: String?; var versioneBreve: String?; var sistemaMinimo: String?; var canale: String?; var os: String?; var link: String? }
        var voci: [Voce] = []
        private var corrente: Voce?
        private var testo = ""

        func parser(_ parser: XMLParser, didStartElement nome: String, namespaceURI: String?, qualifiedName: String?,
                    attributes a: [String: String] = [:]) {
            testo = ""
            if nome == "item" { corrente = Voce() }
            if nome == "enclosure", corrente != nil {
                if let v = a["sparkle:version"] { corrente?.versione = v }
                if let v = a["sparkle:shortVersionString"] { corrente?.versioneBreve = v }
                if let v = a["sparkle:os"] { corrente?.os = v.lowercased() }
            }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) { testo += s }
        func parser(_ parser: XMLParser, didEndElement nome: String, namespaceURI: String?, qualifiedName: String?) {
            let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
            switch nome {
            case "item": if let c = corrente { voci.append(c) }; corrente = nil
            case "sparkle:version": if !t.isEmpty { corrente?.versione = t }
            case "sparkle:shortVersionString": if !t.isEmpty { corrente?.versioneBreve = t }
            case "sparkle:minimumSystemVersion": if !t.isEmpty { corrente?.sistemaMinimo = t }
            case "sparkle:channel": if !t.isEmpty { corrente?.canale = t }
            case "sparkle:releaseNotesLink", "link": if !t.isEmpty, corrente?.link == nil { corrente?.link = t }
            default: break
            }
            testo = ""
        }
    }

    // MARK: App che si aggiornano da sole

    static func siAggiornaDaSola(_ a: AppInstallata) -> String? {
        let fm = FileManager.default
        let c = a.percorso.appendingPathComponent("Contents")
        let id = a.bundleID.lowercased()
        let note: [(String, String)] = [
            ("com.google.", L("Updates itself (Google)", "Si aggiorna da sola (Google)")),
            ("com.microsoft.", L("Updates with Microsoft AutoUpdate", "Si aggiorna con Microsoft AutoUpdate")),
            ("org.mozilla.", L("Updates itself (Firefox › About)", "Si aggiorna da sola (Firefox › Informazioni)")),
            ("com.valvesoftware.", L("Steam updates itself at launch", "Steam si aggiorna da solo all'apertura")),
            ("com.adobe.", L("Updates with Creative Cloud", "Si aggiorna con Creative Cloud")),
            ("us.zoom.", L("Updates itself (zoom.us › Check for Updates)", "Si aggiorna da sola (zoom.us › Controlla aggiornamenti)")),
        ]
        if id.hasPrefix("com.google.chrome.app.") || id.hasPrefix("com.apple.safari.webapp") {
            return L("Web app: always up to date", "App web: sempre aggiornata")
        }
        for (prefisso, n) in note where id.hasPrefix(prefisso) { return n }
        if id.hasPrefix("com.apple.") { return L("Updated together with macOS", "Si aggiorna insieme a macOS") }
        if fm.fileExists(atPath: c.appendingPathComponent("Frameworks/Squirrel.framework").path)
            || fm.fileExists(atPath: c.appendingPathComponent("Resources/app-update.yml").path) {
            return L("Updates itself when you open it", "Si aggiorna da sola quando la apri")
        }
        if fm.fileExists(atPath: c.appendingPathComponent("Frameworks/Sparkle.framework").path) {
            return L("Updates itself: app menu › Check for Updates", "Si aggiorna da sola: menu dell'app › Controlla aggiornamenti")
        }
        return nil
    }

    // MARK: Homebrew

    static func percorsoBrew() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func homebrew() async -> [AppAggiornabile] {
        guard let brew = percorsoBrew() else { return [] }
        let r = await Task.detached {
            esegui(brew, ["outdated", "--json=v2"], ambiente: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"])
        }.value
        guard r.ok else { return [] }
        return analizzaBrew(Data(r.uscita.utf8))
    }

    static func analizzaBrew(_ dati: Data) -> [AppAggiornabile] {
        guard let d = try? JSONSerialization.jsonObject(with: dati) as? [String: Any] else { return [] }
        var voci: [AppAggiornabile] = []
        for (chiave, formula) in [("casks", false), ("formulae", true)] {
            for x in (d[chiave] as? [[String: Any]]) ?? [] {
                guard let nome = x["name"] as? String, nome.range(of: #"^[A-Za-z0-9@._+-]+$"#, options: .regularExpression) != nil else { continue }
                let installata = (x["installed_versions"] as? [String])?.last ?? ""
                let nuova = x["current_version"] as? String
                voci.append(AppAggiornabile(id: "brew.\(chiave).\(nome)", nome: nome, percorso: nil, bundleID: nome, versione: installata,
                                            nuova: nuova, fonte: .homebrew(token: nome, formula: formula), esito: .disponibile,
                                            nota: formula ? L("Command-line tool", "Strumento da Terminale") : nil))
            }
        }
        return voci
    }

    /// Apre il Terminale con il comando di Homebrew, così vedi tutto e scrivi tu la password se serve.
    static func aggiornaConBrew(_ token: String, formula: Bool) -> String? {
        guard let brew = percorsoBrew(), token.range(of: #"^[A-Za-z0-9@._+-]+$"#, options: .regularExpression) != nil else {
            return L("Homebrew not found.", "Homebrew non trovato.")
        }
        let comando = "\(brew) upgrade \(formula ? "" : "--cask ")\(token)"
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(comando)\"\nend tell"
        let r = esegui("/usr/bin/osascript", ["-e", script])
        return r.ok ? nil : r.errore
    }
}
