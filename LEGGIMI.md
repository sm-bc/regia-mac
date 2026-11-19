# Regia per Mac

App per ottimizzare il Mac, sorella di Regia per Windows. SwiftUI, nessuna dipendenza esterna.

## Cosa fa (versione 2.0, allineata a Regia Windows 3.9)
- **Modalità prova** (interruttore in basso a sinistra, accesa a ogni apertura): mostra cosa farebbe, non cambia niente.
- **Panoramica**: dati in tempo reale (processore, memoria, rete, disco, batteria e consumo, stato termico), disco, batteria, consigli.
- **Profili**: Massimo, Bilanciato, Sicuro, Produttività, Grafica e design, Gaming, Efficienza + **profili personali** (Ritocchi › "Salva come profilo") + **Riporta al predefinito**. Sempre con anteprima "ora → dopo".
- **Ritocchi**: 29 impostazioni singole + link alle impostazioni da fare a mano.
- **Pulizia**: pulsanti *Pulizia sicura* (cache, log, Xcode) e *Pulizia accurata* (anche supporto iPhone, simulatori, download vecchi) → **nel Cestino**.
- **Residui**: file di app cancellate e avvii automatici rotti → messi da parte in una cartella di Regia, si rimettono con Annulla.
- **App installate**: "Disinstalla e pulisci" sposta nel Cestino l'app e i file che lascia in Libreria; avvisa se l'app ha un suo disinstallatore.
- **Avvio**: programmi che partono da soli; quelli del tuo account si disattivano e riattivano.
- **Manutenzione**: salute e verifica del disco, report batteria, aggiornamenti macOS, latenza (ping router/DNS), test della connessione, cache DNS, libera memoria, menu "Apri con", riavvio Dock/Finder, indice Spotlight.
- **Riavvio**: pulsante "Riavvia il Mac" e avviso quando una modifica lo richiede.
- **Cronologia** e **Annulla tutto**: ogni modifica salva il valore di prima.

## Sicurezza (come il punto di ripristino su Windows)
- Prima di ogni modifica: copia completa delle impostazioni toccate in
  `~/Library/Application Support/Regia/Backup/<data>/`.
- `modifiche.json` ricorda i valori originali → "Annulla" e "Annulla tutto".
- `registro.txt`: tutto quello che è stato fatto.
- Le impostazioni energia (🔒) chiedono la password nella finestra di macOS.

## Comandi
```bash
./crea-app.sh              # compila e crea Regia.app qui
./crea-app.sh --installa   # ...e la copia in /Applications
./Regia.app/Contents/MacOS/Regia --analisi    # stato del Mac nel Terminale, non cambia niente
./Regia.app/Contents/MacOS/Regia --autotest   # prova tutto in un'area finta
open --env REGIA_PROVA=1 Regia.app            # simulazione su dati finti (per provare lo sviluppo)
```

## File
- `Sources/Regia/Catalogo.swift` — ritocchi e profili (per aggiungerne uno basta una voce qui)
- `Sources/Regia/Motore.swift` — applica, salva, annulla
- `Sources/Regia/Analisi.swift` — panoramica e pulizia
- `Sources/Regia/AppEResidui.swift` — app installate e residui
- `Sources/Regia/Manutenzione.swift` — strumenti, latenza, riavvio
- `Sources/Regia/TempoReale.swift` — dati in tempo reale
- `Sources/Regia/Stato.swift`, `Viste.swift`, `VisteNuove.swift` — interfaccia
- `Sources/Regia/main.swift` — avvio, `--analisi`, `--autotest`
