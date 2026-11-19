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
                        ForEach(gruppo.1) { s in
                            Label { Text(s.nome) } icon: { IconaColorata(simbolo: s.icona, colore: s.colore) }
                                .badge(badge(s))
                                .tag(s)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) { PiedeBarra() }
        } detail: {
            VStack(spacing: 0) {
                BannerAvvisi()
                ZStack {
                    switch stato.sezione ?? .panoramica {
                    case .panoramica: VistaPanoramica()
                    case .suggerimenti: VistaSuggerimenti()
                    case .profili: VistaProfili()
                    case .ritocchi: VistaRitocchi()
                    case .pulizia: VistaPulizia()
                    case .residui: VistaResidui()
                    case .app: VistaApp()
                    case .avvio: VistaAvvio()
                    case .aggiornamentiApp: VistaAggiornamentiApp()
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
                Button { stato.aggiornaTutto() } label: { Label(L("Scan", "Analizza"), systemImage: "arrow.clockwise") }
                    .help(L("Analyse the Mac again", "Analizza di nuovo il Mac"))
                    .keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem {
                Button(role: .destructive) { confermaAnnullaTutto = true } label: {
                    Label(L("Undo All", "Annulla tutto"), systemImage: "arrow.uturn.backward.circle")
                }
                .help(L("Put back all settings as they were before Regia", "Riporta tutte le impostazioni com'erano prima di Regia"))
                .disabled(stato.modifiche.isEmpty)
            }
        }
        .confirmationDialog(L("Put everything back as it was?", "Riportare tutto com'era?"), isPresented: $confermaAnnullaTutto) {
            Button(L("Undo all \(stato.modifiche.count) changes", "Annulla tutte le \(stato.modifiche.count) modifiche"), role: .destructive) { stato.annullaTutto() }
        } message: {
            Text(L("Settings changed by Regia go back to their previous values. Files moved to the Trash stay in the Trash.",
                   "Le impostazioni cambiate da Regia tornano ai valori di prima. I file spostati nel Cestino restano nel Cestino."))
        }
        .sheet(isPresented: Binding(get: { stato.anteprima != nil }, set: { if !$0 { stato.anteprima = nil } })) {
            VistaAnteprima()
        }
        .sheet(isPresented: Binding(get: { stato.residuiApp != nil }, set: { if !$0 { stato.residuiApp = nil } })) {
            VistaDisinstalla()
        }
        .sheet(isPresented: $stato.mostraFeedback) { VistaFeedback() }
        .sheet(item: $stato.risultato) { r in VistaRisultato(r: r) }
        .alert(stato.avviso?.titolo ?? "", isPresented: Binding(get: { stato.avviso != nil }, set: { if !$0 { stato.avviso = nil } })) {
            Button("OK") { stato.avviso = nil }
        } message: { Text(stato.avviso?.testo ?? "") }
        .disabled(stato.bloccato)
        .id(stato.lingua)
        .task {
            stato.aggiornaTutto()
            // Solo per le prove: REGIA_FOTO=/percorso.png salva una foto della finestra e chiude Regia.
            let amb = ProcessInfo.processInfo.environment
            if let percorso = amb["REGIA_FOTO"] {
                if amb["REGIA_FEEDBACK"] == "1" { stato.mostraFeedback = true }
                if let l = amb["REGIA_PROVA_LINGUA"].flatMap(Lingua.init(rawValue:)) {
                    try? await Task.sleep(for: .seconds(4))
                    stato.cambiaLingua(l)
                }
                try? await Task.sleep(for: .seconds(Double(amb["REGIA_ATTESA"] ?? "8") ?? 8))
                let finestra = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.sheetParent == nil })
                if let c = (finestra?.attachedSheet ?? finestra)?.contentView, let v = c.superview ?? Optional(c),
                   let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: percorso))
                }
                exit(0)
            }
        }
    }

    func badge(_ s: Sezione) -> Int {
        switch s {
        case .aggiornamentiApp: return stato.aggiornamentiApp?.disponibili.count ?? 0
        case .suggerimenti: return stato.controlli.filter { $0.livello != .ok }.count
        default: return 0
        }
    }
}

