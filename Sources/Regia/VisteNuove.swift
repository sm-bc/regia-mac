import SwiftUI
import Charts
import AppKit

// MARK: - Piede della barra laterale: Modalità prova e riavvio

struct PiedeBarra: View {
    @EnvironmentObject var stato: Stato
    @State private var confermaRiavvio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Toggle(isOn: $stato.modalitaProva) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Modalità prova").fontWeight(.semibold)
                    Text(stato.modalitaProva ? "Non cambia niente" : "Le modifiche sono vere")
                        .font(.caption2).foregroundStyle(stato.modalitaProva ? .orange : .secondary)
                }
            }
            .toggleStyle(.switch).tint(.orange)
            Button { confermaRiavvio = true } label: { Label("Riavvia il Mac…", systemImage: "restart") }
                .buttonStyle(.borderless)
            Text("\(stato.modifiche.count) modifiche attive").font(.caption).foregroundStyle(.secondary)
            if stato.motore.prova {
                Label("Simulazione su dati finti", systemImage: "testtube.2").font(.caption2).foregroundStyle(.purple)
            }
        }
        .padding(12)
        .confirmationDialog("Riavviare il Mac?", isPresented: $confermaRiavvio) {
            Button("Riavvia") { stato.riavviaMac() }
        } message: { Text(testoRiavvio) }
    }

    var testoRiavvio: String {
        let aperte = Manutenzione.appAperte()
        var t = "Le app chiederanno di salvare i documenti aperti."
        if !aperte.isEmpty { t += "\n\nApp aperte: " + aperte.prefix(12).joined(separator: ", ") + (aperte.count > 12 ? "…" : "") }
        return t
    }
}

// MARK: - Avvisi in cima: Modalità prova e riavvio necessario

struct BannerAvvisi: View {
    @EnvironmentObject var stato: Stato
    @State private var confermaRiavvio = false

    var body: some View {
        VStack(spacing: 0) {
            if stato.modalitaProva {
                HStack(spacing: 10) {
                    Image(systemName: "testtube.2")
                    Text("**Modalità prova accesa:** vedi tutto in anteprima, ma il Mac non viene modificato.")
                    Spacer()
                    Button("Spegni") { stato.modalitaProva = false }.controlSize(.small)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.orange.opacity(0.18))
            }
            if !stato.serveRiavvio.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "restart.circle")
                    Text("**Serve un riavvio** per: \(stato.serveRiavvio.joined(separator: ", ")).").lineLimit(2)
                    Spacer()
                    Button("Più tardi") { stato.serveRiavvio = [] }.controlSize(.small)
                    Button("Riavvia ora…") { confermaRiavvio = true }.controlSize(.small).buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.blue.opacity(0.15))
            }
        }
        .confirmationDialog("Riavviare il Mac?", isPresented: $confermaRiavvio) {
            Button("Riavvia") { stato.riavviaMac() }
        } message: { Text("Le app chiederanno di salvare i documenti aperti.") }
    }
}

// MARK: - Dati in tempo reale

