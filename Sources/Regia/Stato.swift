import Foundation
import AppKit

enum Sezione: String, CaseIterable, Identifiable {
    case panoramica = "Panoramica", profili = "Profili", ritocchi = "Ritocchi"
    case pulizia = "Pulizia", avvio = "Avvio", cronologia = "Cronologia"
    var id: String { rawValue }
    var icona: String {
        switch self {
        case .panoramica: return "gauge.with.dots.needle.67percent"
        case .profili: return "person.crop.rectangle.stack"
        case .ritocchi: return "slider.horizontal.3"
        case .pulizia: return "sparkles"
        case .avvio: return "power"
        case .cronologia: return "clock.arrow.circlepath"
        }
    }
}

struct VoceAnteprima: Identifiable {
    var id: String { ritocco.id }
    let ritocco: Ritocco
    let ora: String
    var scelta: Bool
}

@MainActor
final class Stato: ObservableObject {
    let motore: Motore
    @Published var sezione: Sezione? = .panoramica
    @Published var panoramica: Panoramica?
    @Published var consigli: [Consiglio] = []
    @Published var statoRitocchi: [String: (testo: String, attivo: Bool)] = [:]
    @Published var selezionati: Set<String> = []
    @Published var zone: [ZonaPulizia] = Pulizia.zone()
    @Published var zoneScelte: Set<String> = []
    @Published var avvio: [ElementoAvvio] = []
    @Published var registro: [String] = []
    @Published var occupato: String? = nil
    @Published var anteprima: [VoceAnteprima]? = nil
    @Published var titoloAnteprima = ""
    @Published var avviso: (titolo: String, testo: String)? = nil

    init(motore: Motore) {
        self.motore = motore
        if motore.prova, let base = motore.cartellaProva { zone = Pulizia.zone(base: base) }
        zoneScelte = Set(zone.filter { $0.selezionataDiDefault }.map { $0.id })
        registro = motore.leggiRegistro()
    }

    var modifiche: [Modifica] { motore.modifiche }

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
            var z = zone[i]
            z = await Task.detached { var copia = z; Pulizia.calcola(&copia); return copia }.value
            zone[i] = z
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

    // MARK: Anteprima e applicazione

    func preparaAnteprima(titolo: String, ids: [String]) {
        let voci = ids.compactMap { Catalogo.ritocco($0) }.map { t -> VoceAnteprima in
            let s = statoRitocchi[t.id]
            return VoceAnteprima(ritocco: t, ora: s?.testo ?? "?", scelta: !(s?.attivo ?? false))
        }
        titoloAnteprima = titolo
        anteprima = voci
    }

    func applicaAnteprima() {
        guard let voci = anteprima else { return }
        let scelti = voci.filter { $0.scelta }.map { $0.ritocco }
        anteprima = nil
        guard !scelti.isEmpty else { return }
        Task {
            occupato = "Applico \(scelti.count) modifiche…"
            let m = motore
            let r = await Task.detached { m.applica(scelti) }.value
            await aggiornaStati()
            selezionati.removeAll()
            occupato = nil
            var testo = "Applicate \(r.applicati) modifiche su \(scelti.count). Puoi annullarle da Cronologia."
            if !r.errori.isEmpty { testo += "\n\nProblemi:\n• " + r.errori.joined(separator: "\n• ") }
            if scelti.contains(where: { $0.nota != nil }) {
                testo += "\n\nAlcune modifiche si vedono dopo aver riaperto le app o rientrato nell'account."
            }
            avviso = (r.errori.isEmpty ? "Fatto" : "Fatto, con qualche problema", testo)
        }
    }

    func annulla(_ m: Modifica) {
        Task {
            occupato = "Ripristino \(m.titolo)…"
            let motore = self.motore
            let errore = await Task.detached { () -> String? in
                do { try motore.annulla(m); return nil } catch { return error.localizedDescription }
            }.value
            await aggiornaStati()
            occupato = nil
            if let e = errore { avviso = ("Non riuscito", e) }
        }
    }

    func annullaTutto() {
        Task {
            occupato = "Riporto tutto com'era…"
            let motore = self.motore
            let errori = await Task.detached { motore.annullaTutto() }.value
            await aggiornaStati()
            occupato = nil
            avviso = errori.isEmpty
                ? ("Fatto", "Tutte le impostazioni cambiate da Regia sono tornate com'erano.")
                : ("Ripristino incompleto", errori.joined(separator: "\n"))
        }
    }

    // MARK: Pulizia

    var byteScelti: Int64 { zone.filter { zoneScelte.contains($0.id) && $0.calcolata }.reduce(0) { $0 + $1.dimensione } }

    func pulisci() {
        let scelte = zone.filter { zoneScelte.contains($0.id) && $0.calcolata }
        let elementi = scelte.flatMap { $0.elementi }
        guard !elementi.isEmpty else { return }
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
        do { try motore.disattivaAvvio(e) } catch { avviso = ("Non riuscito", error.localizedDescription) }
        avvio = motore.elementiAvvio()
        registro = motore.leggiRegistro()
        aggiornaConsigli()
    }

    func riattiva(_ e: ElementoAvvio) {
        guard let m = motore.modifiche.first(where: { $0.percorsoSalvato == e.file.path }) else { return }
        annulla(m)
    }

    func apri(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    func mostraNelFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
