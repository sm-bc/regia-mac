import Foundation
import AppKit
import SwiftUI

enum Sezione: String, CaseIterable, Identifiable {
    case panoramica, suggerimenti
    case profili, ritocchi
    case pulizia, residui, app, avvio
    case aggiornamentiApp, manutenzione, cronologia
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .panoramica: return L("Overview", "Panoramica")
        case .suggerimenti: return L("Tips", "Suggerimenti")
        case .profili: return L("Profiles", "Profili")
        case .ritocchi: return L("Tweaks", "Ritocchi")
        case .pulizia: return L("Cleanup", "Pulizia")
        case .residui: return L("Leftovers", "Residui")
        case .app: return L("Installed Apps", "App installate")
        case .avvio: return L("Startup", "Avvio")
        case .aggiornamentiApp: return L("App Updates", "Aggiornamenti app")
        case .manutenzione: return L("Maintenance", "Manutenzione")
        case .cronologia: return L("History", "Cronologia")
        }
    }
    var icona: String {
        switch self {
        case .panoramica: return "gauge.with.dots.needle.67percent"
        case .suggerimenti: return "lightbulb"
        case .profili: return "person.crop.rectangle.stack"
        case .ritocchi: return "slider.horizontal.3"
        case .pulizia: return "sparkles"
        case .residui: return "shippingbox"
        case .app: return "square.grid.2x2"
        case .avvio: return "power"
        case .aggiornamentiApp: return "arrow.down.circle"
        case .manutenzione: return "wrench.and.screwdriver"
        case .cronologia: return "clock.arrow.circlepath"
        }
    }
    /// Colore dell'icona nella barra laterale, come in Impostazioni di Sistema.
    var colore: Color {
        switch self {
        case .panoramica: return .blue
        case .suggerimenti: return .yellow
        case .profili: return .indigo
        case .ritocchi: return .gray
        case .pulizia: return .pink
        case .residui: return .brown
        case .app: return .cyan
        case .avvio: return .red
        case .aggiornamentiApp: return .green
        case .manutenzione: return .orange
        case .cronologia: return .purple
        }
    }
    static var gruppi: [(String, [Sezione])] {
        [
            ("", [.panoramica, .suggerimenti]),
            (L("Optimise", "Ottimizza"), [.profili, .ritocchi]),
            (L("Clean", "Pulisci"), [.pulizia, .residui, .app, .avvio]),
            (L("Tools", "Strumenti"), [.aggiornamentiApp, .manutenzione, .cronologia]),
        ]
    }
}

struct VoceAnteprima: Identifiable {
    var id: String { ritocco.id }
    let ritocco: Ritocco
    let ora: String
    let nuovo: String
    var scelta: Bool
}

struct RisultatoStrumento: Identifiable {
    let id = UUID()
    let titolo: String
    let testo: String
}

