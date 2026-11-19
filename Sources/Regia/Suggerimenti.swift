import Foundation

/// Un controllo di sicurezza o salute del Mac (sola lettura).
struct Controllo: Identifiable {
    let id: String
    let livello: Consiglio.Livello
    let titolo: String
    let dettaglio: String
    var url: String? = nil
}

/// Una buona abitudine da tenere, con un pulsante facoltativo.
struct Suggerimento: Identifiable {
    var id: String { titolo }
    let icona: String
    let titolo: String
    let dettaglio: String
    var tasti: String? = nil
    var url: String? = nil
}

enum Suggerimenti {
    /// Legge lo stato di FileVault, firewall, Gatekeeper, aggiornamenti automatici e Time Machine. Non cambia niente.
    static func controlli() -> [Controllo] {
        var c: [Controllo] = []
        let sicurezza = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"

        let fv = esegui("/usr/bin/fdesetup", ["status"]).uscita
        if fv.contains("FileVault is On") {
            c.append(Controllo(id: "filevault", livello: .ok, titolo: L("FileVault is on", "FileVault attivo"),
                               dettaglio: L("The disk is encrypted: if the Mac is lost, nobody can read your files.",
                                            "Il disco è cifrato: se perdi il Mac nessuno può leggere i tuoi file.")))
        } else if fv.contains("FileVault is Off") {
            c.append(Controllo(id: "filevault", livello: .attenzione, titolo: L("FileVault is off", "FileVault spento"),
                               dettaglio: L("Turn it on in Privacy & Security: it encrypts the disk with no slowdown on modern Macs.",
                                            "Attivalo in Privacy e sicurezza: cifra il disco senza rallentare i Mac moderni."),
                               url: sicurezza))
        }

        let fw = esegui("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]).uscita
        if fw.contains("enabled") {
            c.append(Controllo(id: "firewall", livello: .ok, titolo: L("Firewall is on", "Firewall attivo"),
                               dettaglio: L("Unwanted incoming connections are blocked.", "Le connessioni in entrata non richieste vengono bloccate.")))
        } else if fw.contains("disabled") {
            c.append(Controllo(id: "firewall", livello: .attenzione, titolo: L("Firewall is off", "Firewall spento"),
                               dettaglio: L("Recommended on public Wi-Fi (cafés, hotels, stations). Turn it on in Network › Firewall.",
                                            "Consigliato sulle Wi-Fi pubbliche (bar, hotel, stazioni). Si attiva in Rete › Firewall."),
                               url: "x-apple.systempreferences:com.apple.Network-Settings.extension"))
        }

        let gk = esegui("/usr/sbin/spctl", ["--status"]).uscita
        if gk.contains("assessments enabled") {
            c.append(Controllo(id: "gatekeeper", livello: .ok, titolo: L("Gatekeeper is on", "Gatekeeper attivo"),
                               dettaglio: L("macOS checks apps downloaded from the internet before opening them.",
                                            "macOS controlla le app scaricate da Internet prima di aprirle.")))
        } else if gk.contains("disabled") {
            c.append(Controllo(id: "gatekeeper", livello: .problema, titolo: L("Gatekeeper is off", "Gatekeeper spento"),
                               dettaglio: L("Any app can open without checks. Turn it back on in Privacy & Security.",
                                            "Qualsiasi app si apre senza controlli. Riattivalo in Privacy e sicurezza."),
                               url: sicurezza))
        }

        // Aggiornamenti automatici: chiave assente = valore di serie di macOS (attivo)
        let su = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.SoftwareUpdate.plist") as? [String: Any]
        func attivo(_ k: String) -> Bool { (su?[k] as? Bool) ?? true }
        let urlSU = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
        if !attivo("AutomaticCheckEnabled") {
            c.append(Controllo(id: "aggiornamenti", livello: .problema, titolo: L("Automatic update checks are off", "Controllo automatico degli aggiornamenti spento"),
                               dettaglio: L("macOS doesn't look for security fixes by itself.", "macOS non cerca da solo le correzioni di sicurezza."),
                               url: urlSU))
        } else if !attivo("CriticalUpdateInstall") || !attivo("ConfigDataInstall") {
            c.append(Controllo(id: "aggiornamenti", livello: .attenzione, titolo: L("Security responses are off", "Risposte di sicurezza spente"),
                               dettaglio: L("Turn on \"Install Security Responses and system files\" in Software Update › Automatic Updates.",
                                            "Attiva \"Installa risposte di sicurezza e file di sistema\" in Aggiornamento Software › Aggiornamenti automatici."),
                               url: urlSU))
        } else {
            c.append(Controllo(id: "aggiornamenti", livello: .ok, titolo: L("Automatic updates are on", "Aggiornamenti automatici attivi"),
                               dettaglio: L("macOS checks for updates and installs security fixes by itself.",
                                            "macOS controlla gli aggiornamenti e installa da solo le correzioni di sicurezza.")))
        }

        let tm = esegui("/usr/bin/tmutil", ["destinationinfo"])
        let tmTesto = tm.uscita + tm.errore
        if tmTesto.contains("No destinations configured") {
            c.append(Controllo(id: "backup", livello: .attenzione, titolo: L("No Time Machine backup", "Nessun backup Time Machine"),
                               dettaglio: L("If the disk breaks you lose everything that's not on iCloud. An external disk is enough.",
                                            "Se il disco si guasta perdi tutto quello che non è su iCloud. Basta un disco esterno."),
                               url: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"))
        } else if tm.ok && tmTesto.contains("Name") {
            c.append(Controllo(id: "backup", livello: .ok, titolo: L("Time Machine is set up", "Time Machine configurato"),
                               dettaglio: L("Remember to connect the backup disk from time to time.", "Ricordati di collegare ogni tanto il disco di backup.")))
        }
        return c
    }

    /// Buone abitudini per un Mac veloce ed efficiente (fonti: guide di Apple e riviste specializzate).
    static var abitudini: [Suggerimento] {
        [
            Suggerimento(icona: "restart", titolo: L("Restart about once a week", "Riavvia circa una volta a settimana"),
                         dettaglio: L("Sleep is fine every day, but a restart frees memory and completes updates.",
                                      "Lo stop va bene tutti i giorni, ma un riavvio libera memoria e completa gli aggiornamenti.")),
            Suggerimento(icona: "xmark.app", titolo: L("Quit apps, don't just close windows", "Chiudi le app, non solo le finestre"),
                         dettaglio: L("The red button closes the window but the app keeps running. Quit it with ⌘Q.",
                                      "Il pallino rosso chiude la finestra ma l'app resta aperta. Chiudila con ⌘Q."), tasti: "⌘Q"),
            Suggerimento(icona: "exclamationmark.octagon", titolo: L("Force quit a frozen app", "Uscita forzata di un'app bloccata"),
                         dettaglio: L("Press ⌥⌘Esc, choose the app and click Force Quit.", "Premi ⌥⌘Esc, scegli l'app e premi Uscita forzata."), tasti: "⌥⌘⎋"),
            Suggerimento(icona: "chart.bar.xaxis", titolo: L("Find what slows the Mac down", "Trova cosa rallenta il Mac"),
                         dettaglio: L("Activity Monitor shows which apps use the most CPU, memory and energy.",
                                      "Monitoraggio Attività mostra quali app usano più CPU, memoria ed energia."),
                         url: "file:///System/Applications/Utilities/Activity%20Monitor.app"),
            Suggerimento(icona: "internaldrive", titolo: L("Keep at least 15–20% of the disk free", "Tieni libero almeno il 15–20% del disco"),
                         dettaglio: L("macOS needs space for memory swap and updates: with a full disk everything slows down.",
                                      "macOS usa lo spazio per la memoria virtuale e gli aggiornamenti: col disco pieno tutto rallenta.")),
            Suggerimento(icona: "safari", titolo: L("Fewer open browser tabs", "Meno schede aperte nel browser"),
                         dettaglio: L("Every tab uses memory and energy. Bookmark what you need to read later.",
                                      "Ogni scheda usa memoria ed energia. Metti nei preferiti quello che leggerai dopo.")),
            Suggerimento(icona: "arrow.down.circle", titolo: L("Keep apps up to date", "Tieni aggiornate le app"),
                         dettaglio: L("Updates fix bugs and security issues and often improve speed. Check them in App Updates.",
                                      "Gli aggiornamenti correggono errori e falle di sicurezza e spesso migliorano la velocità. Controllali in Aggiornamenti app.")),
            Suggerimento(icona: "battery.100percent.bolt", titolo: L("Optimised battery charging", "Caricamento ottimizzato"),
                         dettaglio: L("If the Mac is often plugged in, keep optimised charging on: the battery lasts more years.",
                                      "Se il Mac è spesso in carica, lascia attivo il caricamento ottimizzato: la batteria dura più anni."),
                         url: "x-apple.systempreferences:com.apple.Battery-Settings.extension"),
            Suggerimento(icona: "magnifyingglass", titolo: L("Open everything with Spotlight", "Apri tutto con Spotlight"),
                         dettaglio: L("⌘Space, type the first letters and press Return: faster than looking in the Finder.",
                                      "⌘Spazio, scrivi le prime lettere e premi Invio: più veloce che cercare nel Finder."), tasti: "⌘␣"),
            Suggerimento(icona: "lock.shield", titolo: L("Install apps only from trusted sources", "Installa app solo da fonti affidabili"),
                         dettaglio: L("App Store or the developer's official site. Avoid \"cleaners\" and antivirus apps that promise miracles.",
                                      "App Store o sito ufficiale dello sviluppatore. Evita \"pulitori\" e antivirus che promettono miracoli.")),
        ]
    }
}
