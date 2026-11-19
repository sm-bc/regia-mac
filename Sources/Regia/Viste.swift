import SwiftUI

// MARK: - Finestra principale

struct FinestraPrincipale: View {
    @EnvironmentObject var stato: Stato
    @State private var confermaAnnullaTutto = false

    var body: some View {
        NavigationSplitView {
            List(selection: $stato.sezione) {
                ForEach(Sezione.gruppi, id: \.0) { gruppo in
                    Section(gruppo.0) {
                        ForEach(gruppo.1) { s in Label(s.rawValue, systemImage: s.icona).tag(s) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { PiedeBarra() }
        } detail: {
            VStack(spacing: 0) {
                BannerAvvisi()
                ZStack {
                    switch stato.sezione ?? .panoramica {
                    case .panoramica: VistaPanoramica()
                    case .profili: VistaProfili()
                    case .ritocchi: VistaRitocchi()
                    case .pulizia: VistaPulizia()
                    case .residui: VistaResidui()
                    case .app: VistaApp()
                    case .avvio: VistaAvvio()
                    case .manutenzione: VistaManutenzione()
                    case .cronologia: VistaCronologia()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                if let o = stato.occupato {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text(o).font(.callout).foregroundStyle(.secondary) }
                }
            }
            ToolbarItem {
                Button { stato.aggiornaTutto() } label: { Label("Aggiorna", systemImage: "arrow.clockwise") }
                    .help("Analizza di nuovo il Mac")
            }
            ToolbarItem {
                Button(role: .destructive) { confermaAnnullaTutto = true } label: {
                    Label("Annulla tutto", systemImage: "arrow.uturn.backward.circle")
                }
                .help("Riporta tutte le impostazioni com'erano prima di Regia")
                .disabled(stato.modifiche.isEmpty)
            }
        }
        .confirmationDialog("Riportare tutto com'era?", isPresented: $confermaAnnullaTutto) {
            Button("Annulla tutte le \(stato.modifiche.count) modifiche", role: .destructive) { stato.annullaTutto() }
        } message: {
            Text("Le impostazioni cambiate da Regia tornano ai valori di prima. I file spostati nel Cestino restano nel Cestino.")
        }
        .sheet(isPresented: Binding(get: { stato.anteprima != nil }, set: { if !$0 { stato.anteprima = nil } })) {
            VistaAnteprima()
        }
        .sheet(isPresented: Binding(get: { stato.residuiApp != nil }, set: { if !$0 { stato.residuiApp = nil } })) {
            VistaDisinstalla()
        }
        .sheet(item: $stato.risultato) { r in VistaRisultato(r: r) }
        .alert(stato.avviso?.titolo ?? "", isPresented: Binding(get: { stato.avviso != nil }, set: { if !$0 { stato.avviso = nil } })) {
            Button("OK") { stato.avviso = nil }
        } message: { Text(stato.avviso?.testo ?? "") }
        .disabled(stato.occupato?.hasPrefix("Applico") == true || stato.occupato?.hasPrefix("Riporto") == true)
        .task { stato.aggiornaTutto() }
    }
}

// MARK: - Elementi comuni

struct Titolo: View {
    let titolo: String
    let sottotitolo: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titolo).font(.largeTitle.bold())
            Text(sottotitolo).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Riquadro<C: View>: View {
    @ViewBuilder var contenuto: C
    var body: some View {
        contenuto
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct Etichetta: View {
    let testo: String
    let colore: Color
    var body: some View {
        Text(testo).font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(colore.opacity(0.15)))
            .foregroundStyle(colore)
    }
}

// MARK: - Panoramica

struct VistaPanoramica: View {
    @EnvironmentObject var stato: Stato

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Titolo(titolo: "Panoramica", sottotitolo: "Come sta il tuo Mac adesso. Qui non si cambia niente.")
                PannelloLive()
                if let p = stato.panoramica {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        Indicatore(icona: "internaldrive", titolo: "Disco libero", valore: formatoByte(p.discoLibero),
                                   dettaglio: "su \(formatoByte(p.discoTotale))", livello: p.percentoDiscoLibero,
                                   colore: p.percentoDiscoLibero < 0.1 ? .red : (p.percentoDiscoLibero < 0.2 ? .orange : .green))
                        Indicatore(icona: "memorychip", titolo: "Memoria libera", valore: p.memoriaLibera.map { "\($0)%" } ?? "—",
                                   dettaglio: "su \(Int(p.memoriaGB.rounded())) GB", livello: Double(p.memoriaLibera ?? 0) / 100,
                                   colore: (p.memoriaLibera ?? 100) < 20 ? .red : .green)
                        if let s = p.batteriaSalute {
                            Indicatore(icona: p.inCarica ? "battery.100percent.bolt" : "battery.75percent", titolo: "Salute batteria",
                                       valore: "\(s)%", dettaglio: "\(p.batteriaCicli ?? 0) cicli · carica \(p.batteriaPercento ?? 0)%",
                                       livello: Double(s) / 100, colore: s < 80 ? .red : .green)
                        }
                        Indicatore(icona: "clock", titolo: "Acceso da", valore: p.acceso,
                                   dettaglio: "dall'ultimo riavvio", livello: nil, colore: p.giorniAcceso > 7 ? .orange : .green)
                    }

                    Riquadro {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Consigli").font(.headline)
                            ForEach(stato.consigli) { c in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: c.livello == .ok ? "checkmark.circle.fill"
                                          : (c.livello == .attenzione ? "exclamationmark.circle.fill" : "xmark.octagon.fill"))
                                        .foregroundStyle(c.livello == .ok ? .green : (c.livello == .attenzione ? .orange : .red))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.titolo).fontWeight(.medium)
                                        Text(c.dettaglio).font(.callout).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        TabellaProcessi(titolo: "Usano più CPU", processi: p.processiCPU, valore: { String(format: "%.0f%%", $0.cpu) })
                        TabellaProcessi(titolo: "Usano più memoria", processi: p.processiMemoria,
                                        valore: { $0.memoriaMB > 1024 ? String(format: "%.1f GB", $0.memoriaMB / 1024) : String(format: "%.0f MB", $0.memoriaMB) })
                    }

                    Text("\(p.modello) · \(p.chip) · \(p.sistema)").font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView("Analizzo il Mac…").frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(24)
        }
    }
}

struct Indicatore: View {
    let icona: String, titolo: String, valore: String, dettaglio: String
    let livello: Double?
    let colore: Color
    var body: some View {
        Riquadro {
            VStack(alignment: .leading, spacing: 8) {
                Label(titolo, systemImage: icona).font(.callout).foregroundStyle(.secondary)
                Text(valore).font(.title.bold()).monospacedDigit()
                if let l = livello { ProgressView(value: min(max(l, 0), 1)).tint(colore) }
                Text(dettaglio).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct TabellaProcessi: View {
    let titolo: String
    let processi: [Processo]
    let valore: (Processo) -> String
    var body: some View {
        Riquadro {
            VStack(alignment: .leading, spacing: 6) {
                Text(titolo).font(.headline)
                ForEach(processi.prefix(6)) { p in
                    HStack {
                        Text(p.nome).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(valore(p)).monospacedDigit().foregroundStyle(.secondary)
                    }.font(.callout)
                }
            }
        }
    }
}

// MARK: - Profili

struct VistaProfili: View {
    @EnvironmentObject var stato: Stato
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Titolo(titolo: "Profili", sottotitolo: "Un gruppo di ritocchi pronto per un uso. Prima di applicare vedi sempre l'anteprima.")
                HStack {
                    Spacer()
                    Button { stato.preparaPredefinito() } label: { Label("Riporta al predefinito…", systemImage: "arrow.counterclockwise") }
                        .help("Rimette le voci di Regia come su un Mac appena installato (con anteprima, annullabile)")
                        .disabled(stato.statoRitocchi.isEmpty)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(Catalogo.profili + stato.profiliPersonali) { p in
                        let attivi = p.ritocchi.filter { stato.statoRitocchi[$0]?.attivo == true }.count
                        Riquadro {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: p.icona).font(.title2).foregroundStyle(.tint)
                                    Text(p.nome).font(.title2.bold())
                                    Spacer()
                                    Etichetta(testo: "\(attivi)/\(p.ritocchi.count) attivi", colore: attivi == p.ritocchi.count ? .green : .secondary)
                                }
                                Text(p.descrizione).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(p.ritocchi, id: \.self) { id in
                                        if let t = Catalogo.ritocco(id) {
                                            HStack(spacing: 6) {
                                                Image(systemName: stato.statoRitocchi[id]?.attivo == true ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(stato.statoRitocchi[id]?.attivo == true ? .green : .secondary)
                                                Text(t.titolo)
                                                if t.serveAdmin { Image(systemName: "lock").foregroundStyle(.secondary).help("Chiede la password del Mac") }
                                            }.font(.callout)
                                        }
                                    }
                                }
                                HStack {
                                    Button { stato.preparaAnteprima(titolo: "Profilo \(p.nome)", ids: p.ritocchi, avviso: p.avviso) } label: {
                                        Text("Anteprima e applica").frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                    .disabled(stato.statoRitocchi.isEmpty)
                                    if p.personale {
                                        Button(role: .destructive) { stato.eliminaProfilo(p) } label: { Image(systemName: "trash") }
                                            .controlSize(.large).help("Elimina questo profilo")
                                    }
                                }
                            }
                        }
                    }
                }
                Text("🔒 = chiede la password del Mac (la scrivi tu nella finestra di macOS). Per creare un profilo tuo: scegli i ritocchi in Ritocchi e premi \"Salva come profilo\".")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

// MARK: - Ritocchi

struct VistaRitocchi: View {
    @EnvironmentObject var stato: Stato
    @State private var chiediNome = false
    @State private var nomeProfilo = ""
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Titolo(titolo: "Ritocchi", sottotitolo: "Scegli uno per uno cosa cambiare. Tutto si può annullare.")
                    ForEach(Categoria.allCases) { c in
                        let lista = Catalogo.ritocchi.filter { $0.categoria == c }
                        Riquadro {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(c.rawValue, systemImage: c.icona).font(.headline)
                                ForEach(lista) { t in RigaRitocco(t: t) }
                            }
                        }
                    }
                    Riquadro {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Da fare a mano", systemImage: "hand.tap").font(.headline)
                            Text("macOS non lascia cambiare queste impostazioni da un'app: il pulsante apre la pagina giusta.")
                                .font(.callout).foregroundStyle(.secondary)
                            ForEach(Catalogo.consigliManuali, id: \.titolo) { c in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.titolo).fontWeight(.medium)
                                        Text(c.spiegazione).font(.callout).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Apri") { stato.apri(c.url) }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            if !stato.selezionati.isEmpty {
                Divider()
                HStack {
                    Text("\(stato.selezionati.count) ritocchi scelti")
                    Spacer()
                    Button("Togli selezione") { stato.selezionati.removeAll() }
                    Button("Salva come profilo…") { chiediNome = true }
                    Button("Anteprima e applica") {
                        let ordine = Catalogo.ritocchi.map(\.id).filter { stato.selezionati.contains($0) }
                        stato.preparaAnteprima(titolo: "Ritocchi scelti", ids: ordine)
                    }.buttonStyle(.borderedProminent)
                }
                .padding(12).background(.bar)
            }
        }
        .alert("Nome del profilo", isPresented: $chiediNome) {
            TextField("Es. Lavoro in ufficio", text: $nomeProfilo)
            Button("Salva") { stato.salvaProfiloPersonale(nome: nomeProfilo); nomeProfilo = "" }
            Button("Annulla", role: .cancel) { nomeProfilo = "" }
        } message: { Text("Il profilo conterrà i \(stato.selezionati.count) ritocchi scelti.") }
    }
}

struct RigaRitocco: View {
    @EnvironmentObject var stato: Stato
    let t: Ritocco
    var body: some View {
        let s = stato.statoRitocchi[t.id]
        let modifica = stato.motore.modifica(per: t.id)
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { stato.selezionati.contains(t.id) },
                                     set: { if $0 { stato.selezionati.insert(t.id) } else { stato.selezionati.remove(t.id) } }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(s?.attivo == true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(t.titolo).fontWeight(.medium)
                    if t.serveAdmin { Image(systemName: "lock").foregroundStyle(.secondary).help("Chiede la password del Mac") }
                }
                Text(t.spiegazione).font(.callout).foregroundStyle(.secondary)
                if let n = t.nota { Text(n).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if s?.attivo == true { Etichetta(testo: "Attivo", colore: .green) }
                else { Etichetta(testo: "Ora: \(s?.testo ?? "…")", colore: .secondary) }
                if let m = modifica {
                    Button("Ripristina") { stato.annulla(m) }.controlSize(.small)
                        .help("Torna a: \(m.originale ?? (m.originaleEnergia.map { String($0) } ?? "predefinito di macOS"))")
                }
            }
        }
    }
}

// MARK: - Anteprima

struct VistaAnteprima: View {
    @EnvironmentObject var stato: Stato
    var body: some View {
        let voci = stato.anteprima ?? []
        let scelte = voci.filter { $0.scelta }
        VStack(alignment: .leading, spacing: 14) {
            Text("Anteprima: \(stato.titoloAnteprima)").font(.title2.bold())
            Text(stato.anteprimaPredefinito ? "Ecco cosa cambia. Prima di applicare Regia salva una copia delle impostazioni."
                 : "Ecco cosa cambia. Quelli già attivi sono esclusi. Prima di applicare Regia salva una copia delle impostazioni.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let a = stato.avvisoAnteprima {
                Label(a, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if stato.modalitaProva {
                Label("Modalità prova accesa: vedrai cosa succederebbe, senza cambiare niente.", systemImage: "testtube.2")
                    .foregroundStyle(.orange).font(.callout)
            }
            List {
                ForEach(voci.indices, id: \.self) { i in
                    let v = voci[i]
                    HStack(alignment: .top) {
                        Toggle("", isOn: Binding(get: { stato.anteprima?[i].scelta ?? false }, set: { stato.anteprima?[i].scelta = $0 }))
                            .toggleStyle(.checkbox).labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(v.ritocco.titolo).fontWeight(.medium)
                                if v.ritocco.serveAdmin { Image(systemName: "lock").foregroundStyle(.secondary) }
                            }
                            HStack(spacing: 6) {
                                Text(v.ora).foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                Text(v.nuovo).foregroundStyle(.tint)
                            }.font(.callout)
                        }
                    }
                    .opacity(!stato.anteprimaPredefinito && stato.statoRitocchi[v.ritocco.id]?.attivo == true ? 0.5 : 1)
                }
            }
            .frame(minHeight: 260)
            if scelte.contains(where: { $0.ritocco.serveAdmin }) {
                Label("macOS chiederà la password per le impostazioni di energia. La scrivi tu nella sua finestra.", systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if scelte.contains(where: { $0.ritocco.riavvia != nil }) {
                Label("Dock o Finder si riavviano un attimo: le finestre aperte restano.", systemImage: "arrow.clockwise")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Annulla") { stato.anteprima = nil }.keyboardShortcut(.cancelAction)
                Button(stato.modalitaProva ? "Prova \(scelte.count) modifiche" : "Applica \(scelte.count) modifiche") { stato.applicaAnteprima() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(scelte.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 580, height: 600)
    }
}

// MARK: - Pulizia

struct VistaPulizia: View {
    @EnvironmentObject var stato: Stato
    @State private var conferma = false
    @State private var confermaCestino = false
    @State private var dettaglio: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Titolo(titolo: "Pulizia", sottotitolo: "I file vanno nel Cestino, non vengono cancellati: se serve li recuperi.")
                    HStack(spacing: 10) {
                        Button { stato.scegliPulizia(accurata: false) } label: {
                            Label("Pulizia sicura", systemImage: "checkmark.shield")
                        }.help("Cache, log e file di Xcode: si ricreano da soli")
                        Button { stato.scegliPulizia(accurata: true) } label: {
                            Label("Pulizia accurata", systemImage: "sparkles")
                        }.help("Anche supporto iPhone di Xcode, simulatori e download più vecchi di 90 giorni")
                        Spacer()
                    }.controlSize(.large)
                    ForEach(stato.zone) { z in
                        Riquadro {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 10) {
                                    Toggle("", isOn: Binding(get: { stato.zoneScelte.contains(z.id) },
                                                             set: { if $0 { stato.zoneScelte.insert(z.id) } else { stato.zoneScelte.remove(z.id) } }))
                                        .toggleStyle(.checkbox).labelsHidden().disabled(!z.calcolata || z.elementi.isEmpty)
                                    Image(systemName: z.icona).font(.title3).foregroundStyle(.tint).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(z.titolo).fontWeight(.medium)
                                        Text(z.spiegazione).font(.callout).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if z.calcolata {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(formatoByte(z.dimensione)).font(.title3.bold()).monospacedDigit()
                                            Text("\(z.elementi.count) elementi").font(.caption).foregroundStyle(.secondary)
                                        }
                                    } else if z.suRichiesta {
                                        Button("Calcola") { stato.calcolaZona(z.id) }
                                    } else { ProgressView().controlSize(.small) }
                                }
                                if z.calcolata && !z.elementi.isEmpty {
                                    DisclosureGroup(isExpanded: Binding(get: { dettaglio == z.id }, set: { dettaglio = $0 ? z.id : nil })) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            ForEach(z.elementi.prefix(40), id: \.self) { u in
                                                HStack {
                                                    Text(u.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                                    Spacer()
                                                    Button { stato.mostraNelFinder(u) } label: { Image(systemName: "magnifyingglass") }
                                                        .buttonStyle(.borderless).help("Mostra nel Finder")
                                                }.font(.callout)
                                            }
                                            if z.elementi.count > 40 { Text("…e altri \(z.elementi.count - 40)").font(.caption).foregroundStyle(.secondary) }
                                        }.padding(.top, 4)
                                    } label: { Text("Vedi cosa contiene").font(.callout) }
                                }
                            }
                        }
                    }
                    Riquadro {
                        HStack {
                            Image(systemName: "trash").font(.title3).foregroundStyle(.tint).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Svuota il Cestino").fontWeight(.medium)
                                Text("Libera davvero lo spazio. Questa volta è definitivo.").font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Svuota…", role: .destructive) { confermaCestino = true }
                        }
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("Scelto: \(formatoByte(stato.byteScelti))").font(.headline).monospacedDigit()
                Spacer()
                Button("Sposta nel Cestino…") { conferma = true }
                    .buttonStyle(.borderedProminent).disabled(stato.byteScelti == 0)
            }
            .padding(12).background(.bar)
        }
        .confirmationDialog("Spostare \(formatoByte(stato.byteScelti)) nel Cestino?", isPresented: $conferma) {
            Button("Sposta nel Cestino") { stato.pulisci() }
        } message: {
            Text(stato.zone.filter { stato.zoneScelte.contains($0.id) && $0.calcolata }
                .map { "• \($0.titolo): \(formatoByte($0.dimensione))" }.joined(separator: "\n")
                 + "\n\nConviene chiudere prima le app che non stai usando.")
        }
        .confirmationDialog("Svuotare il Cestino?", isPresented: $confermaCestino) {
            Button("Svuota definitivamente", role: .destructive) { stato.svuotaCestino() }
        } message: { Text("Tutto quello che c'è nel Cestino verrà eliminato per sempre. Non si può annullare.") }
    }
}

// MARK: - Avvio

struct VistaAvvio: View {
    @EnvironmentObject var stato: Stato
    @State private var daDisattivare: ElementoAvvio? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Titolo(titolo: "Avvio", sottotitolo: "Programmi che partono da soli in background.")
                ForEach([ElementoAvvio.Livello.utente, .sistemaAgente, .sistemaServizio], id: \.rawValue) { livello in
                    let lista = stato.avvio.filter { $0.livello == livello }
                    if !lista.isEmpty {
                        Riquadro {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(livello.nome).font(.headline)
                                if livello != .utente {
                                    Text("Installati per tutto il Mac: si tolgono disinstallando l'app (per esempio con AppCleaner).")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                ForEach(lista) { e in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(nomeLeggibile(e.nome)).fontWeight(.medium).strikethrough(e.disattivato)
                                            Text(e.programma.isEmpty ? e.nome : e.programma).font(.caption).foregroundStyle(.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer()
                                        if e.disattivato {
                                            Etichetta(testo: "Disattivato", colore: .orange)
                                            Button("Riattiva") { stato.riattiva(e) }
                                        } else if livello == .utente {
                                            Button("Disattiva…") { daDisattivare = e }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Riquadro {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Elementi di login delle app").fontWeight(.medium)
                            Text("Le app aggiunte all'avvio da Impostazioni di Sistema si gestiscono lì.").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Apri") { stato.apri("x-apple.systempreferences:com.apple.LoginItems-Settings.extension") }
                    }
                }
            }
            .padding(24)
        }
        .confirmationDialog("Disattivare \(nomeLeggibile(daDisattivare?.nome ?? ""))?",
                            isPresented: Binding(get: { daDisattivare != nil }, set: { if !$0 { daDisattivare = nil } })) {
            Button("Disattiva") { if let e = daDisattivare { stato.disattiva(e) }; daDisattivare = nil }
        } message: {
            Text("Non partirà più da solo. Il file viene messo da parte, non cancellato: lo riattivi quando vuoi.")
        }
    }

    func nomeLeggibile(_ etichetta: String) -> String {
        let noti = ["com.google.keystone": "Aggiornamenti Google", "com.google.GoogleUpdater": "Aggiornamenti Google",
                    "com.valvesoftware.steamclean": "Steam (pulizia)", "com.adobe": "Adobe", "com.microsoft": "Microsoft",
                    "us.zoom": "Zoom", "com.dropbox": "Dropbox", "com.spotify": "Spotify"]
        for (k, v) in noti where etichetta.hasPrefix(k) {
            let resto = etichetta.dropFirst(k.count).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return resto.isEmpty ? v : "\(v) · \(resto)"
        }
        return etichetta
    }
}

// MARK: - Cronologia

struct VistaCronologia: View {
    @EnvironmentObject var stato: Stato
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Titolo(titolo: "Cronologia", sottotitolo: "Cosa ha cambiato Regia e come annullarlo.")
                Riquadro {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Modifiche attive (\(stato.modifiche.count))").font(.headline)
                        if stato.modifiche.isEmpty {
                            Text("Nessuna: il Mac è com'era prima di Regia.").foregroundStyle(.secondary)
                        }
                        ForEach(stato.modifiche.reversed()) { m in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.titolo).fontWeight(.medium)
                                    Text("\(m.data.formatted(date: .abbreviated, time: .shortened)) · prima: \(prima(m)) · ora: \(m.nuovo)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Annulla") { stato.annulla(m) }
                            }
                        }
                    }
                }
                Riquadro {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Registro").font(.headline)
                            Spacer()
                            Button("Apri cartella") { stato.mostraNelFinder(stato.motore.cartella) }.controlSize(.small)
                        }
                        if stato.registro.isEmpty { Text("Ancora vuoto.").foregroundStyle(.secondary) }
                        ForEach(Array(stato.registro.prefix(200).enumerated()), id: \.offset) { _, r in
                            Text(r).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    func prima(_ m: Modifica) -> String {
        switch m.tipo {
        case .preferenza: return m.originale ?? "predefinito"
        case .energia: return Catalogo.testoEnergia(chiave: m.chiave ?? "", valore: m.originaleEnergia)
        case .avvio: return "attivo"
        case .residuo: return m.percorsoOriginale ?? ""
        }
    }
}
