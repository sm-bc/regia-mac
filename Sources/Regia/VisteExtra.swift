import SwiftUI
import AppKit

// MARK: - Suggerimenti

struct VistaSuggerimenti: View {
    @EnvironmentObject var stato: Stato
    @State private var confermaRiavvio = false

    var body: some View {
        Pagina {
            Titolo(titolo: L("Tips", "Suggerimenti"),
                   sottotitolo: L("Security checks, settings worth changing by hand and good habits for a fast Mac.",
                                  "Controlli di sicurezza, impostazioni da cambiare a mano e buone abitudini per un Mac veloce."))
            Riquadro {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L("Security and protection", "Sicurezza e protezione"), systemImage: "lock.shield").font(.headline)
                    if stato.controlli.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                    ForEach(stato.controlli) { c in
                        HStack(spacing: 10) {
                            SimboloLivello(livello: c.livello)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.titolo).fontWeight(.medium)
                                Text(c.dettaglio).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if let u = c.url, c.livello != .ok { Button(L("Open", "Apri")) { stato.apri(u) }.controlSize(.small) }
                        }
                        if c.id != stato.controlli.last?.id { Divider() }
                    }
                }
            }
            Riquadro {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L("Worth changing by hand", "Da cambiare a mano"), systemImage: "hand.tap").font(.headline)
                    Text(L("macOS doesn't let apps change these settings: the button opens the right page in System Settings.",
                           "macOS non lascia cambiare queste impostazioni da un'app: il pulsante apre la pagina giusta di Impostazioni di Sistema."))
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(Catalogo.consigliManuali) { c in
                        HStack(spacing: 12) {
                            IconaColorata(simbolo: c.icona, colore: .gray, lato: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.titolo).fontWeight(.medium)
                                Text(c.spiegazione).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L("Open", "Apri")) { stato.apri(c.url) }
                        }
                    }
                }
            }
            Riquadro {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L("Good habits", "Buone abitudini"), systemImage: "lightbulb").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .topLeading)], alignment: .leading, spacing: 14) {
                        ForEach(Suggerimenti.abitudini) { s in
                            HStack(alignment: .top, spacing: 10) {
                                IconaColorata(simbolo: s.icona, colore: .yellow, lato: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(s.titolo).fontWeight(.medium)
                                        if let t = s.tasti {
                                            Text(t).font(.caption.monospaced().weight(.semibold))
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.5)))
                                        }
                                    }
                                    Text(s.dettaglio).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    if let u = s.url {
                                        Button(L("Open", "Apri")) { stato.apri(u) }.controlSize(.small).padding(.top, 2)
                                    } else if s.icona == "restart" {
                                        Button(L("Restart…", "Riavvia…")) { confermaRiavvio = true }.controlSize(.small).padding(.top, 2)
                                    } else if s.icona == "arrow.down.circle" {
                                        Button(L("App Updates", "Aggiornamenti app")) { stato.sezione = .aggiornamentiApp }.controlSize(.small).padding(.top, 2)
                                    }
                                }
                            }
                            // Ogni consiglio occupa tutta la cella, allineato a sinistra (prima era centrato e sfalsato).
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }
        }
        .confirmationDialog(L("Restart the Mac?", "Riavviare il Mac?"), isPresented: $confermaRiavvio) {
            Button(L("Restart", "Riavvia")) { stato.riavviaMac() }
        } message: { Text(L("Apps will ask you to save open documents.", "Le app chiederanno di salvare i documenti aperti.")) }
    }
}

// MARK: - Aggiornamenti delle app

struct VistaAggiornamentiApp: View {
    @EnvironmentObject var stato: Stato
    @State private var mostraAggiornate = false
    @State private var mostraAutomatiche = false
    @State private var mostraSconosciute = false

