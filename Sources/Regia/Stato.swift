import Foundation
import AppKit

enum Sezione: String, CaseIterable, Identifiable {
    case panoramica = "Panoramica"
    case profili = "Profili", ritocchi = "Ritocchi"
    case pulizia = "Pulizia", residui = "Residui", app = "App installate", avvio = "Avvio"
    case manutenzione = "Manutenzione", cronologia = "Cronologia"
    var id: String { rawValue }
    var icona: String {
        switch self {
        case .panoramica: return "gauge.with.dots.needle.67percent"
        case .profili: return "person.crop.rectangle.stack"
        case .ritocchi: return "slider.horizontal.3"
        case .pulizia: return "sparkles"
        case .residui: return "shippingbox"
        case .app: return "square.grid.2x2"
        case .avvio: return "power"
        case .manutenzione: return "wrench.and.screwdriver"
        case .cronologia: return "clock.arrow.circlepath"
        }
    }
    static let gruppi: [(String, [Sezione])] = [
        ("", [.panoramica]),
        ("Ottimizza", [.profili, .ritocchi]),
        ("Pulisci", [.pulizia, .residui, .app, .avvio]),
        ("Strumenti", [.manutenzione, .cronologia]),
    ]
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
    /// Come su Windows: accesa a ogni apertura. Mostra cosa succederebbe ma non cambia niente.
    @Published var modalitaProva = true
    @Published var panoramica: Panoramica?
    @Published var consigli: [Consiglio] = []
    @Published var statoRitocchi: [String: (testo: String, attivo: Bool)] = [:]
    @Published var selezionati: Set<String> = []
    @Published var zone: [ZonaPulizia] = []
    @Published var zoneScelte: Set<String> = []
    @Published var avvio: [ElementoAvvio] = []
    @Published var registro: [String] = []
    @Published var occupato: String? = nil
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

    init(motore: Motore) {
        self.motore = motore
        zone = Pulizia.zone(base: motore.home)
        zoneScelte = Set(zone.filter { $0.selezionataDiDefault }.map { $0.id })
        registro = motore.leggiRegistro()
        profiliPersonali = motore.profiliPersonali()
    }

    var modifiche: [Modifica] { motore.modifiche }

    /// In Modalità prova: scrive nel registro cosa avrebbe fatto e lo mostra.
    private func soloProva(_ cosa: String, dettagli: [String] = []) -> Bool {
        guard modalitaProva else { return false }
        motore.scriviRegistro("PROVA (nessuna modifica): \(cosa)")
        registro = motore.leggiRegistro()
        var testo = "Non ho cambiato niente. Ecco cosa avrei fatto:\n\n\(cosa)"
        if !dettagli.isEmpty { testo += "\n• " + dettagli.prefix(25).joined(separator: "\n• ") + (dettagli.count > 25 ? "\n…e altri \(dettagli.count - 25)" : "") }
        testo += "\n\nPer farlo davvero spegni \"Modalità prova\" in basso a sinistra."
        avviso = ("Modalità prova", testo)
        return true
    }

    // MARK: Caricamento

    func aggiornaTutto() {
        Task {
            occupato = "Analizzo il Mac…"
            let m = motore
            let (p, stati, av) = await Task.detached { () -> (Panoramica, [String: (testo: String, attivo: Bool)], [ElementoAvvio]) in
                let p = Analisi.panoramica()
                let e = m.leggiEnergia()
                var s: [String: (testo: String, attivo: Bool)] = [:]
                for t in Catalogo.ritocchi { s[t.id] = m.statoAttuale(t, energia: e) }
                return (p, s, m.elementiAvvio())
            }.value
            panoramica = p
            statoRitocchi = stati
            avvio = av
            occupato = "Calcolo lo spazio da liberare…"
            await calcolaZone(soloAutomatiche: true)
            aggiornaConsigli()
            registro = motore.leggiRegistro()
            occupato = nil
        }
    }