// MARK: - Elementi comuni

/// Icona bianca su quadratino colorato, come in Impostazioni di Sistema.
struct IconaColorata: View {
    let simbolo: String
    let colore: Color
    var lato: CGFloat = 22
    var body: some View {
        Image(systemName: simbolo)
            .font(.system(size: lato * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: lato, height: lato)
            .background(RoundedRectangle(cornerRadius: lato * 0.27, style: .continuous).fill(colore.gradient))
    }
}

struct Titolo: View {
    let titolo: String
    let sottotitolo: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titolo).font(.largeTitle.bold())
            Text(sottotitolo).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Riquadro<C: View>: View {
    @ViewBuilder var contenuto: C
    var body: some View {
        contenuto
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
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

struct SimboloLivello: View {
    let livello: Consiglio.Livello
    var body: some View {
        Image(systemName: livello == .ok ? "checkmark.circle.fill" : (livello == .attenzione ? "exclamationmark.circle.fill" : "xmark.octagon.fill"))
            .foregroundStyle(livello == .ok ? .green : (livello == .attenzione ? .orange : .red))
            .font(.title3)
    }
}

/// Contenitore comune delle schermate: scorrimento, margini e larghezza massima leggibile.
struct Pagina<C: View>: View {
    @ViewBuilder var contenuto: C
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { contenuto }
                .padding(24)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Panoramica

struct VistaPanoramica: View {
    @EnvironmentObject var stato: Stato
    @State private var confermaRiavvio = false

    var body: some View {
        Pagina {
            Titolo(titolo: L("Overview", "Panoramica"),
                   sottotitolo: L("How your Mac is doing right now. Nothing is changed here.", "Come sta il tuo Mac adesso. Qui non si cambia niente."))
            RiepilogoSalute()
            PannelloLive()
            if let p = stato.panoramica {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    Indicatore(icona: "internaldrive", titolo: L("Free disk", "Disco libero"), valore: formatoByte(p.discoLibero),
                               dettaglio: L("of", "su") + " \(formatoByte(p.discoTotale))", livello: p.percentoDiscoLibero,
                               colore: p.percentoDiscoLibero < 0.1 ? .red : (p.percentoDiscoLibero < 0.2 ? .orange : .green))
                    Indicatore(icona: "memorychip", titolo: L("Free memory", "Memoria libera"), valore: p.memoriaLibera.map { "\($0)%" } ?? "—",
                               dettaglio: L("of", "su") + " \(Int(p.memoriaGB.rounded())) GB", livello: Double(p.memoriaLibera ?? 0) / 100,
                               colore: (p.memoriaLibera ?? 100) < 20 ? .red : .green)
                    if let s = p.batteriaSalute {
                        Indicatore(icona: p.inCarica ? "battery.100percent.bolt" : "battery.75percent", titolo: L("Battery health", "Salute batteria"),
                                   valore: "\(s)%", dettaglio: L("\(p.batteriaCicli ?? 0) cycles · charge \(p.batteriaPercento ?? 0)%",
                                                                  "\(p.batteriaCicli ?? 0) cicli · carica \(p.batteriaPercento ?? 0)%"),
                                   livello: Double(s) / 100, colore: s < 80 ? .red : .green)
                    }
                    Indicatore(icona: "clock", titolo: L("On for", "Acceso da"), valore: p.acceso,
                               dettaglio: L("since the last restart", "dall'ultimo riavvio"), livello: nil,
                               colore: p.giorniAcceso >= Analisi.giorniPerRiavvio ? .orange : .green)
                }

                Riquadro {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L("Recommendations", "Consigli"), systemImage: "list.bullet.clipboard").font(.headline)
                        ForEach(stato.consigli) { c in
                            HStack(alignment: .center, spacing: 10) {
                                SimboloLivello(livello: c.livello)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.titolo).fontWeight(.medium)
                                    Text(c.dettaglio).font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let a = c.azione, let t = c.testoAzione {
                                    Button(t) { if a == .riavvia { confermaRiavvio = true } else { stato.eseguiConsiglio(a) } }
                                        .controlSize(.small)
                                }
                            }
                            if c.id != stato.consigli.last?.id { Divider() }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    TabellaProcessi(titolo: L("Most CPU", "Usano più CPU"), processi: p.processiCPU, valore: { "\(Int($0.cpu.rounded()))%" })
                    TabellaProcessi(titolo: L("Most memory", "Usano più memoria"), processi: p.processiMemoria,
                                    valore: { $0.memoriaMB > 1024 ? decimale($0.memoriaMB / 1024) + " GB" : "\(Int($0.memoriaMB)) MB" })
                }

                Text("\(p.modello) · \(p.chip) · \(p.sistema)").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(L("Analysing your Mac…", "Analizzo il Mac…")).frame(maxWidth: .infinity).padding(40)
            }
        }
        .confirmationDialog(L("Restart the Mac?", "Riavviare il Mac?"), isPresented: $confermaRiavvio) {
            Button(L("Restart", "Riavvia")) { stato.riavviaMac() }
        } message: { Text(L("Apps will ask you to save open documents.", "Le app chiederanno di salvare i documenti aperti.")) }
    }
}

/// Riquadro in cima alla Panoramica: esito della scansione in una riga.
struct RiepilogoSalute: View {
    @EnvironmentObject var stato: Stato
    var body: some View {
        let n = stato.daSistemare
        let pronto = stato.panoramica != nil && stato.occupato == nil
        let colore: Color = !pronto ? .blue : (n == 0 ? .green : .orange)
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(colore.gradient).frame(width: 54, height: 54)
                if pronto {
                    Image(systemName: n == 0 ? "checkmark" : "exclamationmark").font(.title.bold()).foregroundStyle(.white)
                } else {
                    ProgressView().controlSize(.small).tint(.white)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(!pronto ? L("Scanning…", "Scansione in corso…")
                     : (n == 0 ? L("Your Mac is in good shape", "Il tuo Mac è in forma")
                        : P(n, "thing to check", "things to check", "cosa da controllare", "cose da controllare")))
                    .font(.title2.bold())
                Text(sottotitolo).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if n > 0 && pronto && stato.controlli.contains(where: { $0.livello != .ok }) {
                Button(L("See tips", "Vedi suggerimenti")) { stato.sezione = .suggerimenti }
            }
            Button { stato.aggiornaTutto() } label: { Label(L("Scan again", "Analizza di nuovo"), systemImage: "arrow.clockwise") }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!pronto)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colore.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colore.opacity(0.25)))
    }

