import Foundation

// MARK: - Valori e azioni

enum Valore: Codable, Hashable {
    case bool(Bool), int(Int), float(Double), string(String)

    /// Argomenti per `defaults write`.
    var argomenti: [String] {
        switch self {
        case .bool(let b): return ["-bool", b ? "true" : "false"]
        case .int(let i): return ["-int", String(i)]
        case .float(let d): return ["-float", String(d)]
        case .string(let s): return ["-string", s]
        }
    }

    var testo: String {
        switch self {
        case .bool(let b): return b ? "sì" : "no"
        case .int(let i): return String(i)
        case .float(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .string(let s): return s
        }
    }

    /// Confronta col valore letto da `defaults read`.
    func coincide(con letto: String?) -> Bool {
        guard let l = letto?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        switch self {
        case .bool(let b):
            if ["1", "true", "yes"].contains(l) { return b }
            if ["0", "false", "no"].contains(l) { return !b }
            return false
        case .int(let i): return Double(l).map { $0 == Double(i) } ?? false
        case .float(let d): return Double(l).map { abs($0 - d) < 0.0001 } ?? false
        case .string(let s): return l == s.lowercased()
        }
    }
}

enum Ambito: String, Codable, Hashable {
    case batteria = "-b", alimentatore = "-c"
    var nome: String { self == .batteria ? "a batteria" : "con l'alimentatore" }
    var sezionePmset: String { self == .batteria ? "Battery Power:" : "AC Power:" }
}

enum Azione: Hashable {
    case preferenza(dominio: String, chiave: String, valore: Valore)
    case energia(ambito: Ambito, chiave: String, valore: Int)
}

enum Categoria: String, CaseIterable, Identifiable {
    case velocita = "Velocità interfaccia"
    case dock = "Dock e Scrivanie"
    case finder = "Finder e file"
    case tastiera = "Tastiera"
    case screenshot = "Screenshot"
    case energia = "Energia e batteria"
    case privacy = "Privacy"
    var id: String { rawValue }
    var icona: String {
        switch self {
        case .velocita: return "hare"
        case .dock: return "dock.rectangle"
        case .finder: return "folder"
        case .tastiera: return "keyboard"
        case .screenshot: return "camera.viewfinder"
        case .energia: return "battery.75percent"
        case .privacy: return "hand.raised"
        }
    }
}

struct Ritocco: Identifiable, Hashable {
    let id: String
    let titolo: String
    let spiegazione: String
    let categoria: Categoria
    let azione: Azione
    /// Processo da riavviare perché la modifica si veda (Dock, Finder, SystemUIServer).
    var riavvia: String? = nil
    var nota: String? = nil