    func aggiornaConsigli() {
        guard let p = panoramica else { return }
        let pulibile = zone.filter { $0.selezionataDiDefault && $0.calcolata }.reduce(0) { $0 + $1.dimensione }
        consigli = Analisi.consigli(p, pulibile: pulibile, avvioUtente: avvio.filter { $0.livello == .utente && !$0.disattivato }.count)
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
            occupato = "Calcolo \(zone[i].titolo.lowercased())…"
            let z = zone[i]
            zone[i] = await Task.detached { var copia = z; Pulizia.calcola(&copia); return copia }.value
            occupato = nil
        }
    }

    private func aggiornaStati() async {
        let m = motore
        statoRitocchi = await Task.detached {
            let e = m.leggiEnergia()
            var s: [String: (testo: String, attivo: Bool)] = [:]
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
            let s = statoRitocchi[t.id]
            switch t.azione {
            case .preferenza:
                guard let s, s.testo != "predefinito di macOS" else { return nil }
                return VoceAnteprima(ritocco: t, ora: s.testo, nuovo: "predefinito di macOS", scelta: true)
            case .energia(_, let k, _):
                guard let d = t.predefinitoEnergia, let s else { return nil }
                let testoPredefinito = Catalogo.testoEnergia(chiave: k, valore: d)
                guard s.testo != testoPredefinito else { return nil }
                return VoceAnteprima(ritocco: t, ora: s.testo, nuovo: testoPredefinito, scelta: true)
            }
        }
        guard !voci.isEmpty else {
            avviso = ("Già a posto", "Tutte le voci di Regia sono già come su un Mac appena installato.")
            return
        }
        titoloAnteprima = "Riporta al predefinito"
        avvisoAnteprima = "Le voci tornano come su un Mac appena installato. Anche questo si può annullare da Cronologia."
        anteprimaPredefinito = true
        anteprima = voci
    }

    func applicaAnteprima() {
        guard let voci = anteprima else { return }
        let scelti = voci.filter { $0.scelta }
        let predefinito = anteprimaPredefinito
        anteprima = nil
        guard !scelti.isEmpty else { return }
        if soloProva("\(titoloAnteprima): \(scelti.count) modifiche",
                     dettagli: scelti.map { "\($0.ritocco.titolo): \($0.ora) → \($0.nuovo)" }) { return }
        let ritocchi = scelti.map { $0.ritocco }
        Task {
            occupato = "Applico \(ritocchi.count) modifiche…"
            let m = motore
            let r = await Task.detached { m.applica(ritocchi, predefinito: predefinito) }.value
            await aggiornaStati()
            selezionati.removeAll()
            occupato = nil
            var testo = "Applicate \(r.applicati) modifiche su \(ritocchi.count). Puoi annullarle da Cronologia."
            if !r.errori.isEmpty { testo += "\n\nProblemi:\n• " + r.errori.joined(separator: "\n• ") }
            let conNota = ritocchi.filter { $0.nota?.contains("rientrare") == true }
            if !conNota.isEmpty {
                serveRiavvio = Array(Set(serveRiavvio + conNota.map { $0.titolo })).sorted()
                testo += "\n\nAlcune modifiche si vedono solo dopo il riavvio del Mac (o uscendo e rientrando)."
            } else if ritocchi.contains(where: { $0.nota != nil }) {
                testo += "\n\nAlcune modifiche si vedono nelle app aperte dopo adesso."
            }
            avviso = (r.errori.isEmpty ? "Fatto" : "Fatto, con qualche problema", testo)
        }
    }

    func annulla(_ m: Modifica) {
        if soloProva("Annullerei: \(m.titolo)") { return }
        Task {
            occupato = "Ripristino \(m.titolo)…"
            let motore = self.motore
            let errore = await Task.detached { () -> String? in
                do { try motore.annulla(m); return nil } catch { return error.localizedDescription }
            }.value
            await aggiornaStati()
            orfaniCalcolati = false
            occupato = nil
            if let e = errore { avviso = ("Non riuscito", e) }
        }
    }

    func annullaTutto() {
        if soloProva("Annulla tutto: \(modifiche.count) modifiche tornerebbero com'erano", dettagli: modifiche.map(\.titolo)) { return }
        Task {
            occupato = "Riporto tutto com'era…"
            let motore = self.motore
            let errori = await Task.detached { motore.annullaTutto() }.value
            await aggiornaStati()
            orfaniCalcolati = false
            occupato = nil
            avviso = errori.isEmpty
                ? ("Fatto", "Tutte le impostazioni cambiate da Regia sono tornate com'erano.")
                : ("Ripristino incompleto", errori.joined(separator: "\n"))
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
            avviso = ("Profilo salvato", "\"\(n)\" con \(ids.count) ritocchi. Lo trovi in Profili.")
        } catch { avviso = ("Non riuscito", error.localizedDescription) }
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
        if soloProva("Pulizia: sposterei nel Cestino \(formatoByte(byteScelti)) (\(elementi.count) elementi)",
                     dettagli: scelte.map { "\($0.titolo): \(formatoByte($0.dimensione))" }) { return }
        Task {
            occupato = "Sposto \(elementi.count) elementi nel Cestino…"
            let r = await Task.detached { Pulizia.spostaNelCestino(elementi) }.value
            motore.scriviRegistro("Pulizia: \(r.spostati.count) elementi nel Cestino (\(formatoByte(r.byte)))"
                                  + (r.errori > 0 ? ", \(r.errori) saltati perché in uso o protetti" : ""))
            await calcolaZone(soloAutomatiche: false)
            registro = motore.leggiRegistro()
            aggiornaConsigli()
            occupato = nil
            avviso = ("Pulizia fatta",
                      "Spostati nel Cestino \(formatoByte(r.byte)) (\(r.spostati.count) elementi)."
                      + (r.errori > 0 ? "\n\(r.errori) elementi saltati perché in uso o protetti da macOS." : "")
                      + "\n\nSe qualcosa ti serve, lo recuperi dal Cestino. Lo spazio si libera davvero quando svuoti il Cestino.")
        }
    }

    func svuotaCestino() {
        if soloProva("Svuoterei il Cestino (definitivo)") { return }
        Task {
            occupato = "Svuoto il Cestino…"
            let r = await Task.detached {
                esegui("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
            }.value
            motore.scriviRegistro(r.ok ? "Cestino svuotato." : "Cestino non svuotato: \(r.errore)")
            registro = motore.leggiRegistro()
            occupato = nil
            avviso = r.ok ? ("Fatto", "Cestino svuotato.")
                          : ("Non riuscito", "macOS non ha dato il permesso di comandare il Finder.\n\(r.errore)")
            panoramica = await Task.detached { Analisi.panoramica() }.value
        }
    }

    // MARK: Avvio

    func disattiva(_ e: ElementoAvvio) {
        if soloProva("Disattiverei all'avvio: \(e.nome)") { return }
        do { try motore.disattivaAvvio(e) } catch { avviso = ("Non riuscito", error.localizedDescription) }
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
            occupato = "Leggo le app installate…"
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
            avviso = ("\(a.nome) è aperta", "Chiudila (⌘Q) e riprova.")
            return
        }
        Task {
            occupato = "Cerco i file di \(a.nome)…"
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
        if soloProva("Disinstallerei \(a.nome) e sposterei nel Cestino \(daTogliere.count) file rimasti",
                     dettagli: [a.percorso.path] + daTogliere.map(\.percorso.path)) { return }
        Task {
            occupato = "Disinstallo \(a.nome)…"
            let errore = await Task.detached { AppInstallate.spostaNelCestino(a) }.value
            var spostati = 0
            if errore == nil {
                spostati = await Task.detached { Pulizia.spostaNelCestino(daTogliere.map(\.percorso)).spostati.count }.value
            }
            motore.scriviRegistro(errore ?? "Disinstallata \(a.nome) (\(a.bundleID)); \(spostati) file rimasti nel Cestino")
            registro = motore.leggiRegistro()
            occupato = nil
            avviso = errore.map { ("Non riuscito", $0) }
                ?? ("Fatto", "\(a.nome) e \(spostati) file rimasti sono nel Cestino. Se ti serve ancora, la recuperi da lì.")
            caricaApp()
        }
    }

    // MARK: Residui di app cancellate

    func cercaOrfani() {
        Task {
            occupato = "Cerco i residui di app cancellate…"
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
        if soloProva("Metterei da parte \(scelti.count) residui", dettagli: scelti.map { $0.percorso.path }) { return }
        var errori: [String] = []
        for r in scelti {
            do { try motore.mettiDaParte(r) } catch { errori.append("\(r.percorso.lastPathComponent): \(error.localizedDescription)") }
        }
        registro = motore.leggiRegistro()
        avviso = errori.isEmpty
            ? ("Fatto", "\(scelti.count) residui messi da parte. Se qualcosa non va, li rimetti con Annulla in Cronologia.")
            : ("Fatto in parte", "Messi da parte \(scelti.count - errori.count) su \(scelti.count).\n\n" + errori.prefix(8).joined(separator: "\n"))
        cercaOrfani()
    }

    // MARK: Manutenzione

    func avviaStrumento(_ s: Strumento) {
        if s.modifica && soloProva("\(s.titolo)") { return }
        inCorso = s.id
        motore.scriviRegistro("Avviato: \(s.titolo)")
        Task {
            let testo = await Task.detached { Manutenzione.esegui(s) }.value
            motore.scriviRegistro("\(s.titolo): " + testo.replacingOccurrences(of: "\n", with: " · "))
            registro = motore.leggiRegistro()
            inCorso = nil
            risultato = RisultatoStrumento(titolo: s.titolo, testo: testo)
        }
    }

    func riavviaMac() {
        if soloProva("Riavvierei il Mac") { return }
        motore.scriviRegistro("Riavvio del Mac richiesto da Regia")
        if let e = Manutenzione.riavvia() { avviso = ("Riavvio non partito", e) }
    }

    // MARK: Varie

    func apri(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    func mostraNelFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
