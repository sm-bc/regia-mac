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
        case .bool(let b): return b ? L("yes", "sì") : "no"
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
    var nome: String { self == .batteria ? L("on battery", "a batteria") : L("on power adapter", "con l'alimentatore") }
    var sezionePmset: String { self == .batteria ? "Battery Power:" : "AC Power:" }
}

enum Azione: Hashable {
    case preferenza(dominio: String, chiave: String, valore: Valore)
    case energia(ambito: Ambito, chiave: String, valore: Int)
}

enum Categoria: String, CaseIterable, Identifiable {
    case velocita, dock, finder, produttivita, tastiera, screenshot, energia, privacy
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .velocita: return L("Interface speed", "Velocità interfaccia")
        case .dock: return L("Dock and Desktop", "Dock e Scrivanie")
        case .finder: return L("Finder and files", "Finder e file")
        case .produttivita: return L("Everyday efficiency", "Efficienza di tutti i giorni")
        case .tastiera: return L("Keyboard", "Tastiera")
        case .screenshot: return L("Screenshots", "Screenshot")
        case .energia: return L("Energy and battery", "Energia e batteria")
        case .privacy: return "Privacy"
        }
    }
    var icona: String {
        switch self {
        case .velocita: return "hare"
        case .dock: return "dock.rectangle"
        case .finder: return "folder"
        case .produttivita: return "checklist"
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
    /// true = si vede solo dopo essere usciti e rientrati nell'account (o dopo un riavvio).
    var serveUscire = false
    /// Valore di un Mac appena installato per le voci di energia (nil = nessun valore fisso: non si tocca).
    var predefinitoEnergia: Int? = nil

    var serveAdmin: Bool { if case .energia = azione { return true }; return false }
    var valoreNuovoTesto: String {
        switch azione {
        case .preferenza(_, _, let v): return v.testo
        case .energia(_, let chiave, let v): return Catalogo.testoEnergia(chiave: chiave, valore: v)
        }
    }
}

// MARK: - Profili

struct Profilo: Identifiable, Codable, Hashable {
    let id: String
    let nome: String
    let icona: String
    let descrizione: String
    let ritocchi: [String]
    var avviso: String? = nil
    var personale = false
}

/// Impostazione che macOS non lascia cambiare da un'app: apriamo la pagina giusta.
struct ConsiglioManuale: Identifiable {
    var id: String { url }
    let titolo: String
    let spiegazione: String
    let url: String
    let icona: String
}

// MARK: - Catalogo

enum Catalogo {
    private static let ritocchiEN = crea(.en)
    private static let ritocchiIT = crea(.it)
    static var ritocchi: [Ritocco] { Lingua.attuale == .it ? ritocchiIT : ritocchiEN }

    // swiftlint:disable function_body_length
    private static func crea(_ l: Lingua) -> [Ritocco] {
        func t(_ en: String, _ it: String) -> String { l == .it ? it : en }
        let perAppNuove = t("Applies to apps opened after the change.", "Vale per le app aperte dopo la modifica.")
        let uscire = t("You need to log out and back in.", "Serve uscire e rientrare nell'account.")
        return [
            // Velocità interfaccia
            Ritocco(id: "ui.noAnimazioniFinestre", titolo: t("Windows without animation", "Finestre senza animazione"),
                    spiegazione: t("New windows open instantly, without the zoom effect.", "Le finestre nuove si aprono subito, senza effetto zoom."),
                    categoria: .velocita,
                    azione: .preferenza(dominio: "NSGlobalDomain", chiave: "NSAutomaticWindowAnimationsEnabled", valore: .bool(false)),
                    nota: perAppNuove),
            Ritocco(id: "ui.ridimensionaVeloce", titolo: t("Instant resizing", "Ridimensionamento istantaneo"),
                    spiegazione: t("Sheets and windows change size with no wait.", "Fogli e finestre cambiano dimensione senza attesa."),
                    categoria: .velocita,
                    azione: .preferenza(dominio: "NSGlobalDomain", chiave: "NSWindowResizeTime", valore: .float(0.001)),
                    nota: perAppNuove),
            Ritocco(id: "ui.quickLookVeloce", titolo: t("Instant Quick Look", "Quick Look istantaneo"),
                    spiegazione: t("Pressing Space on a file shows the preview with no animation.", "Premendo Spazio su un file l'anteprima compare senza animazione."),
                    categoria: .velocita,
                    azione: .preferenza(dominio: "NSGlobalDomain", chiave: "QLPanelAnimationDuration", valore: .float(0)),
                    nota: perAppNuove),
            Ritocco(id: "finder.noAnimazioni", titolo: t("Finder without animations", "Finder senza animazioni"),
                    spiegazione: t("Finder windows and Get Info panels open faster.", "Finestre del Finder e pannelli Info si aprono più in fretta."),
                    categoria: .velocita,
                    azione: .preferenza(dominio: "com.apple.finder", chiave: "DisableAllAnimations", valore: .bool(true)),
                    riavvia: "Finder"),
            Ritocco(id: "mission.veloce", titolo: t("Faster Mission Control", "Mission Control più rapido"),
                    spiegazione: t("Mission Control animation is almost instant.", "Animazione di Mission Control quasi istantanea."),
                    categoria: .velocita,
                    azione: .preferenza(dominio: "com.apple.dock", chiave: "expose-animation-duration", valore: .float(0.1)),
                    riavvia: "Dock"),
            Ritocco(id: "dock.noAnimazioneApertura", titolo: t("No bouncing on launch", "Niente rimbalzo all'apertura"),
                    spiegazione: t("Dock icons don't bounce when you open an app.", "Le icone nel Dock non saltellano quando apri un'app."),
                    categoria: .velocita,
                    azione: .preferenza(dominio: "com.apple.dock", chiave: "launchanim", valore: .bool(false)),
                    riavvia: "Dock"),

            // Dock e Scrivanie
            Ritocco(id: "dock.nascondi", titolo: t("Hide the Dock", "Nascondi il Dock"),
                    spiegazione: t("More room on screen: the Dock appears when you move the pointer to the bottom.", "Più spazio sullo schermo: il Dock compare portando il mouse in basso."),
                    categoria: .dock,
                    azione: .preferenza(dominio: "com.apple.dock", chiave: "autohide", valore: .bool(true)),
                    riavvia: "Dock"),
            Ritocco(id: "dock.ritardo0", titolo: t("Dock appears with no delay", "Dock subito, senza attesa"),
                    spiegazione: t("The hidden Dock shows up as soon as you touch the edge.", "Il Dock nascosto compare appena tocchi il bordo."),
                    categoria: .dock,
                    azione: .preferenza(dominio: "com.apple.dock", chiave: "autohide-delay", valore: .float(0)),
                    riavvia: "Dock"),
            Ritocco(id: "dock.animazioneVeloce", titolo: t("Fast Dock animation", "Comparsa del Dock veloce"),
                    spiegazione: t("The hidden Dock animation takes a third of the time.", "L'animazione del Dock nascosto dura un terzo."),
                    categoria: .dock,
                    azione: .preferenza(dominio: "com.apple.dock", chiave: "autohide-time-modifier", valore: .float(0.3)),
                    riavvia: "Dock"),
            Ritocco(id: "dock.noRecenti", titolo: t("No recent apps in the Dock", "Niente app recenti nel Dock"),
                    spiegazione: t("The Dock shows only the apps you chose.", "Il Dock mostra solo le app che hai scelto tu."),
                    categoria: .dock,
                    azione: .preferenza(dominio: "com.apple.dock", chiave: "show-recents", valore: .bool(false)),
                    riavvia: "Dock"),
            Ritocco(id: "dock.effettoScala", titolo: t("Simple minimize effect", "Riduci a icona con effetto semplice"),
                    spiegazione: t("\"Scale\" effect instead of \"Genie\": lighter.", "Effetto \"Scala\" al posto di \"Genio\": più leggero."),
                    categoria: .dock,
                    azione: .preferenza(dominio: "com.apple.dock", chiave: "mineffect", valore: .string("scale")),
                    riavvia: "Dock"),
            Ritocco(id: "dock.noRiordinaScrivanie", titolo: t("Desktops always in the same order", "Scrivanie sempre nello stesso ordine"),
                    spiegazione: t("macOS doesn't rearrange Spaces based on use.", "macOS non riordina le Scrivanie in base all'uso."),
                    categoria: .dock,
                    azione: .preferenza(dominio: "com.apple.dock", chiave: "mru-spaces", valore: .bool(false)),
                    riavvia: "Dock"),
            Ritocco(id: "dock.noClicSfondo", titolo: t("Clicking the wallpaper doesn't hide windows", "Clic sullo sfondo senza nascondere le finestre"),
                    spiegazione: t("A click on the desktop no longer moves all windows aside (only in Stage Manager).", "Un clic sulla scrivania non sposta più tutte le finestre di lato (solo in Stage Manager)."),
                    categoria: .dock,
                    azione: .preferenza(dominio: "com.apple.WindowManager", chiave: "EnableStandardClickToShowDesktop", valore: .bool(false)),
                    nota: t("If you don't see it right away, log out and back in.", "Se non si vede subito, esci e rientra nell'account.")),

            // Finder e file
            Ritocco(id: "finder.estensioni", titolo: t("Show file extensions", "Mostra le estensioni dei file"),
                    spiegazione: t("Always see .pdf, .jpg, .docx…", "Vedi sempre .pdf, .jpg, .docx…"),
                    categoria: .finder,
                    azione: .preferenza(dominio: "NSGlobalDomain", chiave: "AppleShowAllExtensions", valore: .bool(true)),
                    riavvia: "Finder"),
            Ritocco(id: "finder.barraPercorso", titolo: t("Path bar in Finder", "Barra del percorso nel Finder"),
                    spiegazione: t("See which folder you're in at the bottom of the window.", "In fondo alla finestra vedi in che cartella sei."),
                    categoria: .finder,
                    azione: .preferenza(dominio: "com.apple.finder", chiave: "ShowPathbar", valore: .bool(true)),
                    riavvia: "Finder"),
            Ritocco(id: "finder.barraStato", titolo: t("Status bar in Finder", "Barra di stato nel Finder"),
                    spiegazione: t("Number of items and free space at the bottom of the window.", "Numero di elementi e spazio libero in fondo alla finestra."),
                    categoria: .finder,
                    azione: .preferenza(dominio: "com.apple.finder", chiave: "ShowStatusBar", valore: .bool(true)),
                    riavvia: "Finder"),
            Ritocco(id: "finder.cartellePrima", titolo: t("Folders on top", "Cartelle in cima"),
                    spiegazione: t("In lists, folders come before files.", "Nelle liste le cartelle vengono prima dei file."),
                    categoria: .finder,
                    azione: .preferenza(dominio: "com.apple.finder", chiave: "_FXSortFoldersFirst", valore: .bool(true)),
                    riavvia: "Finder"),
            Ritocco(id: "finder.cercaQui", titolo: t("Search the current folder", "Cerca nella cartella aperta"),
                    spiegazione: t("Finder search starts from the folder you're in, not the whole Mac.", "La ricerca del Finder parte dalla cartella in cui sei, non da tutto il Mac."),
                    categoria: .finder,
                    azione: .preferenza(dominio: "com.apple.finder", chiave: "FXDefaultSearchScope", valore: .string("SCcf")),
                    riavvia: "Finder"),
            Ritocco(id: "finder.noAvvisoEstensione", titolo: t("No warning when changing an extension", "Niente avviso cambiando estensione"),
                    spiegazione: t("Rename .txt to .md without the confirmation dialog.", "Rinomini .txt in .md senza la finestra di conferma."),
                    categoria: .finder,
                    azione: .preferenza(dominio: "com.apple.finder", chiave: "FXEnableExtensionChangeWarning", valore: .bool(false)),
                    riavvia: "Finder"),
            Ritocco(id: "finder.cestino30", titolo: t("Empty the Trash after 30 days", "Svuota il Cestino dopo 30 giorni"),
                    spiegazione: t("Items left in the Trash for more than 30 days are deleted automatically: space doesn't fill up.", "Gli elementi nel Cestino da più di 30 giorni vengono eliminati da soli: lo spazio non si riempie."),
                    categoria: .finder,
                    azione: .preferenza(dominio: "com.apple.finder", chiave: "FXRemoveOldTrashItems", valore: .bool(true)),
                    riavvia: "Finder",
                    nota: t("Items deleted this way can't be recovered.", "Quello che viene eliminato così non si recupera.")),
            Ritocco(id: "file.noDSStoreRete", titolo: t("No .DS_Store files on network drives", "Niente file .DS_Store sui dischi di rete"),
                    spiegazione: t("Your Mac doesn't clutter shared folders with hidden files.", "Il Mac non sporca le cartelle condivise con file nascosti."),
                    categoria: .finder,
                    azione: .preferenza(dominio: "com.apple.desktopservices", chiave: "DSDontWriteNetworkStores", valore: .bool(true))),
            Ritocco(id: "file.noDSStoreUSB", titolo: t("No .DS_Store files on USB drives", "Niente file .DS_Store sulle chiavette"),
                    spiegazione: t("USB sticks and external drives stay clean (useful with Windows).", "Chiavette e dischi esterni restano puliti (utile con Windows)."),
                    categoria: .finder,
                    azione: .preferenza(dominio: "com.apple.desktopservices", chiave: "DSDontWriteUSBStores", valore: .bool(true))),
            Ritocco(id: "file.salvaInLocale", titolo: t("Save to the Mac, not iCloud", "Salva sul Mac, non su iCloud"),
                    spiegazione: t("New documents suggest a folder on the Mac instead of iCloud.", "I nuovi documenti propongono una cartella del Mac invece di iCloud."),
                    categoria: .finder,
                    azione: .preferenza(dominio: "NSGlobalDomain", chiave: "NSDocumentSaveNewDocumentsToCloud", valore: .bool(false))),

            // Efficienza di tutti i giorni
            Ritocco(id: "file.dialogoSalvaEspanso", titolo: t("Full Save dialog", "Finestra Salva completa"),
                    spiegazione: t("The Save dialog always opens expanded, with all folders visible.", "La finestra Salva si apre sempre estesa, con tutte le cartelle in vista."),
                    categoria: .produttivita,
                    azione: .preferenza(dominio: "NSGlobalDomain", chiave: "NSNavPanelExpandedStateForSaveMode", valore: .bool(true)),
                    nota: perAppNuove),
            Ritocco(id: "file.dialogoStampaEspanso", titolo: t("Full Print dialog", "Finestra Stampa completa"),
                    spiegazione: t("The Print dialog opens with all options visible.", "La finestra Stampa si apre con tutte le opzioni in vista."),
                    categoria: .produttivita,
                    azione: .preferenza(dominio: "NSGlobalDomain", chiave: "PMPrintingExpandedStateForPrint", valore: .bool(true)),
                    nota: perAppNuove),
            Ritocco(id: "stampa.chiudiCoda", titolo: t("Printer app closes by itself", "L'app della stampante si chiude da sola"),
                    spiegazione: t("When printing is finished, the printer queue in the Dock goes away.", "Finita la stampa, la coda della stampante sparisce dal Dock."),
                    categoria: .produttivita,
                    azione: .preferenza(dominio: "com.apple.print.PrintingPrefs", chiave: "Quit When Finished", valore: .bool(true))),

            // Tastiera
            Ritocco(id: "tastiera.ripetizioneVeloce", titolo: t("Fast key repeat", "Ripetizione tasti veloce"),
                    spiegazione: t("Holding a key (e.g. Delete) repeats faster.", "Tenendo premuto un tasto (es. Cancella) ripete più in fretta."),
                    categoria: .tastiera,
                    azione: .preferenza(dominio: "NSGlobalDomain", chiave: "KeyRepeat", valore: .int(2)),
                    nota: uscire, serveUscire: true),
            Ritocco(id: "tastiera.ritardoBreve", titolo: t("Short delay before repeat", "Ritardo prima della ripetizione breve"),
                    spiegazione: t("Repeat starts sooner.", "La ripetizione parte prima."),
                    categoria: .tastiera,
                    azione: .preferenza(dominio: "NSGlobalDomain", chiave: "InitialKeyRepeat", valore: .int(15)),
                    nota: uscire, serveUscire: true),

            // Screenshot
            Ritocco(id: "screenshot.noOmbra", titolo: t("Window screenshots without shadow", "Screenshot di finestre senza ombra"),
                    spiegazione: t("Cleaner captures and lighter files.", "Catture più pulite e file più leggeri."),
                    categoria: .screenshot,
                    azione: .preferenza(dominio: "com.apple.screencapture", chiave: "disable-shadow", valore: .bool(true)),
                    riavvia: "SystemUIServer"),
            Ritocco(id: "screenshot.png", titolo: t("Screenshots in PNG", "Screenshot in PNG"),
                    spiegazione: t("Lossless format, good for graphics.", "Formato senza perdita di qualità, adatto alla grafica."),
                    categoria: .screenshot,
                    azione: .preferenza(dominio: "com.apple.screencapture", chiave: "type", valore: .string("png")),
                    riavvia: "SystemUIServer"),
            Ritocco(id: "screenshot.noMiniatura", titolo: t("Screenshots saved instantly", "Screenshot salvati subito"),
                    spiegazione: t("No floating thumbnail in the corner: the file is ready right away.", "Niente miniatura nell'angolo: il file è pronto subito."),
                    categoria: .screenshot,
                    azione: .preferenza(dominio: "com.apple.screencapture", chiave: "show-thumbnail", valore: .bool(false)),
                    riavvia: "SystemUIServer"),

            // Energia (servono i permessi di amministratore)
            Ritocco(id: "energia.batteriaRisparmio", titolo: t("Low Power Mode on battery", "Risparmio energetico a batteria"),
                    spiegazione: t("When unplugged the Mac uses less power and lasts longer.", "Quando non sei in carica il Mac consuma meno e dura di più."),
                    categoria: .energia,
                    azione: .energia(ambito: .batteria, chiave: "lowpowermode", valore: 1), predefinitoEnergia: 0),
            Ritocco(id: "energia.batteriaSchermo", titolo: t("Display off after 3 minutes on battery", "Schermo spento dopo 3 minuti a batteria"),
                    spiegazione: t("The display is what uses the most power.", "Lo schermo è la cosa che consuma di più."),
                    categoria: .energia,
                    azione: .energia(ambito: .batteria, chiave: "displaysleep", valore: 3)),
            Ritocco(id: "energia.batteriaNoPowerNap", titolo: t("No Power Nap on battery", "Niente Power Nap a batteria"),
                    spiegazione: t("While asleep on battery the Mac doesn't wake for mail and updates.", "In stop a batteria il Mac non si sveglia per mail e aggiornamenti."),
                    categoria: .energia,
                    azione: .energia(ambito: .batteria, chiave: "powernap", valore: 0), predefinitoEnergia: 1),
            Ritocco(id: "energia.alimentatorePiena", titolo: t("Full power on the adapter", "Piena potenza con l'alimentatore"),
                    spiegazione: t("When plugged in the Mac never goes into Low Power Mode.", "In carica il Mac non va mai in risparmio energetico."),
                    categoria: .energia,
                    azione: .energia(ambito: .alimentatore, chiave: "lowpowermode", valore: 0), predefinitoEnergia: 0),

            // Privacy
            Ritocco(id: "privacy.noPubblicita", titolo: t("No personalised Apple ads", "Niente pubblicità personalizzata Apple"),
                    spiegazione: t("Apple doesn't use your data to choose ads.", "Apple non usa i tuoi dati per scegliere gli annunci."),
                    categoria: .privacy,
                    azione: .preferenza(dominio: "com.apple.AdLib", chiave: "allowApplePersonalizedAdvertising", valore: .bool(false))),
            Ritocco(id: "privacy.noCrashReporter", titolo: t("No crash report windows", "Niente finestre di segnalazione arresti"),
                    spiegazione: t("If an app quits unexpectedly you get a notification, not a window.", "Se un'app si chiude da sola ricevi una notifica, non una finestra."),
                    categoria: .privacy,
                    azione: .preferenza(dominio: "com.apple.CrashReporter", chiave: "UseUNC", valore: .int(1))),
        ]
    }

    // MARK: Profili (solo tre: Massimo, Bilanciato, Sicuro)

    static let idBilanciato = ["finder.estensioni", "finder.barraPercorso", "finder.cartellePrima", "finder.noAnimazioni",
                               "dock.noRecenti", "dock.noAnimazioneApertura", "mission.veloce", "ui.ridimensionaVeloce",
                               "ui.quickLookVeloce", "file.noDSStoreRete", "file.noDSStoreUSB", "file.dialogoSalvaEspanso",
                               "screenshot.noMiniatura", "energia.batteriaNoPowerNap", "energia.alimentatorePiena",
                               "privacy.noPubblicita"]
    static let idSicuro = ["finder.estensioni", "finder.barraPercorso", "finder.barraStato", "finder.cartellePrima",
                           "file.noDSStoreRete", "file.noDSStoreUSB", "file.dialogoSalvaEspanso", "file.dialogoStampaEspanso",
                           "stampa.chiudiCoda", "privacy.noPubblicita", "privacy.noCrashReporter", "screenshot.noOmbra"]

    static var profili: [Profilo] {
        [
            Profilo(id: "massimo", nome: L("Maximum", "Massimo"), icona: "bolt.fill",
                    descrizione: L("Everything that makes the Mac faster and more efficient: animations, Finder, Dock, keyboard, energy and privacy.",
                                   "Tutto quello che rende il Mac più veloce ed efficiente: animazioni, Finder, Dock, tastiera, energia e privacy."),
                    ritocchi: ritocchi.map(\.id),
                    avviso: L("Maximum changes many things at once, including a hidden Dock, energy settings and a Trash that empties after 30 days. Read the preview and untick what you don't want.",
                              "Il profilo Massimo cambia molte cose insieme, compreso il Dock nascosto, le impostazioni di energia e il Cestino che si svuota dopo 30 giorni. Leggi bene l'anteprima e togli quello che non vuoi.")),
            Profilo(id: "bilanciato", nome: L("Balanced", "Bilanciato"), icona: "scalemass",
                    descrizione: L("For every day: a snappier, tidier Mac without changing your habits.",
                                   "Per tutti i giorni: Mac più reattivo e ordinato senza cambiare le tue abitudini."),
                    ritocchi: idBilanciato),
            Profilo(id: "sicuro", nome: L("Safe", "Sicuro"), icona: "checkmark.shield",
                    descrizione: L("Only light, reversible changes: clearer Finder, cleaner files and privacy.",
                                   "Solo modifiche leggere e reversibili: Finder più chiaro, file puliti e privacy."),
                    ritocchi: idSicuro),
        ]
    }

    static func ritocco(_ id: String) -> Ritocco? { ritocchi.first { $0.id == id } }

    static func testoEnergia(chiave: String, valore: Int?) -> String {
        guard let v = valore else { return L("not set", "non impostato") }
        switch chiave {
        case "displaysleep", "sleep": return v == 0 ? L("never", "mai") : "\(v) min"
        default: return v == 0 ? "no" : L("yes", "sì")
        }
    }

    /// Testo per "nessun valore": la chiave non è impostata e macOS usa il suo valore di serie.
    static var testoPredefinito: String { L("macOS default", "predefinito di macOS") }

    /// Consigli che macOS non permette di cambiare da un'app: apriamo l'impostazione giusta.
    static var consigliManuali: [ConsiglioManuale] {
        [
            ConsiglioManuale(titolo: L("Reduce transparency and motion", "Riduci trasparenza e movimento"),
                             spiegazione: L("Accessibility › Display: fewer visual effects, snappier Mac (especially older ones).",
                                            "Accessibilità › Schermo: meno effetti grafici, Mac più scattante (soprattutto quelli meno recenti)."),
                             url: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension", icona: "circle.lefthalf.filled"),
            ConsiglioManuale(titolo: L("Login items and background apps", "Elementi di login e in background"),
                             spiegazione: L("General › Login Items: remove apps you don't need at startup.",
                                            "Generali › Elementi di login: togli le app che non ti servono all'avvio."),
                             url: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension", icona: "power"),
            ConsiglioManuale(titolo: L("Storage", "Archiviazione"),
                             spiegazione: L("General › Storage: Apple's recommendations, including Optimise Mac Storage for iCloud.",
                                            "Generali › Archiviazione: i consigli di Apple, compreso Ottimizza spazio del Mac per iCloud."),
                             url: "x-apple.systempreferences:com.apple.settings.Storage", icona: "internaldrive"),
            ConsiglioManuale(titolo: L("Battery", "Batteria"),
                             spiegazione: L("Optimised charging, Low Power Mode and battery health.",
                                            "Caricamento ottimizzato, modalità Risparmio energetico e salute della batteria."),
                             url: "x-apple.systempreferences:com.apple.Battery-Settings.extension", icona: "battery.75percent"),
            ConsiglioManuale(titolo: "Spotlight",
                             spiegazione: L("Exclude huge folders you never search: less indexing in the background.",
                                            "Escludi le cartelle enormi che non cerchi mai: meno indicizzazione in background."),
                             url: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension", icona: "magnifyingglass"),
            ConsiglioManuale(titolo: L("Software Update", "Aggiornamento Software"),
                             spiegazione: L("Turn on automatic updates and security responses.",
                                            "Attiva gli aggiornamenti automatici e le risposte di sicurezza."),
                             url: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension", icona: "arrow.down.app"),
            ConsiglioManuale(titolo: "Time Machine",
                             spiegazione: L("An automatic backup to an external disk protects everything else.",
                                            "Un backup automatico su un disco esterno protegge tutto il resto."),
                             url: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension", icona: "clock.arrow.circlepath"),
        ]
    }
}