    var serveAdmin: Bool { if case .energia = azione { return true }; return false }
    var valoreNuovoTesto: String {
        switch azione {
        case .preferenza(_, _, let v): return v.testo
        case .energia(_, let chiave, let v): return Catalogo.testoEnergia(chiave: chiave, valore: v)
        }
    }
}

// MARK: - Profili

struct Profilo: Identifiable {
    let id: String
    let nome: String
    let icona: String
    let descrizione: String
    let ritocchi: [String]
}

// MARK: - Catalogo

enum Catalogo {
    static let ritocchi: [Ritocco] = [
        // Velocità interfaccia
        Ritocco(id: "ui.noAnimazioniFinestre", titolo: "Finestre senza animazione",
                spiegazione: "Le finestre nuove si aprono subito, senza effetto zoom.", categoria: .velocita,
                azione: .preferenza(dominio: "NSGlobalDomain", chiave: "NSAutomaticWindowAnimationsEnabled", valore: .bool(false)),
                nota: "Vale per le app aperte dopo la modifica."),
        Ritocco(id: "ui.ridimensionaVeloce", titolo: "Ridimensionamento istantaneo",
                spiegazione: "Fogli e finestre cambiano dimensione senza attesa.", categoria: .velocita,
                azione: .preferenza(dominio: "NSGlobalDomain", chiave: "NSWindowResizeTime", valore: .float(0.001)),
                nota: "Vale per le app aperte dopo la modifica."),
        Ritocco(id: "mission.veloce", titolo: "Mission Control più rapido",
                spiegazione: "Animazione di Mission Control quasi istantanea.", categoria: .velocita,
                azione: .preferenza(dominio: "com.apple.dock", chiave: "expose-animation-duration", valore: .float(0.1)),
                riavvia: "Dock"),
        Ritocco(id: "dock.noAnimazioneApertura", titolo: "Niente rimbalzo all'apertura",
                spiegazione: "Le icone nel Dock non saltellano quando apri un'app.", categoria: .velocita,
                azione: .preferenza(dominio: "com.apple.dock", chiave: "launchanim", valore: .bool(false)),
                riavvia: "Dock"),

        // Dock e Scrivanie
        Ritocco(id: "dock.nascondi", titolo: "Nascondi il Dock",
                spiegazione: "Più spazio sullo schermo: il Dock compare portando il mouse in basso.", categoria: .dock,
                azione: .preferenza(dominio: "com.apple.dock", chiave: "autohide", valore: .bool(true)),
                riavvia: "Dock"),
        Ritocco(id: "dock.ritardo0", titolo: "Dock subito, senza attesa",
                spiegazione: "Il Dock nascosto compare appena tocchi il bordo.", categoria: .dock,
                azione: .preferenza(dominio: "com.apple.dock", chiave: "autohide-delay", valore: .float(0)),
                riavvia: "Dock"),
        Ritocco(id: "dock.animazioneVeloce", titolo: "Comparsa del Dock veloce",
                spiegazione: "L'animazione del Dock nascosto dura un terzo.", categoria: .dock,
                azione: .preferenza(dominio: "com.apple.dock", chiave: "autohide-time-modifier", valore: .float(0.3)),
                riavvia: "Dock"),
        Ritocco(id: "dock.noRecenti", titolo: "Niente app recenti nel Dock",
                spiegazione: "Il Dock mostra solo le app che hai scelto tu.", categoria: .dock,
                azione: .preferenza(dominio: "com.apple.dock", chiave: "show-recents", valore: .bool(false)),
                riavvia: "Dock"),
        Ritocco(id: "dock.effettoScala", titolo: "Riduci a icona con effetto semplice",
                spiegazione: "Effetto \"Scala\" al posto di \"Genio\": più leggero.", categoria: .dock,
                azione: .preferenza(dominio: "com.apple.dock", chiave: "mineffect", valore: .string("scale")),
                riavvia: "Dock"),
        Ritocco(id: "dock.noRiordinaScrivanie", titolo: "Scrivanie sempre nello stesso ordine",
                spiegazione: "macOS non riordina le Scrivanie in base all'uso.", categoria: .dock,
                azione: .preferenza(dominio: "com.apple.dock", chiave: "mru-spaces", valore: .bool(false)),
                riavvia: "Dock"),

        // Finder e file
        Ritocco(id: "finder.estensioni", titolo: "Mostra le estensioni dei file",
                spiegazione: "Vedi sempre .pdf, .jpg, .docx…", categoria: .finder,
                azione: .preferenza(dominio: "NSGlobalDomain", chiave: "AppleShowAllExtensions", valore: .bool(true)),
                riavvia: "Finder"),
        Ritocco(id: "finder.barraPercorso", titolo: "Barra del percorso nel Finder",
                spiegazione: "In fondo alla finestra vedi in che cartella sei.", categoria: .finder,
                azione: .preferenza(dominio: "com.apple.finder", chiave: "ShowPathbar", valore: .bool(true)),
                riavvia: "Finder"),
        Ritocco(id: "finder.barraStato", titolo: "Barra di stato nel Finder",
                spiegazione: "Numero di elementi e spazio libero in fondo alla finestra.", categoria: .finder,
                azione: .preferenza(dominio: "com.apple.finder", chiave: "ShowStatusBar", valore: .bool(true)),
                riavvia: "Finder"),
        Ritocco(id: "finder.cartellePrima", titolo: "Cartelle in cima",
                spiegazione: "Nelle liste le cartelle vengono prima dei file.", categoria: .finder,
                azione: .preferenza(dominio: "com.apple.finder", chiave: "_FXSortFoldersFirst", valore: .bool(true)),
                riavvia: "Finder"),
        Ritocco(id: "finder.cercaQui", titolo: "Cerca nella cartella aperta",
                spiegazione: "La ricerca del Finder parte dalla cartella in cui sei, non da tutto il Mac.", categoria: .finder,
                azione: .preferenza(dominio: "com.apple.finder", chiave: "FXDefaultSearchScope", valore: .string("SCcf")),
                riavvia: "Finder"),
        Ritocco(id: "finder.noAvvisoEstensione", titolo: "Niente avviso cambiando estensione",
                spiegazione: "Rinomini .txt in .md senza la finestra di conferma.", categoria: .finder,
                azione: .preferenza(dominio: "com.apple.finder", chiave: "FXEnableExtensionChangeWarning", valore: .bool(false)),
                riavvia: "Finder"),
        Ritocco(id: "file.noDSStoreRete", titolo: "Niente file .DS_Store sui dischi di rete",
                spiegazione: "Il Mac non sporca le cartelle condivise con file nascosti.", categoria: .finder,
                azione: .preferenza(dominio: "com.apple.desktopservices", chiave: "DSDontWriteNetworkStores", valore: .bool(true))),
        Ritocco(id: "file.noDSStoreUSB", titolo: "Niente file .DS_Store sulle chiavette",
                spiegazione: "Chiavette e dischi esterni restano puliti (utile con Windows).", categoria: .finder,
                azione: .preferenza(dominio: "com.apple.desktopservices", chiave: "DSDontWriteUSBStores", valore: .bool(true))),
        Ritocco(id: "file.salvaInLocale", titolo: "Salva sul Mac, non su iCloud",
                spiegazione: "I nuovi documenti propongono una cartella del Mac invece di iCloud.", categoria: .finder,
                azione: .preferenza(dominio: "NSGlobalDomain", chiave: "NSDocumentSaveNewDocumentsToCloud", valore: .bool(false))),

        // Tastiera
        Ritocco(id: "tastiera.ripetizioneVeloce", titolo: "Ripetizione tasti veloce",
                spiegazione: "Tenendo premuto un tasto (es. Cancella) ripete più in fretta.", categoria: .tastiera,
                azione: .preferenza(dominio: "NSGlobalDomain", chiave: "KeyRepeat", valore: .int(2)),
                nota: "Serve uscire e rientrare nell'account."),
        Ritocco(id: "tastiera.ritardoBreve", titolo: "Ritardo prima della ripetizione breve",
                spiegazione: "La ripetizione parte prima.", categoria: .tastiera,
                azione: .preferenza(dominio: "NSGlobalDomain", chiave: "InitialKeyRepeat", valore: .int(15)),
                nota: "Serve uscire e rientrare nell'account."),

        // Screenshot
        Ritocco(id: "screenshot.noOmbra", titolo: "Screenshot di finestre senza ombra",
                spiegazione: "Catture più pulite e file più leggeri.", categoria: .screenshot,
                azione: .preferenza(dominio: "com.apple.screencapture", chiave: "disable-shadow", valore: .bool(true)),
                riavvia: "SystemUIServer"),
        Ritocco(id: "screenshot.png", titolo: "Screenshot in PNG",
                spiegazione: "Formato senza perdita di qualità, adatto alla grafica.", categoria: .screenshot,
                azione: .preferenza(dominio: "com.apple.screencapture", chiave: "type", valore: .string("png")),
                riavvia: "SystemUIServer"),

        // Energia (servono i permessi di amministratore)
        Ritocco(id: "energia.batteriaRisparmio", titolo: "Risparmio energetico a batteria",
                spiegazione: "Quando non sei in carica il Mac consuma meno e dura di più.", categoria: .energia,
                azione: .energia(ambito: .batteria, chiave: "lowpowermode", valore: 1)),
        Ritocco(id: "energia.batteriaSchermo", titolo: "Schermo spento dopo 3 minuti a batteria",
                spiegazione: "Lo schermo è la cosa che consuma di più.", categoria: .energia,
                azione: .energia(ambito: .batteria, chiave: "displaysleep", valore: 3)),
        Ritocco(id: "energia.batteriaNoPowerNap", titolo: "Niente Power Nap a batteria",
                spiegazione: "In stop a batteria il Mac non si sveglia per mail e aggiornamenti.", categoria: .energia,
                azione: .energia(ambito: .batteria, chiave: "powernap", valore: 0)),
        Ritocco(id: "energia.alimentatorePiena", titolo: "Piena potenza con l'alimentatore",
                spiegazione: "In carica il Mac non va mai in risparmio energetico.", categoria: .energia,
                azione: .energia(ambito: .alimentatore, chiave: "lowpowermode", valore: 0)),

        // Privacy
        Ritocco(id: "privacy.noPubblicita", titolo: "Niente pubblicità personalizzata Apple",
                spiegazione: "Apple non usa i tuoi dati per scegliere gli annunci.", categoria: .privacy,
                azione: .preferenza(dominio: "com.apple.AdLib", chiave: "allowApplePersonalizedAdvertising", valore: .bool(false))),
        Ritocco(id: "privacy.noCrashReporter", titolo: "Niente finestre di segnalazione arresti",
                spiegazione: "Se un'app si chiude da sola ricevi una notifica, non una finestra.", categoria: .privacy,
                azione: .preferenza(dominio: "com.apple.CrashReporter", chiave: "UseUNC", valore: .int(1))),
    ]