@MainActor
final class Stato: ObservableObject {
    let motore: Motore
    @Published var sezione: Sezione? = .panoramica
    @Published var lingua: Lingua = Lingua.attuale
    /// Come su Windows: accesa a ogni apertura. Mostra cosa succederebbe ma non cambia niente.
    @Published var modalitaProva = true
    @Published var panoramica: Panoramica?
    @Published var ultimaScansione: Date? = nil
    @Published var consigli: [Consiglio] = []
    @Published var controlli: [Controllo] = []
    @Published var statoRitocchi: [String: StatoRitocco] = [:]
    @Published var selezionati: Set<String> = []
    @Published var zone: [ZonaPulizia] = []
    @Published var zoneScelte: Set<String> = []
    @Published var avvio: [ElementoAvvio] = []
    @Published var registro: [String] = []
    @Published var occupato: String? = nil
    /// true mentre applica o ripristina: l'interfaccia non accetta altri comandi.
    @Published var bloccato = false
    @Published var anteprima: [VoceAnteprima]? = nil
    @Published var titoloAnteprima = ""
    @Published var avvisoAnteprima: String? = nil
    @Published var anteprimaPredefinito = false
    @Published var avviso: (titolo: String, testo: String)? = nil
    @Published var profiliPersonali: [Profilo] = []
    // Tempo reale
    @Published var live: Campione? = nil
    @Published var storicoCPU: [Double] = []
    @Published var storicoRete: [Double] = []
    private let misuratore = Misuratore()
    // App e residui
    @Published var app: [AppInstallata] = []
    @Published var residuiApp: (app: AppInstallata, residui: [Residuo], scelti: Set<String>)? = nil
    @Published var orfani: [Residuo] = []
    @Published var orfaniScelti: Set<String> = []
    @Published var orfaniCalcolati = false
    // Manutenzione e riavvio
    @Published var risultato: RisultatoStrumento? = nil
    @Published var inCorso: String? = nil
    @Published var serveRiavvio: [String] = []
    /// Dopo la scansione: il Mac è acceso da diversi giorni.
    @Published var suggerisciRiavvio = false
    // Aggiornamenti di Regia (GitHub)
    @Published var aggiornamento: Aggiornamenti.Info? = nil
    @Published var cercandoAggiornamenti = false
    @Published var aggiornamentoInstallato: String? = nil
    private var controlloFatto = false
    // Aggiornamenti delle altre app
    @Published var aggiornamentiApp: RisultatoAggiornamentiApp? = nil
    @Published var cercandoAggiornamentiApp = false
    // Segnalazioni
    @Published var mostraFeedback = false

    init(motore: Motore) {
        self.motore = motore
        zone = Pulizia.zone(base: motore.home)
        zoneScelte = Set(zone.filter { $0.selezionataDiDefault }.map { $0.id })
        registro = motore.leggiRegistro()
        profiliPersonali = motore.profiliPersonali()
        // Solo per le prove: apre direttamente una sezione (es. REGIA_SEZIONE=suggerimenti)
        if let s = ProcessInfo.processInfo.environment["REGIA_SEZIONE"].flatMap(Sezione.init(rawValue:)) { sezione = s }
    }

    var modifiche: [Modifica] { motore.modifiche }

    // MARK: Lingua

    func cambiaLingua(_ l: Lingua) {
        guard l != lingua else { return }
        Lingua.salva(l)
        lingua = l
        // I testi già calcolati (zone, stati, consigli) vanno rifatti nella lingua nuova.
        let vecchie = Dictionary(uniqueKeysWithValues: zone.map { ($0.id, $0) })
        zone = Pulizia.zone(base: motore.home).map { z in
            guard let v = vecchie[z.id] else { return z }
            var n = z; n.calcolata = v.calcolata; n.elementi = v.elementi; n.dimensione = v.dimensione; return n
        }
        Task {
            if panoramica != nil { panoramica = await Task.detached { Analisi.panoramica() }.value }
            await aggiornaStati()
            controlli = await Task.detached { Suggerimenti.controlli() }.value
            if aggiornamentiApp != nil { controllaAggiornamentiApp() }
        }
    }

    /// In Modalità prova: scrive nel registro cosa avrebbe fatto e lo mostra.
    private func soloProva(_ cosa: String, dettagli: [String] = []) -> Bool {
        guard modalitaProva else { return false }
        motore.scriviRegistro(L("TEST (no changes)", "PROVA (nessuna modifica)") + ": \(cosa)")
        registro = motore.leggiRegistro()
        var testo = L("Nothing was changed. Here is what I would have done:", "Non ho cambiato niente. Ecco cosa avrei fatto:") + "\n\n\(cosa)"
        if !dettagli.isEmpty {
            testo += "\n• " + dettagli.prefix(25).joined(separator: "\n• ")
                + (dettagli.count > 25 ? "\n" + L("…and \(dettagli.count - 25) more", "…e altri \(dettagli.count - 25)") : "")
        }
        testo += "\n\n" + L("To do it for real, turn off \"Test mode\" at the bottom left.", "Per farlo davvero spegni \"Modalità prova\" in basso a sinistra.")
        avviso = (L("Test mode", "Modalità prova"), testo)
        return true
    }

    // MARK: Scansione

