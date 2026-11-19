# Regia per Mac

App per ottimizzare il Mac, sorella di Regia per Windows. SwiftUI, nessuna dipendenza esterna.

## Cosa fa (versione 2.3)
- **Lingua**: inglese di serie, italiano selezionabile (barra laterale in basso, menu Lingua, Impostazioni ⌘,). Testi nel codice con `L("inglese", "italiano")`.
- **Modalità prova** (interruttore in basso a sinistra, accesa a ogni apertura): mostra cosa farebbe, non cambia niente.
- **Panoramica**: dati in tempo reale (processore, memoria, rete, disco, batteria e consumo, stato termico), disco, batteria, consigli.
- **Suggerimenti**: controlli di sicurezza in sola lettura (FileVault, firewall, Gatekeeper, aggiornamenti automatici, Time Machine), impostazioni da fare a mano, buone abitudini.
- **Profili**: Massimo, Bilanciato, Sicuro + **profili personali** (Ritocchi › "Salva come profilo") + **Riporta al predefinito**. Sempre con anteprima "ora → dopo".
- **Ritocchi**: 37 impostazioni singole.
- **Pulizia**: pulsanti *Pulizia sicura* (cache, log, Xcode) e *Pulizia accurata* (anche supporto iPhone, simulatori, download vecchi) → **nel Cestino**.
- **Residui**: file di app cancellate e avvii automatici rotti → messi da parte in una cartella di Regia, si rimettono con Annulla.
- **App installate**: "Disinstalla e pulisci" sposta nel Cestino l'app e i file che lascia in Libreria; avvisa se l'app ha un suo disinstallatore.
- **Avvio**: programmi che partono da soli; quelli del tuo account si disattivano e riattivano.
- **Manutenzione**: salute e verifica del disco, report batteria, aggiornamenti macOS, latenza (ping router/DNS), test della connessione, cache DNS, libera memoria, menu "Apri con", riavvio Dock/Finder, indice Spotlight.
- **Aggiornamenti app**: App Store (catalogo pubblico Apple), feed Sparkle degli sviluppatori, Homebrew. Il pulsante Aggiorna apre App Store / app / Terminale.
- **Riavvio**: pulsante "Riavvia", avviso quando una modifica lo richiede e dopo la scansione se il Mac è acceso da 3 giorni o più.
- **Segnala**: prepara una segnalazione e apre la pagina "New issue" di GitHub (non invia niente da sola).
- **Cronologia** e **Annulla tutto**: ogni modifica salva il valore di prima.

## Sicurezza (come il punto di ripristino su Windows)
- Prima di ogni modifica: copia completa delle impostazioni toccate in
  `~/Library/Application Support/Regia/Backup/<data>/`.
- `modifiche.json` ricorda i valori originali → "Annulla" e "Annulla tutto".
- `registro.txt`: tutto quello che è stato fatto.
- Le impostazioni energia (🔒) chiedono la password nella finestra di macOS.

## Pubblicare una versione nuova su GitHub
1. Fai le modifiche e prova con `./Regia.app/Contents/MacOS/Regia --autotest`.
2. Aumenta il numero nel file `VERSIONE` (es. 2.1 → 2.2) e fai il commit.
3. `./pubblica.sh "Cosa c'è di nuovo, in una riga"`

Lo script compila e prova l'app, crea la Release con lo zip, controlla lo zip online e solo alla fine
aggiorna `versione.json`. Le copie installate mostrano "Aggiorna alla x.y" in basso a sinistra.
Repository: https://github.com/sm-bc/regia-mac (pubblico: chiunque può scaricare).
Sicurezza: chi controlla l'account GitHub può pubblicare aggiornamenti → tieni attiva la verifica in due passaggi.

## Comandi
```bash
./crea-app.sh              # compila e crea Regia.app qui (Apple Silicon + Intel)
./crea-app.sh --installa   # ...e la copia in /Applications
./Regia.app/Contents/MacOS/Regia --analisi    # stato del Mac nel Terminale, non cambia niente
./Regia.app/Contents/MacOS/Regia --autotest   # prova tutto in un'area finta
./Regia.app/Contents/MacOS/Regia --aggiornamenti-app   # elenco aggiornamenti delle app, non installa niente
open --env REGIA_PROVA=1 Regia.app            # simulazione su dati finti (per provare lo sviluppo)
```

## File
- `Sources/Regia/Catalogo.swift` — ritocchi e profili (per aggiungerne uno basta una voce qui)
- `Sources/Regia/Motore.swift` — applica, salva, annulla
- `Sources/Regia/Analisi.swift` — panoramica e pulizia
- `Sources/Regia/AppEResidui.swift` — app installate e residui
- `Sources/Regia/Manutenzione.swift` — strumenti, latenza, riavvio
- `Sources/Regia/TempoReale.swift` — dati in tempo reale
- `Sources/Regia/Lingua.swift` — inglese/italiano
- `Sources/Regia/Suggerimenti.swift` — controlli di sicurezza e buone abitudini
- `Sources/Regia/AggiornamentiApp.swift` — aggiornamenti delle app (App Store, Sparkle, Homebrew)
- `Sources/Regia/Feedback.swift` — segnalazioni su GitHub
- `Sources/Regia/Stato.swift`, `Viste.swift`, `VisteNuove.swift`, `VisteExtra.swift` — interfaccia
- `Sources/Regia/Aggiornamenti.swift` — controllo e installazione degli aggiornamenti da GitHub
- `Sources/Regia/main.swift` — avvio, `--analisi`, `--autotest`
- `pubblica.sh` — pubblica una versione su GitHub