struct PannelloLive: View {
    @EnvironmentObject var stato: Stato
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Riquadro {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("In tempo reale", systemImage: "waveform.path.ecg").font(.headline)
                    Spacer()
                    Text("aggiornato ogni secondo").font(.caption).foregroundStyle(.secondary)
                }
                if let c = stato.live {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], alignment: .leading, spacing: 14) {
                        ValoreLive(titolo: "Processore", valore: "\(Int(c.cpu.rounded()))%", sotto: nil, storico: stato.storicoCPU, massimo: 100)
                        ValoreLive(titolo: "Memoria usata",
                                   valore: String(format: "%.1f GB", c.memoriaUsataGB).replacingOccurrences(of: ".", with: ","),
                                   sotto: "su \(Int(c.memoriaTotaleGB.rounded())) GB", storico: nil, massimo: nil)
                        ValoreLive(titolo: "Rete ↓ / ↑", valore: formatoVelocita(c.reteGiu), sotto: "↑ " + formatoVelocita(c.reteSu),
                                   storico: stato.storicoRete, massimo: nil)
                        ValoreLive(titolo: "Disco lettura / scrittura", valore: formatoVelocita(c.discoLettura),
                                   sotto: "scrittura " + formatoVelocita(c.discoScrittura), storico: nil, massimo: nil)
                        if let b = c.batteria {
                            ValoreLive(titolo: c.alimentatore ? (c.inCarica ? "Batteria (in carica)" : "Batteria (alimentatore)") : "Batteria",
                                       valore: "\(b)%",
                                       sotto: [c.watt.map { String(format: "%.1f W", $0).replacingOccurrences(of: ".", with: ",") },
                                               c.minutiRimasti.map { "\($0 / 60) h \($0 % 60) min" }].compactMap { $0 }.joined(separator: " · "),
                                       storico: nil, massimo: nil)
                        }
                        ValoreLive(titolo: "Temperatura", valore: c.termico.prefix(1).uppercased() + c.termico.dropFirst(),
                                   sotto: c.termicoLivello >= 2 ? "il Mac sta rallentando per raffreddarsi" : "stato termico di macOS",
                                   storico: nil, massimo: nil, colore: c.termicoLivello >= 2 ? .red : (c.termicoLivello == 1 ? .orange : nil))
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { stato.aggiornaLive() }
        .onReceive(timer) { _ in stato.aggiornaLive() }
    }
}

struct ValoreLive: View {
    let titolo: String
    let valore: String
    let sotto: String?
    let storico: [Double]?
    let massimo: Double?
    var colore: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titolo).font(.caption).foregroundStyle(.secondary)
            Text(valore).font(.title3.bold()).monospacedDigit().foregroundStyle(colore ?? .primary)
            if let s = sotto, !s.isEmpty { Text(s).font(.caption2).foregroundStyle(.secondary).monospacedDigit() }
            if let st = storico, st.count > 1 {
                Chart(Array(st.enumerated()), id: \.offset) { p in
                    AreaMark(x: .value("t", p.offset), y: .value("v", p.element))
                        .foregroundStyle(.tint.opacity(0.2))
                    LineMark(x: .value("t", p.offset), y: .value("v", p.element))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .chartYScale(domain: 0...(massimo ?? max(st.max() ?? 1, 1)))
                .chartXScale(domain: 0...59)
                .frame(height: 30)
            }
        }
    }
}

// MARK: - Residui di app cancellate