    func aggiornaTutto() {
        if !controlloFatto { controlloFatto = true; cercaAggiornamenti(silenzioso: true) }
        Task {
            occupato = L("Analysing your Mac…", "Analizzo il Mac…")
            let m = motore
            let (p, stati, av, ctl) = await Task.detached { () -> (Panoramica, [String: StatoRitocco], [ElementoAvvio], [Controllo]) in
                let p = Analisi.panoramica()
                let e = m.leggiEnergia()
                var s: [String: StatoRitocco] = [:]
                for t in Catalogo.ritocchi { s[t.id] = m.statoAttuale(t, energia: e) }
                return (p, s, m.elementiAvvio(), Suggerimenti.controlli())
            }.value
            panoramica = p
            statoRitocchi = stati
            avvio = av
            controlli = ctl
            occupato = L("Calculating space to free…", "Calcolo lo spazio da liberare…")
            await calcolaZone(soloAutomatiche: true)
            aggiornaConsigli()
            registro = motore.leggiRegistro()
            ultimaScansione = Date()
            suggerisciRiavvio = p.giorniAcceso >= Analisi.giorniPerRiavvio
            occupato = nil
            if aggiornamentiApp == nil && !cercandoAggiornamentiApp { controllaAggiornamentiApp() }
        }
    }

    /// Problemi e cose da controllare trovati dall'ultima scansione.
    var daSistemare: Int {
        consigli.filter { $0.livello != .ok }.count + controlli.filter { $0.livello != .ok }.count
    }

    func aggiornaConsigli() {
        guard let p = panoramica else { return }
        let pulibile = zone.filter { $0.selezionataDiDefault && $0.calcolata }.reduce(0) { $0 + $1.dimensione }
        consigli = Analisi.consigli(p, pulibile: pulibile, avvioUtente: avvio.filter { $0.livello == .utente && !$0.disattivato }.count)
    }

    func eseguiConsiglio(_ a: Consiglio.Azione) {
        switch a {
        case .sezione(let s): sezione = s
        case .riavvia: break   // gestito dalla vista con la conferma
        case .apri(let u): apri(u)
        }
    }

    func calcolaZone(soloAutomatiche: Bool) async {
        for i in zone.indices where !(soloAutomatiche && zone[i].suRichiesta) {
            let z = zone[i]
            zone[i] = await Task.detached { var copia = z; Pulizia.calcola(&copia); return copia }.value
        }
    }

    func calcolaZona(_ id: String) {
        guard let i = zone.firstIndex(where: { $0.id == id }) else { return }
        Task {
            occupato = L("Calculating", "Calcolo") + " \(zone[i].titolo.lowercased())…"
            let z = zone[i]
            zone[i] = await Task.detached { var copia = z; Pulizia.calcola(&copia); return copia }.value
            occupato = nil
        }
    }

    private func aggiornaStati() async {
        let m = motore
        statoRitocchi = await Task.detached {
            let e = m.leggiEnergia()
            var s: [String: StatoRitocco] = [:]
            for t in Catalogo.ritocchi { s[t.id] = m.statoAttuale(t, energia: e) }
            return s
        }.value
        avvio = motore.elementiAvvio()
        registro = motore.leggiRegistro()
        aggiornaConsigli()
        objectWillChange.send()
    }

    // MARK: Tempo reale

    func aggiornaLive() {
        let c = misuratore.campione()
        live = c
        storicoCPU = Array((storicoCPU + [c.cpu]).suffix(60))
        storicoRete = Array((storicoRete + [c.reteGiu]).suffix(60))
    }

    // MARK: Anteprima e applicazione

    func preparaAnteprima(titolo: String, ids: [String], avviso: String? = nil) {
        let voci = ids.compactMap { Catalogo.ritocco($0) }.map { t -> VoceAnteprima in
            let s = statoRitocchi[t.id]
            return VoceAnteprima(ritocco: t, ora: s?.testo ?? "?", nuovo: t.valoreNuovoTesto, scelta: !(s?.attivo ?? false))
        }
        titoloAnteprima = titolo
        avvisoAnteprima = avviso
        anteprimaPredefinito = false
        anteprima = voci
    }

