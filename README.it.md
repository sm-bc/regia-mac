# Regia per Mac

[English](README.md) · **Italiano**

Programma gratuito per **macOS 14 o successivo** (Apple Silicon e Intel) che analizza il Mac e lo ottimizza in modo sicuro. È la versione Mac di [Regia per Windows](https://github.com/sm-bc/regia).

## Cosa fa
- **Interfaccia in inglese o italiano**: si sceglie in basso a sinistra, nel menu Lingua o in Impostazioni (⌘,).
- **Panoramica** con dati in tempo reale: processore, memoria, rete, disco, batteria, temperatura. Più consigli con pulsanti per risolvere e l'invito a **riavviare** se il Mac è acceso da diversi giorni.
- **Suggerimenti**: controlli di sicurezza (FileVault, firewall, Gatekeeper, aggiornamenti automatici, Time Machine), impostazioni da cambiare a mano e buone abitudini.
- **Profili**: Massimo, Bilanciato, Sicuro. Puoi anche salvare i tuoi profili.
- **Ritocchi** singoli (37) per velocità, Dock, Finder, efficienza, tastiera, screenshot, energia e privacy.
- **Aggiornamenti app**: controlla le app dell'App Store, quelle scaricate dai siti degli sviluppatori (Sparkle) e Homebrew.
- **Pulizia** di cache, log e file di Xcode. I file vanno nel Cestino, quindi si possono recuperare.
- **Residui** di app cancellate e **App installate** con "Disinstalla e pulisci".
- **Avvio**: i programmi che partono da soli.
- **Manutenzione**: disco, batteria, aggiornamenti di macOS, latenza e velocità della rete, cache DNS, Spotlight.
- **Segnalazioni**: "Segnala" in basso a sinistra prepara una segnalazione o un'idea e apre la pagina di GitHub (invii tu).

## Perché è sicuro
- La **Modalità prova** è accesa a ogni apertura: vedi tutto in anteprima, ma non cambia niente.
- Prima di ogni modifica: anteprima "ora → dopo", conferma e copia delle impostazioni.
- **Annulla tutto** rimette i valori di prima.
- Non tocca i file di sistema protetti di macOS. Non invia dati personali: si collega a Internet solo per cercare gli aggiornamenti (di Regia e delle app: catalogo pubblico dell'App Store e siti degli sviluppatori) e quando lanci un test di rete.

## Installazione
1. Apri la pagina **[Releases](https://github.com/sm-bc/regia-mac/releases/latest)** e scarica `Regia-Mac_x.y.zip`.
2. Apri lo zip e trascina **Regia** in **Applicazioni**.
3. La prima volta macOS dice che non può verificare lo sviluppatore: Regia non è firmata con un certificato Apple a pagamento. Apri **Impostazioni di Sistema › Privacy e sicurezza** e premi **Apri comunque**.

## Aggiornamenti
All'avvio Regia controlla se c'è una versione nuova. Se c'è, compare il pulsante **Aggiorna** in basso a sinistra. Prima di installare chiede conferma e controlla:
- l'impronta SHA-256 del pacchetto;
- l'identificativo dell'app;
- il numero di versione;
- la firma.

La versione precedente viene salvata in `~/Library/Application Support/Regia/Versioni`.

## Compilare da soli
```bash
./crea-app.sh              # crea Regia.app
./crea-app.sh --installa   # ...e la copia in /Applications
./Regia.app/Contents/MacOS/Regia --autotest   # prova tutto su dati finti
```

## Avvertenze
Cambiare le impostazioni di sistema comporta sempre un minimo di rischio. Usa la Modalità prova e leggi le anteprime. Il programma è fornito "così com'è", senza garanzie (vedi `LICENSE`).

## Licenza
MIT (vedi `LICENSE`).
