#!/bin/zsh
# Testo (in inglese) della pagina di una Release su GitHub. Lo usa pubblica.sh.
# Uso: strumenti/note-release.sh "What's new" 2.4 <sha256>
NOTE="$1"; V="$2"; SHA="$3"
cat <<FINE
### What's new
$NOTE

### Install (first time)
1. Download \`Regia-Mac_$V.zip\` below and open it: **Regia** appears.
2. Drag Regia to your **Applications** folder.
3. Open Regia. macOS says it can't verify the developer, because Regia isn't signed with a paid Apple certificate: open **System Settings › Privacy & Security** and click **Open Anyway**.

After that, Regia updates itself: when a new version is out, an **Update** button appears at the bottom left.

**Requirements:** macOS 14 or later, Apple Silicon or Intel.

SHA-256: \`$SHA\`
FINE
