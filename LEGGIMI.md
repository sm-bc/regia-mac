# Regia per Mac

App per ottimizzare il Mac, sorella di Regia per Windows. SwiftUI, nessuna dipendenza esterna.

## Cosa fa
- **Panoramica** (solo lettura): disco, memoria, batteria, da quanto è acceso, programmi più pesanti, consigli.
- **Profili**: Produttività, Grafica e design, Gaming, Efficienza. Sempre con anteprima "ora → dopo".
- **Ritocchi**: 29 impostazioni singole (Dock, Finder, tastiera, screenshot, energia, privacy) + link alle impostazioni da fare a mano.
- **Pulizia**: cache, log, DerivedData di Xcode, download vecchi → **nel Cestino** (recuperabili). Svuota Cestino a parte, con conferma.
- **Avvio**: programmi che partono da soli; quelli del tuo account si disattivano e riattivano.
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
open --env REGIA_PROVA=1 Regia.app            # app in modalità prova: il Mac vero non viene toccato
```

## File
- `Sources/Regia/Catalogo.swift` — ritocchi e profili (per aggiungerne uno basta una voce qui)
- `Sources/Regia/Motore.swift` — applica, salva, annulla
- `Sources/Regia/Analisi.swift` — panoramica e pulizia
- `Sources/Regia/Stato.swift`, `Viste.swift` — interfaccia
- `Sources/Regia/main.swift` — avvio, `--analisi`, `--autotest`