    var sottotitolo: String {
        guard let d = stato.ultimaScansione else { return L("Reading disk, memory, battery and security…", "Leggo disco, memoria, batteria e sicurezza…") }
        var t = L("Last scan", "Ultima scansione") + ": " + d.formatted(date: .omitted, time: .shortened)
        if let a = stato.aggiornamentiApp?.disponibili.count, a > 0 { t += " · " + P(a, "app update", "app updates", "aggiornamento app", "aggiornamenti app") }
        return t
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
        Pagina {
            HStack(alignment: .top) {
                Titolo(titolo: L("Profiles", "Profili"),
                       sottotitolo: L("A ready-made set of tweaks. You always see a preview before anything changes.",
                                      "Un gruppo di ritocchi pronto. Prima di applicare vedi sempre l'anteprima."))
                Button { stato.preparaPredefinito() } label: { Label(L("Restore Defaults…", "Riporta al predefinito…"), systemImage: "arrow.counterclockwise") }
                    .help(L("Puts Regia's settings back as on a freshly installed Mac (with preview, can be undone)",
                            "Rimette le voci di Regia come su un Mac appena installato (con anteprima, annullabile)"))
                    .disabled(stato.statoRitocchi.isEmpty)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(Catalogo.profili + stato.profiliPersonali) { p in SchedaProfilo(p: p) }
            }
            Text(L("🔒 = asks for the Mac password (you type it in the macOS window). To create your own profile: pick tweaks in Tweaks and press \"Save as Profile\".",
                   "🔒 = chiede la password del Mac (la scrivi tu nella finestra di macOS). Per creare un profilo tuo: scegli i ritocchi in Ritocchi e premi \"Salva come profilo\"."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SchedaProfilo: View {
    @EnvironmentObject var stato: Stato
    let p: Profilo
    @State private var espanso = false

    var colore: Color {
        switch p.id { case "massimo": return .orange; case "bilanciato": return .blue; case "sicuro": return .green; default: return .purple }
    }

    var body: some View {
        let attivi = p.ritocchi.filter { stato.statoRitocchi[$0]?.attivo == true }.count
        Riquadro {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconaColorata(simbolo: p.icona, colore: colore, lato: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.nome).font(.title2.bold())
                        Text(L("\(p.ritocchi.count) tweaks", "\(p.ritocchi.count) ritocchi")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Etichetta(testo: L("\(attivi)/\(p.ritocchi.count) active", "\(attivi)/\(p.ritocchi.count) attivi"),
                              colore: attivi == p.ritocchi.count ? .green : .secondary)
                }
                Text(p.descrizione).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(attivi), total: Double(max(p.ritocchi.count, 1))).tint(colore)
                DisclosureGroup(isExpanded: $espanso) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(p.ritocchi, id: \.self) { id in
                            if let t = Catalogo.ritocco(id) {
                                HStack(spacing: 6) {
                                    Image(systemName: stato.statoRitocchi[id]?.attivo == true ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(stato.statoRitocchi[id]?.attivo == true ? .green : .secondary)
                                    Text(t.titolo)
                                    if t.serveAdmin { Image(systemName: "lock").foregroundStyle(.secondary).help(L("Asks for the Mac password", "Chiede la password del Mac")) }
                                }.font(.callout)
                            }
                        }
                    }.padding(.top, 4)
                } label: { Text(L("What it changes", "Cosa cambia")).font(.callout) }
                HStack {
                    Button { stato.preparaAnteprima(titolo: L("Profile", "Profilo") + " \(p.nome)", ids: p.ritocchi, avviso: p.avviso) } label: {
                        Text(L("Preview and Apply", "Anteprima e applica")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(stato.statoRitocchi.isEmpty)
                    if p.personale {
                        Button(role: .destructive) { stato.eliminaProfilo(p) } label: { Image(systemName: "trash") }
                            .controlSize(.large).help(L("Delete this profile", "Elimina questo profilo"))
                    }
                }
            }
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
            Pagina {
                Titolo(titolo: L("Tweaks", "Ritocchi"),
                       sottotitolo: L("Choose one by one what to change. Everything can be undone.", "Scegli uno per uno cosa cambiare. Tutto si può annullare."))
                ForEach(Categoria.allCases) { c in
                    let lista = Catalogo.ritocchi.filter { $0.categoria == c }
                    Riquadro {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(c.nome, systemImage: c.icona).font(.headline)
                            ForEach(lista) { t in
                                RigaRitocco(t: t)
                                if t.id != lista.last?.id { Divider() }
                            }
                        }
                    }
                }
                Riquadro {
                    HStack {
                        Image(systemName: "hand.tap").font(.title3).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Settings to change by hand", "Impostazioni da cambiare a mano")).fontWeight(.medium)
                            Text(L("macOS doesn't let apps change some settings: you find them with an Open button in Tips.",
                                   "macOS non lascia cambiare alcune impostazioni da un'app: le trovi con il pulsante Apri in Suggerimenti."))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Go to Tips", "Vai a Suggerimenti")) { stato.sezione = .suggerimenti }
                    }
                }
            }
            if !stato.selezionati.isEmpty {
                Divider()
                HStack {
                    Text(P(stato.selezionati.count, "tweak selected", "tweaks selected", "ritocco scelto", "ritocchi scelti"))
                    Spacer()
                    Button(L("Clear Selection", "Togli selezione")) { stato.selezionati.removeAll() }
                    Button(L("Save as Profile…", "Salva come profilo…")) { chiediNome = true }
                    Button(L("Preview and Apply", "Anteprima e applica")) {
                        let ordine = Catalogo.ritocchi.map(\.id).filter { stato.selezionati.contains($0) }
                        stato.preparaAnteprima(titolo: L("Selected tweaks", "Ritocchi scelti"), ids: ordine)
                    }.buttonStyle(.borderedProminent)
                }
                .padding(12).background(.bar)
            }
        }
        .alert(L("Profile name", "Nome del profilo"), isPresented: $chiediNome) {
            TextField(L("E.g. Office work", "Es. Lavoro in ufficio"), text: $nomeProfilo)
            Button(L("Save", "Salva")) { stato.salvaProfiloPersonale(nome: nomeProfilo); nomeProfilo = "" }
            Button(L("Cancel", "Annulla"), role: .cancel) { nomeProfilo = "" }
        } message: { Text(L("The profile will contain the \(stato.selezionati.count) selected tweaks.", "Il profilo conterrà i \(stato.selezionati.count) ritocchi scelti.")) }
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
                    if t.serveAdmin { Image(systemName: "lock").foregroundStyle(.secondary).help(L("Asks for the Mac password", "Chiede la password del Mac")) }
                }
                Text(t.spiegazione).font(.callout).foregroundStyle(.secondary)
                if let n = t.nota { Text(n).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if s?.attivo == true { Etichetta(testo: L("Active", "Attivo"), colore: .green) }
                else { Etichetta(testo: L("Now", "Ora") + ": \(s?.testo ?? "…")", colore: .secondary) }
                if let m = modifica {
                    Button(L("Restore", "Ripristina")) { stato.annulla(m) }.controlSize(.small)
                        .help(L("Back to", "Torna a") + ": \(m.originale ?? (m.originaleEnergia.map { String($0) } ?? Catalogo.testoPredefinito))")
                }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Anteprima

struct VistaAnteprima: View {
    @EnvironmentObject var stato: Stato
    var body: some View {
        let voci = stato.anteprima ?? []
        let scelte = voci.filter { $0.scelta }
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Preview", "Anteprima") + ": \(stato.titoloAnteprima)").font(.title2.bold())
            Text(stato.anteprimaPredefinito
                 ? L("Here's what changes. Before applying, Regia saves a copy of the settings.", "Ecco cosa cambia. Prima di applicare Regia salva una copia delle impostazioni.")
                 : L("Here's what changes. Settings already active are excluded. Before applying, Regia saves a copy of the settings.",
                     "Ecco cosa cambia. Quelli già attivi sono esclusi. Prima di applicare Regia salva una copia delle impostazioni."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let a = stato.avvisoAnteprima {
                Label(a, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if stato.modalitaProva {
                Label(L("Test mode is on: you'll see what would happen, without changing anything.", "Modalità prova accesa: vedrai cosa succederebbe, senza cambiare niente."),
                      systemImage: "testtube.2")
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
                Label(L("macOS will ask for the password for energy settings. You type it in its window.",
                        "macOS chiederà la password per le impostazioni di energia. La scrivi tu nella sua finestra."), systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if scelte.contains(where: { $0.ritocco.riavvia != nil }) {
                Label(L("Dock or Finder restart for a moment: open windows stay.", "Dock o Finder si riavviano un attimo: le finestre aperte restano."),
                      systemImage: "arrow.clockwise")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(L("Cancel", "Annulla")) { stato.anteprima = nil }.keyboardShortcut(.cancelAction)
                Button(stato.modalitaProva ? L("Test \(scelte.count) changes", "Prova \(scelte.count) modifiche")
                       : L("Apply \(scelte.count) changes", "Applica \(scelte.count) modifiche")) { stato.applicaAnteprima() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(scelte.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 600, height: 620)
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
            Pagina {
                Titolo(titolo: L("Cleanup", "Pulizia"),
                       sottotitolo: L("Files go to the Trash, they're not deleted: you can recover them if needed.",
                                      "I file vanno nel Cestino, non vengono cancellati: se serve li recuperi."))
                HStack(spacing: 10) {
                    Button { stato.scegliPulizia(accurata: false) } label: {
                        Label(L("Safe Cleanup", "Pulizia sicura"), systemImage: "checkmark.shield")
                    }.help(L("Caches, logs and Xcode files: they're recreated by themselves", "Cache, log e file di Xcode: si ricreano da soli"))
                    Button { stato.scegliPulizia(accurata: true) } label: {
                        Label(L("Deep Cleanup", "Pulizia accurata"), systemImage: "sparkles")
                    }.help(L("Also Xcode iPhone support, simulators and downloads older than 90 days",
                             "Anche supporto iPhone di Xcode, simulatori e download più vecchi di 90 giorni"))
                    Spacer()
                }.controlSize(.large)
                ForEach(stato.zone) { z in
                    Riquadro {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                Toggle("", isOn: Binding(get: { stato.zoneScelte.contains(z.id) },
                                                         set: { if $0 { stato.zoneScelte.insert(z.id) } else { stato.zoneScelte.remove(z.id) } }))
                                    .toggleStyle(.checkbox).labelsHidden().disabled(!z.calcolata || z.elementi.isEmpty)
                                IconaColorata(simbolo: z.icona, colore: .pink, lato: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(z.titolo).fontWeight(.medium)
                                    Text(z.spiegazione).font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if z.calcolata {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(formatoByte(z.dimensione)).font(.title3.bold()).monospacedDigit()
                                        Text(P(z.elementi.count, "item", "items", "elemento", "elementi")).font(.caption).foregroundStyle(.secondary)
                                    }
                                } else if z.suRichiesta {
                                    Button(L("Calculate", "Calcola")) { stato.calcolaZona(z.id) }
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
                                                    .buttonStyle(.borderless).help(L("Show in Finder", "Mostra nel Finder"))
                                            }.font(.callout)
                                        }
                                        if z.elementi.count > 40 {
                                            Text(L("…and \(z.elementi.count - 40) more", "…e altri \(z.elementi.count - 40)")).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.padding(.top, 4)
                                } label: { Text(L("See what's inside", "Vedi cosa contiene")).font(.callout) }
                            }
                        }
                    }
                }
                Riquadro {
                    HStack(spacing: 12) {
                        IconaColorata(simbolo: "trash", colore: .gray, lato: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Empty the Trash", "Svuota il Cestino")).fontWeight(.medium)
                            Text(L("Really frees the space. This time it's permanent.", "Libera davvero lo spazio. Questa volta è definitivo.")).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Empty…", "Svuota…"), role: .destructive) { confermaCestino = true }
                    }
                }
            }
            Divider()
            HStack {
                Text(L("Selected", "Scelto") + ": \(formatoByte(stato.byteScelti))").font(.headline).monospacedDigit()
                Spacer()
                Button(L("Move to Trash…", "Sposta nel Cestino…")) { conferma = true }
                    .buttonStyle(.borderedProminent).disabled(stato.byteScelti == 0)
            }
            .padding(12).background(.bar)
        }
        .confirmationDialog(L("Move \(formatoByte(stato.byteScelti)) to the Trash?", "Spostare \(formatoByte(stato.byteScelti)) nel Cestino?"), isPresented: $conferma) {
            Button(L("Move to Trash", "Sposta nel Cestino")) { stato.pulisci() }
        } message: {
            Text(stato.zone.filter { stato.zoneScelte.contains($0.id) && $0.calcolata }
                .map { "• \($0.titolo): \(formatoByte($0.dimensione))" }.joined(separator: "\n")
                 + "\n\n" + L("It's best to quit the apps you're not using first.", "Conviene chiudere prima le app che non stai usando."))
        }
        .confirmationDialog(L("Empty the Trash?", "Svuotare il Cestino?"), isPresented: $confermaCestino) {
            Button(L("Empty Permanently", "Svuota definitivamente"), role: .destructive) { stato.svuotaCestino() }
        } message: { Text(L("Everything in the Trash will be deleted forever. This can't be undone.", "Tutto quello che c'è nel Cestino verrà eliminato per sempre. Non si può annullare.")) }
    }
}

// MARK: - Avvio

struct VistaAvvio: View {
    @EnvironmentObject var stato: Stato
    @State private var daDisattivare: ElementoAvvio? = nil

    var body: some View {
        Pagina {
            Titolo(titolo: L("Startup", "Avvio"), sottotitolo: L("Programs that start by themselves in the background.", "Programmi che partono da soli in background."))
            ForEach([ElementoAvvio.Livello.utente, .sistemaAgente, .sistemaServizio], id: \.rawValue) { livello in
                let lista = stato.avvio.filter { $0.livello == livello }
                if !lista.isEmpty {
                    Riquadro {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(livello.nome).font(.headline)
                            if livello != .utente {
                                Text(L("Installed for the whole Mac: remove them by uninstalling the app (for example in Installed Apps).",
                                       "Installati per tutto il Mac: si tolgono disinstallando l'app (per esempio da App installate)."))
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
                                        Etichetta(testo: L("Disabled", "Disattivato"), colore: .orange)
                                        Button(L("Enable", "Riattiva")) { stato.riattiva(e) }
                                    } else if livello == .utente {
                                        Button(L("Disable…", "Disattiva…")) { daDisattivare = e }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if stato.avvio.isEmpty {
                Riquadro { Label(L("Nothing starts by itself in the background.", "Niente parte da solo in background."), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            Riquadro {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("App login items", "Elementi di login delle app")).fontWeight(.medium)
                        Text(L("Apps added to startup in System Settings are managed there.", "Le app aggiunte all'avvio da Impostazioni di Sistema si gestiscono lì."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Open", "Apri")) { stato.apri("x-apple.systempreferences:com.apple.LoginItems-Settings.extension") }
                }
            }
        }
        .confirmationDialog(L("Disable", "Disattivare") + " \(nomeLeggibile(daDisattivare?.nome ?? ""))?",
                            isPresented: Binding(get: { daDisattivare != nil }, set: { if !$0 { daDisattivare = nil } })) {
            Button(L("Disable", "Disattiva")) { if let e = daDisattivare { stato.disattiva(e) }; daDisattivare = nil }
        } message: {
            Text(L("It won't start by itself any more. The file is set aside, not deleted: you can re-enable it whenever you want.",
                   "Non partirà più da solo. Il file viene messo da parte, non cancellato: lo riattivi quando vuoi."))
        }
    }

    func nomeLeggibile(_ etichetta: String) -> String {
        let noti = ["com.google.keystone": L("Google updates", "Aggiornamenti Google"), "com.google.GoogleUpdater": L("Google updates", "Aggiornamenti Google"),
                    "com.valvesoftware.steamclean": L("Steam (cleanup)", "Steam (pulizia)"), "com.adobe": "Adobe", "com.microsoft": "Microsoft",
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
        Pagina {
            Titolo(titolo: L("History", "Cronologia"), sottotitolo: L("What Regia changed and how to undo it.", "Cosa ha cambiato Regia e come annullarlo."))
            Riquadro {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Active changes", "Modifiche attive") + " (\(stato.modifiche.count))").font(.headline)
                    if stato.modifiche.isEmpty {
                        Text(L("None: the Mac is as it was before Regia.", "Nessuna: il Mac è com'era prima di Regia.")).foregroundStyle(.secondary)
                    }
                    ForEach(stato.modifiche.reversed()) { m in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stato.titolo(m)).fontWeight(.medium)
                                Text("\(m.data.formatted(date: .abbreviated, time: .shortened)) · " + L("before", "prima") + ": \(prima(m)) · " + L("now", "ora") + ": \(m.nuovo)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L("Undo", "Annulla")) { stato.annulla(m) }
                        }
                    }
                }
            }
            Riquadro {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L("Log", "Registro")).font(.headline)
                        Spacer()
                        Button(L("Open Folder", "Apri cartella")) { stato.mostraNelFinder(stato.motore.cartella) }.controlSize(.small)
                    }
                    if stato.registro.isEmpty { Text(L("Still empty.", "Ancora vuoto.")).foregroundStyle(.secondary) }
                    ForEach(Array(stato.registro.prefix(200).enumerated()), id: \.offset) { _, r in
                        Text(r).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        }
    }

    func prima(_ m: Modifica) -> String {
        switch m.tipo {
        case .preferenza: return m.originale ?? L("default", "predefinito")
        case .energia: return Catalogo.testoEnergia(chiave: m.chiave ?? "", valore: m.originaleEnergia)
        case .avvio: return L("enabled", "attivo")
        case .residuo: return m.percorsoOriginale ?? ""
        }
    }
}
