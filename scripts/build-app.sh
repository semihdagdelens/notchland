#!/bin/zsh
# Release build alır ve build/UstBar.app paketini oluşturur.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/UstBar"

APP="build/UstBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/UstBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/MediaRemote "$APP/Contents/Resources/MediaRemote"

# Kalıcı kimlik varsa onunla imzala (izinler derlemeler arasında korunur), yoksa ad-hoc.
KEYCHAIN="$HOME/Library/Keychains/ustbar-signing.keychain-db"
if [[ -f "$KEYCHAIN" ]] && security find-certificate -c "UstBar Dev" "$KEYCHAIN" >/dev/null 2>&1; then
    security unlock-keychain -p "ustbar-dev" "$KEYCHAIN"
    codesign --force --keychain "$KEYCHAIN" --sign "UstBar Dev" "$APP"
else
    echo "Uyarı: 'UstBar Dev' kimliği yok; ad-hoc imzalanıyor. İzinler her derlemede sıfırlanır (scripts/setup-signing.sh)."
    codesign --force --sign - "$APP"
fi

echo "Hazır: $APP"