struct VistaResidui: View {
    @EnvironmentObject var stato: Stato
    @State private var conferma = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Titolo(titolo: "Residui", sottotitolo: "File lasciati da app che non ci sono più e avvii automatici che puntano a programmi cancellati.")
                    Riquadro {
                        Label("I residui scelti vengono messi da parte in una cartella di Regia, non cancellati: con Annulla tornano al loro posto. Quelli segnati come \"dati\" sono esclusi di serie perché possono contenere documenti o impostazioni.",
                              systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    }
                    if !stato.orfaniCalcolati {
                        Button { stato.cercaOrfani() } label: { Label("Cerca residui", systemImage: "magnifyingglass") }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    } else if stato.orfani.isEmpty {
                        Riquadro { Label("Nessun residuo trovato: il Mac è pulito.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    } else {
                        let gruppi = Dictionary(grouping: stato.orfani, by: \.app).sorted { $0.key.lowercased() < $1.key.lowercased() }
                        ForEach(gruppi, id: \.key) { app, lista in
                            Riquadro {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(app).font(.headline)
                                        Spacer()
                                        Text(formatoByte(lista.reduce(0) { $0 + $1.dimensione })).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    ForEach(lista) { r in RigaResiduo(r: r, scelti: $stato.orfaniScelti) }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            if stato.orfaniCalcolati && !stato.orfani.isEmpty {
                Divider()
                HStack {
                    let n = stato.orfaniScelti.count
                    Text("\(n) scelti · \(formatoByte(stato.orfani.filter { stato.orfaniScelti.contains($0.id) }.reduce(0) { $0 + $1.dimensione }))")
                        .font(.headline)
                    Spacer()
                    Button("Cerca di nuovo") { stato.cercaOrfani() }
                    Button("Metti da parte…") { conferma = true }.buttonStyle(.borderedProminent).disabled(n == 0)
                }
                .padding(12).background(.bar)
            }
        }
        .confirmationDialog("Mettere da parte \(stato.orfaniScelti.count) residui?", isPresented: $conferma) {
            Button("Metti da parte") { stato.mettiDaParteOrfani() }
        } message: { Text("Vengono spostati in una cartella di Regia. Con Annulla (Cronologia) tornano al loro posto.") }
    }
}

struct RigaResiduo: View {
    let r: Residuo
    @Binding var scelti: Set<String>
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(get: { scelti.contains(r.id) }, set: { if $0 { scelti.insert(r.id) } else { scelti.remove(r.id) } }))
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(r.tipo.rawValue).fontWeight(.medium)
                    if r.delicato { Etichetta(testo: "dati", colore: .orange) }
                }
                Text(r.percorso.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(formatoByte(r.dimensione)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Button { NSWorkspace.shared.activateFileViewerSelecting([r.percorso]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Mostra nel Finder")
        }
    }
}

// MARK: - App installate

struct VistaApp: View {
    @EnvironmentObject var stato: Stato
    @State private var cerca = ""
    @State private var ordine = 0   // 0 nome, 1 dimensione

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Titolo(titolo: "App installate", sottotitolo: "\"Disinstalla e pulisci\" sposta l'app nel Cestino insieme ai file che lascia in Libreria. Prima ti mostra l'elenco.")
            HStack {
                TextField("Cerca per nome…", text: $cerca).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                Picker("", selection: $ordine) { Text("Per nome").tag(0); Text("Per dimensione").tag(1) }
                    .pickerStyle(.segmented).frame(width: 220).labelsHidden()
                Spacer()
                Text("\(stato.app.count) app · \(formatoByte(stato.app.reduce(0) { $0 + ($1.dimensione ?? 0) }))")
                    .foregroundStyle(.secondary).monospacedDigit()
                Button { stato.caricaApp() } label: { Image(systemName: "arrow.clockwise") }.help("Rileggi l'elenco")
            }
            List(filtrate) { a in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: a.percorso.path)).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(a.nome).fontWeight(.medium)
                            if a.daAppStore { Etichetta(testo: "App Store", colore: .blue) }
                            if a.protetta { Etichetta(testo: "di sistema", colore: .secondary) }
                        }
                        Text("\(a.versione.isEmpty ? "" : "v\(a.versione) · ")\(a.bundleID)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(a.dimensione.map(formatoByte) ?? "…").foregroundStyle(.secondary).monospacedDigit()
                    Button("Disinstalla e pulisci…") { stato.preparaDisinstallazione(a) }
                        .disabled(a.protetta).controlSize(.small)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .padding(24)
        .onAppear { if stato.app.isEmpty { stato.caricaApp() } }
    }

    var filtrate: [AppInstallata] {
        var l = stato.app
        if !cerca.isEmpty { l = l.filter { $0.nome.localizedCaseInsensitiveContains(cerca) || $0.bundleID.localizedCaseInsensitiveContains(cerca) } }
        if ordine == 1 { l.sort { ($0.dimensione ?? 0) > ($1.dimensione ?? 0) } }
        return l
    }
}

struct VistaDisinstalla: View {
    @EnvironmentObject var stato: Stato

    var body: some View {
        if let (a, residui, _) = stato.residuiApp {
            let disinst = AppInstallate.disinstallatore(per: a, tra: stato.app)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: a.percorso.path)).resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text("Disinstalla \(a.nome)").font(.title2.bold())
                        Text(a.percorso.path).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let d = disinst {
                    Label("\(a.nome) ha un suo programma di disinstallazione: \"\(d.nome)\". È meglio usare quello, perché toglie anche i componenti di sistema.",
                          systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button("Apri \(d.nome)") { NSWorkspace.shared.open(d.percorso); stato.residuiApp = nil }
                }
                Text(residui.isEmpty ? "Nessun file rimasto in Libreria: va nel Cestino solo l'app."
                     : "Va nel Cestino l'app e i file scelti qui sotto. Quelli segnati \"dati\" possono contenere documenti o impostazioni: di serie restano.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !residui.isEmpty {
                    List(residui) { r in
                        RigaResiduo(r: r, scelti: Binding(get: { stato.residuiApp?.scelti ?? [] },
                                                          set: { stato.residuiApp?.scelti = $0 }))
                    }
                    .frame(minHeight: 200)
                }
                if stato.modalitaProva {
                    Label("Modalità prova accesa: vedrai cosa succederebbe, senza cambiare niente.", systemImage: "testtube.2")
                        .foregroundStyle(.orange).font(.callout)
                }
                HStack {
                    Spacer()
                    Button("Annulla") { stato.residuiApp = nil }.keyboardShortcut(.cancelAction)
                    Button(stato.modalitaProva ? "Prova" : "Sposta nel Cestino") { stato.disinstalla() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(width: 600, height: residui.isEmpty ? 300 : 540)
        }
    }
}

// MARK: - Manutenzione

struct VistaManutenzione: View {
    @EnvironmentObject var stato: Stato
    @State private var daConfermare: Strumento? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Titolo(titolo: "Manutenzione", sottotitolo: "Controlli e piccole riparazioni con gli strumenti di Apple. I controlli leggono soltanto.")
                ForEach(Strumento.Gruppo.allCases, id: \.self) { g in
                    Riquadro {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(g.rawValue).font(.headline)
                            ForEach(Manutenzione.strumenti.filter { $0.gruppo == g }) { s in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: s.icona).font(.title3).foregroundStyle(.tint).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(s.titolo).fontWeight(.medium)
                                            if s.serveAdmin { Image(systemName: "lock").foregroundStyle(.secondary).help("Chiede la password del Mac") }
                                        }
                                        Text(s.spiegazione).font(.callout).foregroundStyle(.secondary)
                                        if let d = s.durata { Text("Durata: \(d)").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if stato.inCorso == s.id {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Button(s.modifica ? "Esegui…" : "Controlla") {
                                            if s.modifica { daConfermare = s } else { stato.avviaStrumento(s) }
                                        }
                                        .disabled(stato.inCorso != nil)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .confirmationDialog(daConfermare?.titolo ?? "", isPresented: Binding(get: { daConfermare != nil }, set: { if !$0 { daConfermare = nil } })) {
            Button(stato.modalitaProva ? "Prova" : "Esegui") { if let s = daConfermare { stato.avviaStrumento(s) }; daConfermare = nil }
        } message: {
            Text([daConfermare?.spiegazione, daConfermare?.avviso, daConfermare?.serveAdmin == true ? "macOS chiederà la password: la scrivi tu nella sua finestra." : nil]
                .compactMap { $0 }.joined(separator: "\n\n"))
        }
    }
}

struct VistaRisultato: View {
    @EnvironmentObject var stato: Stato
    let r: RisultatoStrumento
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(r.titolo).font(.title2.bold())
            ScrollView {
                Text(r.testo).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 340)
            HStack { Spacer(); Button("OK") { stato.risultato = nil }.keyboardShortcut(.defaultAction) }
        }
        .padding(22)
        .frame(width: 520)
    }
}