    /// "Riporta al predefinito": le voci cambiate tornano come su un Mac appena installato.
    func preparaPredefinito() {
        let voci = Catalogo.ritocchi.compactMap { t -> VoceAnteprima? in
            guard let s = statoRitocchi[t.id], !s.predefinito else { return nil }
            switch t.azione {
            case .preferenza:
                return VoceAnteprima(ritocco: t, ora: s.testo, nuovo: Catalogo.testoPredefinito, scelta: true)
            case .energia(_, let k, _):
                guard let d = t.predefinitoEnergia else { return nil }
                return VoceAnteprima(ritocco: t, ora: s.testo, nuovo: Catalogo.testoEnergia(chiave: k, valore: d), scelta: true)
            }
        }
        guard !voci.isEmpty else {
            avviso = (L("Already fine", "Già a posto"),
                      L("All of Regia's settings are already as on a freshly installed Mac.", "Tutte le voci di Regia sono già come su un Mac appena installato."))
            return
        }
        titoloAnteprima = L("Restore defaults", "Riporta al predefinito")
        avvisoAnteprima = L("These settings go back to how they are on a freshly installed Mac. This can also be undone from History.",
                            "Le voci tornano come su un Mac appena installato. Anche questo si può annullare da Cronologia.")
        anteprimaPredefinito = true
        anteprima = voci
    }

    func applicaAnteprima() {
        guard let voci = anteprima else { return }
        let scelti = voci.filter { $0.scelta }
        let predefinito = anteprimaPredefinito
        anteprima = nil
        guard !scelti.isEmpty else { return }
        if soloProva("\(titoloAnteprima): " + L("\(scelti.count) changes", "\(scelti.count) modifiche"),
                     dettagli: scelti.map { "\($0.ritocco.titolo): \($0.ora) → \($0.nuovo)" }) { return }
        let ritocchi = scelti.map { $0.ritocco }
        Task {
            bloccato = true
            occupato = L("Applying \(ritocchi.count) changes…", "Applico \(ritocchi.count) modifiche…")
            let m = motore
            let r = await Task.detached { m.applica(ritocchi, predefinito: predefinito) }.value
            await aggiornaStati()
            selezionati.removeAll()
            occupato = nil
            bloccato = false
            var testo = L("Applied \(r.applicati) of \(ritocchi.count) changes. You can undo them from History.",
                          "Applicate \(r.applicati) modifiche su \(ritocchi.count). Puoi annullarle da Cronologia.")
            if !r.errori.isEmpty { testo += "\n\n" + L("Problems", "Problemi") + ":\n• " + r.errori.joined(separator: "\n• ") }
            let conUscita = ritocchi.filter(\.serveUscire)
            if !conUscita.isEmpty {
                serveRiavvio = Array(Set(serveRiavvio + conUscita.map { $0.titolo })).sorted()
                testo += "\n\n" + L("Some changes only show after restarting the Mac (or logging out and back in).",
                                    "Alcune modifiche si vedono solo dopo il riavvio del Mac (o uscendo e rientrando).")
            } else if ritocchi.contains(where: { $0.nota != nil }) {
                testo += "\n\n" + L("Some changes show in apps opened from now on.", "Alcune modifiche si vedono nelle app aperte dopo adesso.")
            }
            avviso = (r.errori.isEmpty ? L("Done", "Fatto") : L("Done, with some problems", "Fatto, con qualche problema"), testo)
        }
    }

    func annulla(_ m: Modifica) {
        if soloProva(L("I would undo", "Annullerei") + ": \(titolo(m))") { return }
        Task {
            occupato = L("Restoring", "Ripristino") + " \(titolo(m))…"
            let motore = self.motore
            let errore = await Task.detached { () -> String? in
                do { try motore.annulla(m); return nil } catch { return error.localizedDescription }
            }.value
            await aggiornaStati()
            orfaniCalcolati = false
            occupato = nil
            if let e = errore { avviso = (L("Failed", "Non riuscito"), e) }
        }
    }

    /// Titolo di una modifica nella lingua attuale (le modifiche salvate ricordano la lingua di allora).
    func titolo(_ m: Modifica) -> String { Catalogo.ritocco(m.ritoccoID)?.titolo ?? m.titolo }