    var body: some View {
        Pagina {
            HStack(alignment: .top) {
                Titolo(titolo: L("App Updates", "Aggiornamenti app"),
                       sottotitolo: L("Checks App Store apps, apps from developers' websites and Homebrew. Nothing is installed without you.",
                                      "Controlla le app dell'App Store, quelle scaricate dai siti degli sviluppatori e Homebrew. Non si installa niente senza di te."))
                if stato.cercandoAggiornamentiApp {
                    ProgressView().controlSize(.small).padding(.top, 10)
                } else {
                    Button { stato.controllaAggiornamentiApp() } label: { Label(L("Check Now", "Controlla ora"), systemImage: "arrow.clockwise") }
                        .controlSize(.large)
                }
            }
            if let r = stato.aggiornamentiApp {
                let disp = r.disponibili
                Riquadro {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(disp.isEmpty ? L("Everything is up to date", "Tutto aggiornato") : P(disp.count, "update available", "updates available", "aggiornamento disponibile", "aggiornamenti disponibili"),
                                  systemImage: disp.isEmpty ? "checkmark.seal.fill" : "arrow.down.circle.fill")
                                .font(.headline).foregroundStyle(disp.isEmpty ? .green : .accentColor)
                            Spacer()
                            Text(L("Checked at", "Controllato alle") + " " + r.data.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            if disp.contains(where: { if case .appStore = $0.fonte { return true }; return false }) {
                                Button(L("Open App Store Updates", "Apri aggiornamenti App Store")) { stato.apri("macappstore://showUpdatesPage") }.controlSize(.small)
                            }
                        }
                        ForEach(disp) { v in
                            RigaAggiornamento(v: v)
                            if v.id != disp.last?.id { Divider() }
                        }
                    }
                }
                gruppo(L("Up to date", "Aggiornate"), icona: "checkmark.circle", voci: r.voci.filter { $0.esito == .aggiornata }, aperto: $mostraAggiornate)
                gruppo(L("Update themselves", "Si aggiornano da sole"), icona: "arrow.triangle.2.circlepath",
                       voci: r.voci.filter { $0.esito == .nonVerificabile && $0.fonte == .automatica }, aperto: $mostraAutomatiche)
                gruppo(L("Can't be checked automatically", "Non controllabili in automatico"), icona: "questionmark.circle",
                       voci: r.voci.filter { $0.esito == .nonVerificabile && $0.fonte != .automatica }, aperto: $mostraSconosciute)
            } else if stato.cercandoAggiornamentiApp {
                Riquadro { ProgressView(L("Checking your apps…", "Controllo le app…")).frame(maxWidth: .infinity).padding() }
            }
            Riquadro {
                HStack(spacing: 12) {
                    IconaColorata(simbolo: "apple.logo", colore: .gray, lato: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS").fontWeight(.medium)
                        Text(L("System updates are installed from System Settings › General › Software Update.",
                               "Gli aggiornamenti di sistema si installano da Impostazioni di Sistema › Generali › Aggiornamento Software."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let s = Manutenzione.strumenti.first(where: { $0.id == "macos.aggiornamenti" }) {
                        if stato.inCorso == s.id { ProgressView().controlSize(.small) }
                        else { Button(L("Check", "Controlla")) { stato.avviaStrumento(s) }.disabled(stato.inCorso != nil) }
                    }
                    Button(L("Open", "Apri")) { stato.apri("x-apple.systempreferences:com.apple.Software-Update-Settings.extension") }
                }
            }
            Text(L("How it works: for App Store apps Regia asks Apple's public catalogue; for other apps it reads the update feed the developer publishes (Sparkle). The \"Update\" button opens the App Store, the app itself or Terminal (Homebrew): you always confirm there.",
                   "Come funziona: per le app dell'App Store Regia chiede al catalogo pubblico di Apple; per le altre legge il feed di aggiornamento pubblicato dallo sviluppatore (Sparkle). Il pulsante \"Aggiorna\" apre l'App Store, l'app stessa o il Terminale (Homebrew): confermi sempre tu lì."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { if stato.aggiornamentiApp == nil { stato.controllaAggiornamentiApp() } }
    }

    @ViewBuilder
    func gruppo(_ titolo: String, icona: String, voci: [AppAggiornabile], aperto: Binding<Bool>) -> some View {
        if !voci.isEmpty {
            Riquadro {
                DisclosureGroup(isExpanded: aperto) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(voci) { v in RigaAggiornamento(v: v) }
                    }.padding(.top, 8)
                } label: {
                    Label("\(titolo) (\(voci.count))", systemImage: icona).font(.headline)
                }
            }
        }
    }
}

struct RigaAggiornamento: View {
    @EnvironmentObject var stato: Stato
    let v: AppAggiornabile
    var body: some View {
        HStack(spacing: 10) {
            if let p = v.percorso {
                Image(nsImage: NSWorkspace.shared.icon(forFile: p.path)).resizable().frame(width: 30, height: 30)
            } else {
                IconaColorata(simbolo: "terminal", colore: .brown, lato: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(v.nome).fontWeight(.medium)
                    Etichetta(testo: v.nomeFonte, colore: v.esito == .disponibile ? .blue : .secondary)
                }
                Group {
                    if let n = v.nuova { Text("\(v.versione.isEmpty ? "?" : v.versione) → ") + Text(n).bold().foregroundColor(.accentColor) }
                    else { Text(v.versione.isEmpty ? "" : "v\(v.versione)") }
                }
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                if let n = v.nota { Text(n).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if v.esito == .disponibile {
                Button(L("Update", "Aggiorna")) { stato.aggiorna(v) }.buttonStyle(.borderedProminent).controlSize(.small)
            } else if let pagina = v.pagina, case .appStore = v.fonte {
                Button(L("App Store", "App Store")) { NSWorkspace.shared.open(pagina) }.controlSize(.small)
            }
        }
    }
}

// MARK: - Segnalazioni e idee

struct VistaFeedback: View {
    @EnvironmentObject var stato: Stato
    @Environment(\.dismiss) private var chiudi
    @State private var tipo: Feedback.Tipo = .problema
    @State private var titolo = ""
    @State private var testo = ""
    @State private var includiSistema = true
    @State private var includiRegistro = false
    @State private var copiato = false

    var corpo: String {
        Feedback.corpo(tipo: tipo, testo: testo,
                       info: includiSistema ? Feedback.infoSistema(stato.panoramica) : nil,
                       registro: includiRegistro ? Feedback.registroAnonimo(stato.registro) : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconaColorata(simbolo: "bubble.left.and.exclamationmark.bubble.right", colore: .blue, lato: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Send Feedback", "Invia una segnalazione")).font(.title2.bold())
                    Text(L("Report a problem or suggest an idea to improve Regia.", "Segnala un problema o proponi un'idea per migliorare Regia."))
                        .foregroundStyle(.secondary)
                }
            }
            Picker("", selection: $tipo) {
                ForEach(Feedback.Tipo.allCases) { t in Label(t.nome, systemImage: t.icona).tag(t) }
            }
            .pickerStyle(.segmented).labelsHidden()
            TextField(L("Title (e.g. Cleanup doesn't find caches)", "Titolo (es. La pulizia non trova le cache)"), text: $titolo)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 4) {
                Text(tipo == .problema ? L("What happened? What did you expect instead?", "Cosa è successo? Cosa ti aspettavi invece?")
                     : L("Describe your idea or question", "Descrivi la tua idea o domanda"))
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $testo)
                    .font(.body)
                    .frame(minHeight: 130)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            }
            Toggle(L("Include technical info (Regia and macOS version, Mac model)", "Includi info tecniche (versione di Regia e macOS, modello del Mac)"), isOn: $includiSistema)
            Toggle(L("Include the last lines of Regia's log (your user name is hidden)", "Includi le ultime righe del registro di Regia (il nome utente è nascosto)"), isOn: $includiRegistro)
            DisclosureGroup(L("See exactly what will be sent", "Vedi esattamente cosa verrà inviato")) {
                ScrollView {
                    Text(corpo).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 110)
            }
            Label(L("Regia opens the project's page on GitHub with everything filled in: you need a free GitHub account, and nothing is sent until you press \"Create\" there.",
                    "Regia apre la pagina del progetto su GitHub con tutto già compilato: serve un account GitHub gratuito e non si invia niente finché non premi \"Create\" lì."),
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { NSWorkspace.shared.open(URL(string: Feedback.progetto + "/issues")!) } label: { Text(L("See existing reports", "Vedi le segnalazioni")) }
                    .buttonStyle(.link)
                Spacer()
                Button(copiato ? L("Copied", "Copiato") : L("Copy Text", "Copia testo")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(tipo.prefisso) \(titolo)\n\n\(corpo)", forType: .string)
                    copiato = true
                }
                Button(L("Cancel", "Annulla")) { chiudi() }.keyboardShortcut(.cancelAction)
                Button(L("Continue on GitHub", "Continua su GitHub")) {
                    if let u = Feedback.url(tipo: tipo, titolo: titolo, corpo: corpo) { NSWorkspace.shared.open(u) }
                    stato.motore.scriviRegistro(L("Feedback page opened on GitHub", "Aperta la pagina delle segnalazioni su GitHub") + " (\(tipo.prefisso))")
                    chiudi()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 600)
    }
}

// MARK: - Impostazioni (⌘,)

struct VistaImpostazioni: View {
    @EnvironmentObject var stato: Stato
    var body: some View {
        Form {
            Section {
                Picker(L("Language", "Lingua"), selection: Binding(get: { stato.lingua }, set: { stato.cambiaLingua($0) })) {
                    ForEach(Lingua.allCases) { l in Text(l.nome).tag(l) }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(L("The whole interface changes immediately.", "Tutta l'interfaccia cambia subito.")).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent(L("Version", "Versione"), value: Aggiornamenti.versioneAttuale)
                HStack {
                    Button(L("Check for Updates", "Cerca aggiornamenti")) { stato.cercaAggiornamenti(silenzioso: false) }
                    Button(L("Send Feedback…", "Invia una segnalazione…")) { stato.mostraFeedback = true; NSApp.windows.first { $0.isKeyWindow }?.close() }
                    Button(L("Project on GitHub", "Progetto su GitHub")) { stato.apri(Feedback.progetto) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 300)
        .id(stato.lingua)
    }
}
