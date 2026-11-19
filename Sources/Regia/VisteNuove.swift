import SwiftUI
import Charts
import AppKit

// MARK: - Piede della barra laterale: Modalità prova, lingua, riavvio, segnalazioni

struct PiedeBarra: View {
    @EnvironmentObject var stato: Stato
    @State private var confermaRiavvio = false
    @State private var confermaAggiornamento = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let a = stato.aggiornamento {
                Button { confermaAggiornamento = true } label: {
                    Label(L("Update to \(a.versione)", "Aggiorna alla \(a.versione)"), systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Divider()
            Toggle(isOn: $stato.modalitaProva) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Test mode", "Modalità prova")).fontWeight(.semibold)
                    Text(stato.modalitaProva ? L("Changes nothing", "Non cambia niente") : L("Changes are real", "Le modifiche sono vere"))
                        .font(.caption2).foregroundStyle(stato.modalitaProva ? .orange : .secondary)
                }
            }
            .toggleStyle(.switch).tint(.orange)
            HStack(spacing: 12) {
                Button { confermaRiavvio = true } label: { Label(L("Restart…", "Riavvia…"), systemImage: "arrow.clockwise.circle") }
                Button { stato.mostraFeedback = true } label: { Label(L("Feedback", "Segnala"), systemImage: "bubble.left.and.exclamationmark.bubble.right") }
                    .help(L("Report a problem or suggest an idea", "Segnala un problema o proponi un'idea"))
            }
            .buttonStyle(.borderless).font(.callout)
            HStack(spacing: 6) {
                Menu {
                    Picker(L("Language", "Lingua"), selection: Binding(get: { stato.lingua }, set: { stato.cambiaLingua($0) })) {
                        ForEach(Lingua.allCases) { l in Text(l.nome).tag(l) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(stato.lingua.nome, systemImage: "globe")
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help(L("Language / Lingua", "Lingua / Language"))
                Spacer()
                Text("Regia \(Aggiornamenti.versioneAttuale)").font(.caption).foregroundStyle(.secondary)
                if stato.cercandoAggiornamenti { ProgressView().controlSize(.mini) }
                else {
                    Button { stato.cercaAggiornamenti(silenzioso: false) } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.borderless).help(L("Check for Regia updates", "Cerca aggiornamenti di Regia"))
                }
            }
            Text(stato.modifiche.count == 1 ? L("1 active change", "1 modifica attiva") : L("\(stato.modifiche.count) active changes", "\(stato.modifiche.count) modifiche attive")).font(.caption2).foregroundStyle(.secondary)
            if stato.motore.prova {
                Label(L("Simulation on fake data", "Simulazione su dati finti"), systemImage: "testtube.2").font(.caption2).foregroundStyle(.purple)
            }
        }
        .padding(12)
        .confirmationDialog(L("Restart the Mac?", "Riavviare il Mac?"), isPresented: $confermaRiavvio) {
            Button(L("Restart", "Riavvia")) { stato.riavviaMac() }
        } message: { Text(testoRiavvio) }
        .alert(L("Update Regia?", "Aggiornare Regia?"), isPresented: $confermaAggiornamento) {
            Button(L("Update", "Aggiorna")) { stato.installaAggiornamento() }
            Button(L("Cancel", "Annulla"), role: .cancel) {}
        } message: { Text(testoAggiornamento) }
        .alert(L("Update complete", "Aggiornamento completato"), isPresented: Binding(get: { stato.aggiornamentoInstallato != nil },
                                                                 set: { if !$0 { stato.aggiornamentoInstallato = nil } })) {
            Button(L("Reopen Regia", "Riapri Regia")) { stato.riapriDopoAggiornamento() }
            Button(L("Later", "Più tardi"), role: .cancel) {}
        } message: { Text(L("You now have version \(stato.aggiornamentoInstallato ?? ""). Reopen Regia to use it.",
                            "Ora hai la versione \(stato.aggiornamentoInstallato ?? ""). Riapri Regia per usarla.")) }
    }

    var testoAggiornamento: String {
        guard let a = stato.aggiornamento else { return "" }
        var t = L("From version \(Aggiornamenti.versioneAttuale) to \(a.versione).", "Dalla versione \(Aggiornamenti.versioneAttuale) alla \(a.versione).")
        if let n = a.note, !n.isEmpty { t += "\n\n" + L("What's new", "Novità") + ":\n\(n)" }
        t += "\n\n" + L("I download the package from GitHub and check it with its SHA-256 fingerprint. Before replacing the app I save a copy in the Versions folder. Changes, backups, log and profiles are not touched.",
                        "Scarico il pacchetto da GitHub e lo controllo con l'impronta SHA-256. Prima di sostituire l'app ne salvo una copia nella cartella Versioni. Modifiche, backup, registro e profili non vengono toccati.")
        return t
    }

    var testoRiavvio: String {
        let aperte = Manutenzione.appAperte()
        var t = L("Apps will ask you to save open documents.", "Le app chiederanno di salvare i documenti aperti.")
        if !aperte.isEmpty { t += "\n\n" + L("Open apps", "App aperte") + ": " + aperte.prefix(12).joined(separator: ", ") + (aperte.count > 12 ? "…" : "") }
        return t
    }
}

// MARK: - Avvisi in cima: Modalità prova, riavvio consigliato o necessario

struct BannerAvvisi: View {
    @EnvironmentObject var stato: Stato
    @State private var confermaRiavvio = false