    func annullaTutto() {
        if soloProva(L("Undo all: \(modifiche.count) changes would go back to how they were", "Annulla tutto: \(modifiche.count) modifiche tornerebbero com'erano"),
                     dettagli: modifiche.map(titolo)) { return }
        Task {
            bloccato = true
            occupato = L("Putting everything back…", "Riporto tutto com'era…")
            let motore = self.motore
            let errori = await Task.detached { motore.annullaTutto() }.value
            await aggiornaStati()
            orfaniCalcolati = false
            occupato = nil
            bloccato = false
            avviso = errori.isEmpty
                ? (L("Done", "Fatto"), L("All settings changed by Regia are back to how they were.", "Tutte le impostazioni cambiate da Regia sono tornate com'erano."))
                : (L("Restore incomplete", "Ripristino incompleto"), errori.joined(separator: "\n"))
        }
    }

    // MARK: Profili personali

    func salvaProfiloPersonale(nome: String) {
        let ids = Catalogo.ritocchi.map(\.id).filter { selezionati.contains($0) }
        let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !ids.isEmpty else { return }
        do {
            try motore.salvaProfilo(nome: n, ritocchi: ids)
            profiliPersonali = motore.profiliPersonali()
            registro = motore.leggiRegistro()
            avviso = (L("Profile saved", "Profilo salvato"),
                      L("\"\(n)\" with \(ids.count) tweaks. You'll find it in Profiles.", "\"\(n)\" con \(ids.count) ritocchi. Lo trovi in Profili."))
        } catch { avviso = (L("Failed", "Non riuscito"), error.localizedDescription) }
    }

    func eliminaProfilo(_ p: Profilo) {
        motore.eliminaProfilo(p)
        profiliPersonali = motore.profiliPersonali()
        registro = motore.leggiRegistro()
    }

    // MARK: Pulizia

    var byteScelti: Int64 { zone.filter { zoneScelte.contains($0.id) && $0.calcolata }.reduce(0) { $0 + $1.dimensione } }

    /// "Pulizia sicura" (cache, log, Xcode) o "Pulizia accurata" (anche iPhone, simulatori e download vecchi).
    func scegliPulizia(accurata: Bool) {
        zoneScelte = Set(zone.filter { $0.selezionataDiDefault || (accurata && $0.accurata) }.map(\.id))
        if accurata, let d = zone.first(where: { $0.suRichiesta && !$0.calcolata }) { calcolaZona(d.id) }
    }

    func pulisci() {
        let scelte = zone.filter { zoneScelte.contains($0.id) && $0.calcolata }
        let elementi = scelte.flatMap { $0.elementi }
        guard !elementi.isEmpty else { return }
        if soloProva(L("Cleanup: I would move \(formatoByte(byteScelti)) to the Trash (\(elementi.count) items)",
                       "Pulizia: sposterei nel Cestino \(formatoByte(byteScelti)) (\(elementi.count) elementi)"),
                     dettagli: scelte.map { "\($0.titolo): \(formatoByte($0.dimensione))" }) { return }
        Task {
            occupato = L("Moving \(elementi.count) items to the Trash…", "Sposto \(elementi.count) elementi nel Cestino…")
            let r = await Task.detached { Pulizia.spostaNelCestino(elementi) }.value
            motore.scriviRegistro(L("Cleanup: \(r.spostati.count) items to the Trash (\(formatoByte(r.byte)))", "Pulizia: \(r.spostati.count) elementi nel Cestino (\(formatoByte(r.byte)))")
                                  + (r.errori > 0 ? L(", \(r.errori) skipped because in use or protected", ", \(r.errori) saltati perché in uso o protetti") : ""))
            await calcolaZone(soloAutomatiche: false)
            registro = motore.leggiRegistro()
            aggiornaConsigli()
            occupato = nil
            avviso = (L("Cleanup done", "Pulizia fatta"),
                      L("Moved \(formatoByte(r.byte)) to the Trash (\(r.spostati.count) items).", "Spostati nel Cestino \(formatoByte(r.byte)) (\(r.spostati.count) elementi).")
                      + (r.errori > 0 ? "\n" + L("\(r.errori) items skipped because in use or protected by macOS.", "\(r.errori) elementi saltati perché in uso o protetti da macOS.") : "")
                      + "\n\n" + L("If you need something back, recover it from the Trash. The space is really freed when you empty the Trash.",
                                   "Se qualcosa ti serve, lo recuperi dal Cestino. Lo spazio si libera davvero quando svuoti il Cestino."))
        }
    }