    static let profili: [Profilo] = [
        Profilo(id: "produttivita", nome: "Produttività", icona: "briefcase",
                descrizione: "Finder più chiaro, Dock pulito, tastiera reattiva. Per ufficio, mail e gestionale.",
                ritocchi: ["finder.estensioni", "finder.barraPercorso", "finder.barraStato", "finder.cartellePrima",
                           "finder.cercaQui", "finder.noAvvisoEstensione", "file.salvaInLocale", "dock.noRecenti",
                           "dock.noRiordinaScrivanie", "tastiera.ripetizioneVeloce", "tastiera.ritardoBreve",
                           "ui.ridimensionaVeloce"]),
        Profilo(id: "grafica", nome: "Grafica e design", icona: "paintpalette",
                descrizione: "Estensioni visibili, screenshot puliti in PNG, chiavette senza file nascosti.",
                ritocchi: ["finder.estensioni", "finder.barraPercorso", "finder.noAvvisoEstensione",
                           "file.noDSStoreRete", "file.noDSStoreUSB", "file.salvaInLocale",
                           "screenshot.noOmbra", "screenshot.png", "dock.noRiordinaScrivanie"]),
        Profilo(id: "gaming", nome: "Gaming", icona: "gamecontroller",
                descrizione: "Tutto lo schermo al gioco, animazioni ridotte, piena potenza in carica.",
                ritocchi: ["dock.nascondi", "dock.ritardo0", "dock.animazioneVeloce", "dock.noAnimazioneApertura",
                           "ui.noAnimazioniFinestre", "ui.ridimensionaVeloce", "mission.veloce",
                           "dock.noRiordinaScrivanie", "energia.alimentatorePiena"]),
        Profilo(id: "efficienza", nome: "Efficienza", icona: "leaf",
                descrizione: "Più autonomia a batteria: risparmio energetico, schermo che si spegne prima, meno animazioni.",
                ritocchi: ["energia.batteriaRisparmio", "energia.batteriaSchermo", "energia.batteriaNoPowerNap",
                           "dock.noAnimazioneApertura", "ui.noAnimazioniFinestre", "dock.effettoScala"]),
    ]