    var body: some View {
        VStack(spacing: 0) {
            if stato.modalitaProva {
                Fascia(colore: .orange, icona: "testtube.2",
                       testo: L("**Test mode is on:** you see everything as a preview, but the Mac isn't changed.",
                                "**Modalità prova accesa:** vedi tutto in anteprima, ma il Mac non viene modificato.")) {
                    Button(L("Turn Off", "Spegni")) { stato.modalitaProva = false }.controlSize(.small)
                }
            }
            if !stato.serveRiavvio.isEmpty {
                Fascia(colore: .blue, icona: "restart.circle",
                       testo: L("**A restart is needed** for: ", "**Serve un riavvio** per: ") + stato.serveRiavvio.joined(separator: ", ") + ".") {
                    Button(L("Later", "Più tardi")) { stato.serveRiavvio = [] }.controlSize(.small)
                    Button(L("Restart Now…", "Riavvia ora…")) { confermaRiavvio = true }.controlSize(.small).buttonStyle(.borderedProminent)
                }
            } else if stato.suggerisciRiavvio, let p = stato.panoramica {
                Fascia(colore: .blue, icona: "restart.circle",
                       testo: L("**Your Mac has been on for \(Int(p.giorniAcceso)) days.** A restart frees memory and finishes installing updates.",
                                "**Il Mac è acceso da \(Int(p.giorniAcceso)) giorni.** Un riavvio libera memoria e completa gli aggiornamenti.")) {
                    Button(L("Later", "Più tardi")) { stato.suggerisciRiavvio = false }.controlSize(.small)
                    Button(L("Restart…", "Riavvia…")) { confermaRiavvio = true }.controlSize(.small).buttonStyle(.borderedProminent)
                }
            }
        }
        .confirmationDialog(L("Restart the Mac?", "Riavviare il Mac?"), isPresented: $confermaRiavvio) {
            Button(L("Restart", "Riavvia")) { stato.riavviaMac() }
        } message: { Text(L("Apps will ask you to save open documents.", "Le app chiederanno di salvare i documenti aperti.")) }
    }
}

struct Fascia<B: View>: View {
    let colore: Color
    let icona: String
    let testo: String
    @ViewBuilder var pulsanti: B
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icona).foregroundStyle(colore)
            Text(LocalizedStringKey(testo)).lineLimit(2)
            Spacer()
            pulsanti
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(colore.opacity(0.14))
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
                    Label(L("Live", "In tempo reale"), systemImage: "waveform.path.ecg").font(.headline)
                    Spacer()
                    Text(L("updated every second", "aggiornato ogni secondo")).font(.caption).foregroundStyle(.secondary)
                }
                if let c = stato.live {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], alignment: .leading, spacing: 14) {
                        ValoreLive(titolo: L("Processor", "Processore"), valore: "\(Int(c.cpu.rounded()))%", sotto: nil, storico: stato.storicoCPU, massimo: 100)
                        ValoreLive(titolo: L("Memory used", "Memoria usata"), valore: decimale(c.memoriaUsataGB) + " GB",
                                   sotto: L("of", "su") + " \(Int(c.memoriaTotaleGB.rounded())) GB", storico: nil, massimo: nil)
                        ValoreLive(titolo: L("Network ↓ / ↑", "Rete ↓ / ↑"), valore: formatoVelocita(c.reteGiu), sotto: "↑ " + formatoVelocita(c.reteSu),
                                   storico: stato.storicoRete, massimo: nil)
                        ValoreLive(titolo: L("Disk read / write", "Disco lettura / scrittura"), valore: formatoVelocita(c.discoLettura),
                                   sotto: L("write", "scrittura") + " " + formatoVelocita(c.discoScrittura), storico: nil, massimo: nil)
                        if let b = c.batteria {
                            ValoreLive(titolo: c.alimentatore ? (c.inCarica ? L("Battery (charging)", "Batteria (in carica)") : L("Battery (adapter)", "Batteria (alimentatore)"))
                                       : L("Battery", "Batteria"),
                                       valore: "\(b)%",
                                       sotto: [c.watt.map { decimale($0) + " W" },
                                               c.minutiRimasti.map { "\($0 / 60) h \($0 % 60) min" }].compactMap { $0 }.joined(separator: " · "),
                                       storico: nil, massimo: nil)
                        }
                        ValoreLive(titolo: L("Temperature", "Temperatura"), valore: c.termico.prefix(1).uppercased() + c.termico.dropFirst(),
                                   sotto: c.termicoLivello >= 2 ? L("the Mac is slowing down to cool off", "il Mac sta rallentando per raffreddarsi")
                                          : L("macOS thermal state", "stato termico di macOS"),
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
            Pagina {
                Titolo(titolo: L("Leftovers", "Residui"),
                       sottotitolo: L("Files left by apps that are gone and startup items pointing to deleted programs.",
                                      "File lasciati da app che non ci sono più e avvii automatici che puntano a programmi cancellati."))
                Riquadro {
                    Label(L("Selected leftovers are set aside in a Regia folder, not deleted: with Undo they go back where they were. Those marked \"data\" are excluded by default because they may contain documents or settings.",
                            "I residui scelti vengono messi da parte in una cartella di Regia, non cancellati: con Annulla tornano al loro posto. Quelli segnati come \"dati\" sono esclusi di serie perché possono contenere documenti o impostazioni."),
                          systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                }
                if !stato.orfaniCalcolati {
                    Button { stato.cercaOrfani() } label: { Label(L("Find Leftovers", "Cerca residui"), systemImage: "magnifyingglass") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                } else if stato.orfani.isEmpty {
                    Riquadro { Label(L("No leftovers found: the Mac is clean.", "Nessun residuo trovato: il Mac è pulito."), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
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
            if stato.orfaniCalcolati && !stato.orfani.isEmpty {
                Divider()
                HStack {
                    let n = stato.orfaniScelti.count
                    Text(L("\(n) selected", "\(n) scelti") + " · \(formatoByte(stato.orfani.filter { stato.orfaniScelti.contains($0.id) }.reduce(0) { $0 + $1.dimensione }))")
                        .font(.headline)
                    Spacer()
                    Button(L("Search Again", "Cerca di nuovo")) { stato.cercaOrfani() }
                    Button(L("Set Aside…", "Metti da parte…")) { conferma = true }.buttonStyle(.borderedProminent).disabled(n == 0)
                }
                .padding(12).background(.bar)
            }
        }
        .confirmationDialog(L("Set aside \(stato.orfaniScelti.count) leftovers?", "Mettere da parte \(stato.orfaniScelti.count) residui?"), isPresented: $conferma) {
            Button(L("Set Aside", "Metti da parte")) { stato.mettiDaParteOrfani() }
        } message: { Text(L("They're moved to a Regia folder. With Undo (History) they go back where they were.",
                            "Vengono spostati in una cartella di Regia. Con Annulla (Cronologia) tornano al loro posto.")) }
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
                    Text(r.tipo.nome).fontWeight(.medium)
                    if r.delicato { Etichetta(testo: L("data", "dati"), colore: .orange) }
                }
                Text(r.percorso.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(formatoByte(r.dimensione)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Button { NSWorkspace.shared.activateFileViewerSelecting([r.percorso]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help(L("Show in Finder", "Mostra nel Finder"))
        }
    }
}

// MARK: - App installate

struct VistaApp: View {
    @EnvironmentObject var stato: Stato
    @State private var cerca = ""
    @State private var ordine = 0   // 0 nome, 1 dimensione

    var body: some View {
        // Usa Pagina (ScrollView alla base) come le altre sezioni: con List/ScrollView
        // dentro un VStack la colonna si allungava oltre la finestra e spariva la barra laterale.
        Pagina {
            Titolo(titolo: L("Installed Apps", "App installate"),
                   sottotitolo: L("\"Uninstall and Clean\" moves the app to the Trash together with the files it leaves in Library. It shows you the list first.",
                                  "\"Disinstalla e pulisci\" sposta l'app nel Cestino insieme ai file che lascia in Libreria. Prima ti mostra l'elenco."))
            HStack {
                TextField(L("Search by name…", "Cerca per nome…"), text: $cerca).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                Picker("", selection: $ordine) { Text(L("By Name", "Per nome")).tag(0); Text(L("By Size", "Per dimensione")).tag(1) }
                    .pickerStyle(.segmented).frame(width: 230).labelsHidden()
                Spacer()
                Text("\(stato.app.count) app · \(formatoByte(stato.app.reduce(0) { $0 + ($1.dimensione ?? 0) }))")
                    .foregroundStyle(.secondary).monospacedDigit()
                Button { stato.caricaApp() } label: { Image(systemName: "arrow.clockwise") }.help(L("Reload the list", "Rileggi l'elenco"))
            }
            let elenco = filtrate
            LazyVStack(spacing: 0) {
                ForEach(Array(elenco.enumerated()), id: \.element.id) { i, a in
                    rigaApp(a)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(i.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
                }
                if elenco.isEmpty {
                    Text(stato.app.isEmpty ? L("Loading…", "Caricamento…") : L("No app found.", "Nessuna app trovata."))
                        .foregroundStyle(.secondary).padding(20)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        }
        .onAppear { if stato.app.isEmpty { stato.caricaApp() } }
    }

    func rigaApp(_ a: AppInstallata) -> some View {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: a.percorso.path)).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(a.nome).fontWeight(.medium)
                            if a.daAppStore { Etichetta(testo: "App Store", colore: .blue) }
                            if a.protetta { Etichetta(testo: L("system", "di sistema"), colore: .secondary) }
                        }
                        Text("\(a.versione.isEmpty ? "" : "v\(a.versione) · ")\(a.bundleID)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(a.dimensione.map(formatoByte) ?? "…").foregroundStyle(.secondary).monospacedDigit()
                    Button(L("Uninstall and Clean…", "Disinstalla e pulisci…")) { stato.preparaDisinstallazione(a) }
                        .disabled(a.protetta).controlSize(.small)
                }
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
                        Text(L("Uninstall", "Disinstalla") + " \(a.nome)").font(.title2.bold())
                        Text(a.percorso.path).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let d = disinst {
                    Label(L("\(a.nome) has its own uninstaller: \"\(d.nome)\". It's better to use it, because it also removes system components.",
                            "\(a.nome) ha un suo programma di disinstallazione: \"\(d.nome)\". È meglio usare quello, perché toglie anche i componenti di sistema."),
                          systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button(L("Open", "Apri") + " \(d.nome)") { NSWorkspace.shared.open(d.percorso); stato.residuiApp = nil }
                }
                Text(residui.isEmpty ? L("No files left in Library: only the app goes to the Trash.", "Nessun file rimasto in Libreria: va nel Cestino solo l'app.")
                     : L("The app and the files selected below go to the Trash. Those marked \"data\" may contain documents or settings: by default they stay.",
                         "Va nel Cestino l'app e i file scelti qui sotto. Quelli segnati \"dati\" possono contenere documenti o impostazioni: di serie restano."))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !residui.isEmpty {
                    List(residui) { r in
                        RigaResiduo(r: r, scelti: Binding(get: { stato.residuiApp?.scelti ?? [] },
                                                          set: { stato.residuiApp?.scelti = $0 }))
                    }
                    .frame(minHeight: 200)
                }
                if stato.modalitaProva {
                    Label(L("Test mode is on: you'll see what would happen, without changing anything.", "Modalità prova accesa: vedrai cosa succederebbe, senza cambiare niente."),
                          systemImage: "testtube.2")
                        .foregroundStyle(.orange).font(.callout)
                }
                HStack {
                    Spacer()
                    Button(L("Cancel", "Annulla")) { stato.residuiApp = nil }.keyboardShortcut(.cancelAction)
                    Button(stato.modalitaProva ? L("Test", "Prova") : L("Move to Trash", "Sposta nel Cestino")) { stato.disinstalla() }
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
        Pagina {
            Titolo(titolo: L("Maintenance", "Manutenzione"),
                   sottotitolo: L("Checks and small repairs with Apple's tools. Checks only read.", "Controlli e piccole riparazioni con gli strumenti di Apple. I controlli leggono soltanto."))
            ForEach(Strumento.Gruppo.allCases, id: \.self) { g in
                Riquadro {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(g.nome).font(.headline)
                        let lista = Manutenzione.strumenti.filter { $0.gruppo == g }
                        ForEach(lista) { s in
                            HStack(alignment: .center, spacing: 12) {
                                IconaColorata(simbolo: s.icona, colore: g == .controlli ? .blue : (g == .rete ? .teal : .orange), lato: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(s.titolo).fontWeight(.medium)
                                        if s.serveAdmin { Image(systemName: "lock").foregroundStyle(.secondary).help(L("Asks for the Mac password", "Chiede la password del Mac")) }
                                    }
                                    Text(s.spiegazione).font(.callout).foregroundStyle(.secondary)
                                    if let d = s.durata { Text(L("Duration", "Durata") + ": \(d)").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if stato.inCorso == s.id {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Button(s.modifica ? L("Run…", "Esegui…") : L("Check", "Controlla")) {
                                        if s.modifica { daConfermare = s } else { stato.avviaStrumento(s) }
                                    }
                                    .disabled(stato.inCorso != nil)
                                }
                            }
                            if s.id != lista.last?.id { Divider() }
                        }
                    }
                }
            }
        }
        .confirmationDialog(daConfermare?.titolo ?? "", isPresented: Binding(get: { daConfermare != nil }, set: { if !$0 { daConfermare = nil } })) {
            Button(stato.modalitaProva ? L("Test", "Prova") : L("Run", "Esegui")) { if let s = daConfermare { stato.avviaStrumento(s) }; daConfermare = nil }
        } message: {
            Text([daConfermare?.spiegazione, daConfermare?.avviso,
                  daConfermare?.serveAdmin == true ? L("macOS will ask for the password: you type it in its window.", "macOS chiederà la password: la scrivi tu nella sua finestra.") : nil]
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
