#!/bin/zsh
# Compila Regia e crea Regia.app in questa cartella.
# Uso:  ./crea-app.sh            -> crea Regia.app
#       ./crea-app.sh --installa -> la copia anche in /Applications
set -e
cd "$(dirname "$0")"
echo "1/4 Compilo…"
swift build -c release --arch arm64 --arch x86_64 2>&1 | grep -v "deprecated" | tail -1   # Apple Silicon + Intel

echo "2/4 Creo il pacchetto…"
APP="Regia.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Regia" "$APP/Contents/MacOS/Regia"
VERSIONE=$(cat VERSIONE 2>/dev/null || echo 1.0)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Regia</string>
  <key>CFBundleDisplayName</key><string>Regia</string>
  <key>CFBundleIdentifier</key><string>io.github.sm-bc.regia</string>
  <key>CFBundleExecutable</key><string>Regia</string>
  <key>CFBundleIconFile</key><string>Regia</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSIONE</string>
  <key>CFBundleVersion</key><string>$VERSIONE</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Regia usa il Finder solo per svuotare il Cestino quando lo chiedi tu.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Regia cerca i download vecchi solo quando premi Calcola.</string>
</dict></plist>
PLIST

echo "3/4 Icona…"
TMP=$(mktemp -d)
swift strumenti/icona.swift "$TMP/icona.png"
mkdir -p "$TMP/Regia.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icona.png" --out "$TMP/Regia.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icona.png" --out "$TMP/Regia.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/Regia.iconset" -o "$APP/Contents/Resources/Regia.icns"
rm -rf "$TMP"

echo "4/4 Firma locale…"
codesign --force --deep --sign - "$APP"

if [[ "$1" == "--installa" ]]; then
  rm -rf /Applications/Regia.app
  cp -R "$APP" /Applications/
  echo "Installata in /Applications/Regia.app"
fi
echo "Fatto: $(pwd)/$APP"