    static func ritocco(_ id: String) -> Ritocco? { ritocchi.first { $0.id == id } }

    static func testoEnergia(chiave: String, valore: Int?) -> String {
        guard let v = valore else { return "non impostato" }
        switch chiave {
        case "displaysleep", "sleep": return v == 0 ? "mai" : "\(v) min"
        default: return v == 0 ? "no" : "sì"
        }
    }

    /// Consigli che macOS non permette di cambiare da un'app: apriamo l'impostazione giusta.
    static let consigliManuali: [(titolo: String, spiegazione: String, url: String)] = [
        ("Riduci trasparenza e movimento", "Accessibilità › Schermo: meno effetti grafici, Mac più scattante.",
         "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"),
        ("Elementi di login e in background", "Generali › Elementi di login: togli le app che non ti servono all'avvio.",
         "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
        ("Archiviazione", "Generali › Archiviazione: consigli di Apple per liberare spazio.",
         "x-apple.systempreferences:com.apple.settings.Storage"),
        ("Batteria", "Caricamento ottimizzato e stato di salute della batteria.",
         "x-apple.systempreferences:com.apple.Battery-Settings.extension"),
        ("Spotlight", "Escludi dall'indicizzazione cartelle enormi che non cerchi mai.",
         "x-apple.systempreferences:com.apple.Spotlight-Settings.extension"),
    ]
}
