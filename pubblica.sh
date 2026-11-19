#!/bin/zsh
# ==========================================================================
#  Pubblica una nuova versione di Regia Mac su GitHub.
#  Uso:   ./pubblica.sh "Cosa c'è di nuovo, in una riga"
#  Prima: aumenta il numero nel file VERSIONE (es. 2.1 -> 2.2) e fai il commit.
#
#  Cosa fa: compila, lancia l'autotest, crea lo zip, crea la Release su GitHub
#  con lo zip allegato, controlla che lo zip online abbia la stessa impronta
#  SHA-256 e SOLO ALLA FINE aggiorna versione.json (così le copie installate
#  vedono il pulsante "Aggiorna" quando lo zip è già scaricabile).
#  La prima volta crea anche il repository pubblico sm-bc/regia-mac.
# ==========================================================================
set -e
cd "$(dirname "$0")"
UTENTE="sm-bc"
REPO="regia-mac"
NOTE="$1"
V="$(cat VERSIONE)"
ZIP="Distribuzione/Regia-Mac_$V.zip"
URL="https://github.com/$UTENTE/$REPO/releases/download/v$V/Regia-Mac_$V.zip"

ferma() { echo "STOP: $1"; exit 1; }

[[ -n "$NOTE" ]] || ferma "scrivi le novità tra virgolette: ./pubblica.sh \"...\""
gh auth status >/dev/null 2>&1 || ferma "prima accedi a GitHub con: gh auth login"
[[ -z "$(git status --porcelain)" ]] || ferma "ci sono modifiche senza commit."
[[ "$(git config user.name)" == "$UTENTE" ]] || ferma "l'autore dei commit deve essere $UTENTE (git config user.name)."

# Prima volta: crea il repository pubblico
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "== Creo il repository pubblico $UTENTE/$REPO"
  gh repo create "$UTENTE/$REPO" --public --source . --remote origin \
    --description "Regia per Mac: analisi e ottimizzazione sicura di macOS, con anteprima, Modalità prova e Annulla tutto."
fi

if git ls-remote --tags origin "refs/tags/v$V" | grep -q .; then ferma "la versione $V è già pubblicata: aumenta il numero in VERSIONE."; fi
if [[ -f versione.json ]]; then
  PRIMA=$(python3 -c "import json; print(json.load(open('versione.json'))['versione'])")
  python3 -c "import sys; a=[int(x) for x in '$V'.split('.')]; b=[int(x) for x in '$PRIMA'.split('.')]; sys.exit(0 if a>b else 1)" \
    || ferma "VERSIONE ($V) deve essere più alta di quella pubblicata ($PRIMA)."
fi

echo "== 1/5 Compilo e provo"
./crea-app.sh
./Regia.app/Contents/MacOS/Regia --autotest | tail -1 | grep -q "TUTTO OK" || ferma "l'autotest non è passato."
[[ "$(defaults read "$PWD/Regia.app/Contents/Info.plist" CFBundleShortVersionString)" == "$V" ]] || ferma "versione dell'app diversa da $V."

echo "== 2/5 Creo lo zip"
mkdir -p Distribuzione
rm -f "$ZIP"
ditto -c -k --keepParent Regia.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo "SHA-256: $SHA"

echo "== 3/5 Carico il codice e creo la Release v$V"
git push -u origin main
gh release create "v$V" "$ZIP" --repo "$UTENTE/$REPO" --target main --title "Regia Mac $V" --notes "$NOTE

**Installazione (la prima volta)**
1. Scarica \`Regia-Mac_$V.zip\` qui sotto e aprilo: compare **Regia**.
2. Trascina Regia nella cartella **Applicazioni**.
3. Apri Regia. macOS dice che non può verificare lo sviluppatore (Regia non è firmata con un certificato Apple a pagamento): apri **Impostazioni di Sistema › Privacy e sicurezza** e premi **Apri comunque**.

Poi si aggiorna da sola: quando esce una versione nuova compare il pulsante **Aggiorna** in basso a sinistra.

SHA-256: \`$SHA\`"

echo "== 4/5 Controllo lo zip online"
sleep 3
ONLINE=$(curl -sfL "$URL" | shasum -a 256 | cut -d' ' -f1)
[[ "$ONLINE" == "$SHA" ]] || ferma "lo zip online ha un'impronta diversa ($ONLINE): versione.json NON aggiornato."

echo "== 5/5 Aggiorno versione.json"
python3 - "$V" "$URL" "$SHA" "$NOTE" > versione.json <<'PY'
import json, sys
print(json.dumps({"versione": sys.argv[1], "url": sys.argv[2], "sha256": sys.argv[3], "note": sys.argv[4]},
                 ensure_ascii=False, indent=2))
PY
git add versione.json
git commit -q -m "Regia Mac $V: versione.json"
git push origin main
echo ""
echo "Fatto: https://github.com/$UTENTE/$REPO/releases/tag/v$V"
echo "Le copie installate vedranno \"Aggiorna alla $V\" entro qualche minuto."