    func svuotaCestino() {
        if soloProva(L("I would empty the Trash (permanently)", "Svuoterei il Cestino (definitivo)")) { return }
        Task {
            occupato = L("Emptying the Trash…", "Svuoto il Cestino…")
            let r = await Task.detached {
                esegui("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
            }.value
            motore.scriviRegistro(r.ok ? L("Trash emptied.", "Cestino svuotato.") : L("Trash not emptied", "Cestino non svuotato") + ": \(r.errore)")
            registro = motore.leggiRegistro()
            occupato = nil
            avviso = r.ok ? (L("Done", "Fatto"), L("Trash emptied.", "Cestino svuotato."))
                          : (L("Failed", "Non riuscito"), L("macOS didn't allow controlling the Finder.", "macOS non ha dato il permesso di comandare il Finder.") + "\n\(r.errore)")
            panoramica = await Task.detached { Analisi.panoramica() }.value
        }
    }

    // MARK: Avvio

    func disattiva(_ e: ElementoAvvio) {
        if soloProva(L("I would disable at startup", "Disattiverei all'avvio") + ": \(e.nome)") { return }
        do { try motore.disattivaAvvio(e) } catch { avviso = (L("Failed", "Non riuscito"), error.localizedDescription) }
        avvio = motore.elementiAvvio()
        registro = motore.leggiRegistro()
        aggiornaConsigli()
    }

    func riattiva(_ e: ElementoAvvio) {
        guard let m = motore.modifiche.first(where: { $0.percorsoSalvato == e.file.path }) else { return }
        annulla(m)
    }

    // MARK: App installate

    func caricaApp() {
        Task {
            occupato = L("Reading installed apps…", "Leggo le app installate…")
            let home = motore.home, sim = motore.prova
            var lista = await Task.detached { AppInstallate.elenco(home: home, simulazione: sim) }.value
            app = lista
            occupato = nil
            // Le dimensioni arrivano dopo, una alla volta
            for i in lista.indices {
                let u = lista[i].percorso
                lista[i].dimensione = await Task.detached { Pulizia.dimensione(u) }.value
                if i % 8 == 7 || i == lista.count - 1 { app = lista }
            }
        }
    }

    func preparaDisinstallazione(_ a: AppInstallata) {
        if AppInstallate.inUso(a) {
            avviso = (L("\(a.nome) is open", "\(a.nome) è aperta"), L("Quit it (⌘Q) and try again.", "Chiudila (⌘Q) e riprova."))
            return
        }
        Task {
            occupato = L("Looking for \(a.nome)'s files…", "Cerco i file di \(a.nome)…")
            let home = motore.home
            let r = await Task.detached { Residui.trova(bundleID: a.bundleID, nome: a.nome, home: home) }.value
            occupato = nil
            residuiApp = (a, r, Set(r.filter { !$0.delicato }.map(\.id)))
        }
    }

    func disinstalla() {
        guard let (a, residui, scelti) = residuiApp else { return }
        residuiApp = nil
        let daTogliere = residui.filter { scelti.contains($0.id) }
        if soloProva(L("I would uninstall \(a.nome) and move \(daTogliere.count) leftover files to the Trash",
                       "Disinstallerei \(a.nome) e sposterei nel Cestino \(daTogliere.count) file rimasti"),
                     dettagli: [a.percorso.path] + daTogliere.map(\.percorso.path)) { return }
        Task {
            occupato = L("Uninstalling \(a.nome)…", "Disinstallo \(a.nome)…")
            let errore = await Task.detached { AppInstallate.spostaNelCestino(a) }.value
            var spostati = 0
            if errore == nil {
                spostati = await Task.detached { Pulizia.spostaNelCestino(daTogliere.map(\.percorso)).spostati.count }.value
            }
            motore.scriviRegistro(errore ?? L("Uninstalled \(a.nome) (\(a.bundleID)); \(spostati) leftover files in the Trash",
                                             "Disinstallata \(a.nome) (\(a.bundleID)); \(spostati) file rimasti nel Cestino"))
            registro = motore.leggiRegistro()
            occupato = nil
            avviso = errore.map { (L("Failed", "Non riuscito"), $0) }
                ?? (L("Done", "Fatto"), L("\(a.nome) and \(spostati) leftover files are in the Trash. If you still need it, recover it from there.",
                                          "\(a.nome) e \(spostati) file rimasti sono nel Cestino. Se ti serve ancora, la recuperi da lì."))
            caricaApp()
        }
    }

    // MARK: Residui di app cancellate

    func cercaOrfani() {
        Task {
            occupato = L("Looking for leftovers of deleted apps…", "Cerco i residui di app cancellate…")
            let home = motore.home, sim = motore.prova
            orfani = await Task.detached { Residui.orfani(home: home, simulazione: sim) }.value
            orfaniScelti = Set(orfani.filter { !$0.delicato }.map(\.id))
            orfaniCalcolati = true
            occupato = nil
        }
    }

    func mettiDaParteOrfani() {
        let scelti = orfani.filter { orfaniScelti.contains($0.id) }
        guard !scelti.isEmpty else { return }
        if soloProva(L("I would set aside \(scelti.count) leftovers", "Metterei da parte \(scelti.count) residui"), dettagli: scelti.map { $0.percorso.path }) { return }
        var errori: [String] = []
        for r in scelti {
            do { try motore.mettiDaParte(r) } catch { errori.append("\(r.percorso.lastPathComponent): \(error.localizedDescription)") }
        }
        registro = motore.leggiRegistro()
        avviso = errori.isEmpty
            ? (L("Done", "Fatto"), L("\(scelti.count) leftovers set aside. If something goes wrong, put them back with Undo in History.",
                                     "\(scelti.count) residui messi da parte. Se qualcosa non va, li rimetti con Annulla in Cronologia."))
            : (L("Partly done", "Fatto in parte"), L("Set aside \(scelti.count - errori.count) of \(scelti.count).", "Messi da parte \(scelti.count - errori.count) su \(scelti.count).")
               + "\n\n" + errori.prefix(8).joined(separator: "\n"))
        cercaOrfani()
    }

    // MARK: Manutenzione

    func avviaStrumento(_ s: Strumento) {
        if s.modifica && soloProva("\(s.titolo)") { return }
        inCorso = s.id
        motore.scriviRegistro(L("Started", "Avviato") + ": \(s.titolo)")
        Task {
            let testo = await Task.detached { Manutenzione.esegui(s) }.value
            motore.scriviRegistro("\(s.titolo): " + testo.replacingOccurrences(of: "\n", with: " · "))
            registro = motore.leggiRegistro()
            inCorso = nil
            risultato = RisultatoStrumento(titolo: s.titolo, testo: testo)
        }
    }

    func riavviaMac() {
        if soloProva(L("I would restart the Mac", "Riavvierei il Mac")) { return }
        motore.scriviRegistro(L("Mac restart requested by Regia", "Riavvio del Mac richiesto da Regia"))
        if let e = Manutenzione.riavvia() { avviso = (L("Restart didn't start", "Riavvio non partito"), e) }
    }

    // MARK: Aggiornamenti di Regia

    func cercaAggiornamenti(silenzioso: Bool) {
        cercandoAggiornamenti = true
        Task {
            do {
                aggiornamento = try await Aggiornamenti.controlla()
                if let a = aggiornamento {
                    motore.scriviRegistro(L("Update available: Regia \(a.versione) (you have \(Aggiornamenti.versioneAttuale))",
                                            "Aggiornamento disponibile: Regia \(a.versione) (hai la \(Aggiornamenti.versioneAttuale))"))
                } else if !silenzioso {
                    avviso = (L("Updates", "Aggiornamenti"),
                              L("You already have the latest version of Regia (\(Aggiornamenti.versioneAttuale)).",
                                "Hai già la versione più recente di Regia (\(Aggiornamenti.versioneAttuale))."))
                }
            } catch {
                motore.scriviRegistro(L("Update check failed", "Controllo aggiornamenti non riuscito") + ": \(error.localizedDescription)")
                if !silenzioso {
                    avviso = (L("Updates", "Aggiornamenti"),
                              L("I couldn't check for updates. Check your internet connection and try again.",
                                "Non sono riuscito a controllare gli aggiornamenti. Controlla la connessione a Internet e riprova.")
                              + "\n\n\(error.localizedDescription)")
                }
            }
            registro = motore.leggiRegistro()
            cercandoAggiornamenti = false
        }
    }

    func installaAggiornamento() {
        guard let a = aggiornamento else { return }
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else {
            avviso = (L("Update", "Aggiornamento"), L("Updating only works from the Regia.app application.", "L'aggiornamento funziona solo dall'app Regia.app."))
            return
        }
        let versioni = motore.cartella.appendingPathComponent("Versioni")
        let m = motore
        Task {
            occupato = L("Downloading Regia \(a.versione)…", "Scarico Regia \(a.versione)…")
            do {
                try await Aggiornamenti.installa(a, app: app, cartellaVersioni: versioni) { riga in m.scriviRegistro(riga) }
                aggiornamento = nil
                aggiornamentoInstallato = a.versione
            } catch {
                m.scriviRegistro(L("Update failed", "Aggiornamento non riuscito") + ": \(error.localizedDescription)")
                avviso = (L("Update failed", "Aggiornamento non riuscito"), error.localizedDescription)
            }
            registro = motore.leggiRegistro()
            occupato = nil
        }
    }

    func riapriDopoAggiornamento() {
        Aggiornamenti.riapri(Bundle.main.bundleURL)
        NSApp.terminate(nil)
    }

    // MARK: Aggiornamenti delle app

    func controllaAggiornamentiApp() {
        guard !cercandoAggiornamentiApp else { return }
        cercandoAggiornamentiApp = true
        Task {
            let home = motore.home, sim = motore.prova
            let elenco = await Task.detached { AppInstallate.elenco(home: home, simulazione: sim) }.value
            let r = await AggiornamentiApp.controlla(elenco)
            aggiornamentiApp = r
            cercandoAggiornamentiApp = false
            let n = r.disponibili.count
            motore.scriviRegistro(L("App updates checked: \(n) available", "Aggiornamenti app controllati: \(n) disponibili")
                                  + (n > 0 ? " (" + r.disponibili.map(\.nome).joined(separator: ", ") + ")" : ""))
            registro = motore.leggiRegistro()
        }
    }

    func aggiorna(_ v: AppAggiornabile) {
        switch v.fonte {
        case .appStore:
            if let p = v.pagina { NSWorkspace.shared.open(p) } else { apri("macappstore://showUpdatesPage") }
        case .homebrew(let token, let formula):
            if let e = AggiornamentiApp.aggiornaConBrew(token, formula: formula) { avviso = (L("Failed", "Non riuscito"), e) }
        case .sparkle, .automatica, .sconosciuta:
            guard let p = v.percorso else { return }
            NSWorkspace.shared.openApplication(at: p, configuration: NSWorkspace.OpenConfiguration())
            if v.fonte == .sparkle {
                avviso = (L("\(v.nome) is open", "\(v.nome) è aperta"),
                          L("It usually offers the update by itself. If it doesn't, choose \(v.nome) › Check for Updates… in the menu bar at the top.",
                            "Di solito propone da sola l'aggiornamento. Se non lo fa, scegli \(v.nome) › Controlla aggiornamenti… nella barra dei menu in alto."))
            }
        }
        motore.scriviRegistro(L("Update requested", "Aggiornamento richiesto") + ": \(v.nome) \(v.versione) → \(v.nuova ?? "?")")
        registro = motore.leggiRegistro()
    }

    // MARK: Varie

    func apri(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    func mostraNelFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
