#!/bin/zsh
# Release build alır ve build/Notchland.app paketini oluşturur.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Notchland"

APP="build/Notchland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Notchland"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/MediaRemote "$APP/Contents/Resources/MediaRemote"

# Kalıcı kimlik varsa onunla imzala (izinler derlemeler arasında korunur), yoksa ad-hoc.
KEYCHAIN="$HOME/Library/Keychains/notchland-signing.keychain-db"
if [[ -f "$KEYCHAIN" ]] && security find-certificate -c "Notchland Dev" "$KEYCHAIN" >/dev/null 2>&1; then
    security unlock-keychain -p "notchland-dev" "$KEYCHAIN"
    codesign --force --keychain "$KEYCHAIN" --sign "Notchland Dev" "$APP"
else
    echo "Uyarı: 'Notchland Dev' kimliği yok; ad-hoc imzalanıyor. İzinler her derlemede sıfırlanır (scripts/setup-signing.sh)."
    codesign --force --sign - "$APP"
fi

echo "Hazır: $APP"
