# Regia per Mac

**Italiano** · [English](#english)

Programma gratuito per **macOS 14 o successivo** (Apple Silicon e Intel) che analizza il Mac e lo ottimizza in modo sicuro. È la versione Mac di [Regia per Windows](https://github.com/sm-bc/regia).

## Cosa fa
- **Panoramica** con dati in tempo reale: processore, memoria, rete, disco, batteria, temperatura. Più consigli sullo stato del Mac.
- **Profili**: Massimo, Bilanciato, Sicuro, Produttività, Grafica e design, Gaming, Efficienza. Puoi anche salvare i tuoi profili.
- **Ritocchi** singoli per Dock, Finder, tastiera, screenshot, energia e privacy.
- **Pulizia** di cache, log e file di Xcode. I file vanno nel Cestino, quindi si possono recuperare.
- **Residui** di app cancellate e **App installate** con "Disinstalla e pulisci".
- **Avvio**: i programmi che partono da soli.
- **Manutenzione**: disco, batteria, aggiornamenti di macOS, latenza e velocità della rete, cache DNS, Spotlight.

## Perché è sicuro
- La **Modalità prova** è accesa a ogni apertura: vedi tutto in anteprima, ma non cambia niente.
- Prima di ogni modifica: anteprima "ora → dopo", conferma e copia delle impostazioni.
- **Annulla tutto** rimette i valori di prima.
- Non tocca i file di sistema protetti di macOS. Non invia dati a nessuno: si collega a Internet solo per cercare gli aggiornamenti di Regia e quando lanci un test di rete.

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

---

<a name="english"></a>
# Regia for Mac (English)

Free tool for **macOS 14 or later** (Apple Silicon and Intel) that analyzes the Mac and optimizes it safely. It is the Mac version of [Regia for Windows](https://github.com/sm-bc/regia). The interface is in Italian.

- **Dry-run mode** is on at every launch. Every change shows a preview first, backs up the original values and can be reverted with **Undo all**.
- Profiles, single tweaks, cleanup to the Trash, leftovers of deleted apps, uninstaller, startup items, maintenance tools and live system data.
- **Install:** download `Regia-Mac_x.y.zip` from [Releases](https://github.com/sm-bc/regia-mac/releases/latest) and drag Regia to Applications. On first launch, go to System Settings › Privacy & Security and click **Open Anyway**: the app is not signed with a paid Apple certificate.
- **Updates:** an **Update** button appears when a new version is out. The package is checked by SHA-256 fingerprint, bundle identifier, version and code signature before it replaces the app.

## License
MIT.
