#!/bin/zsh
# Derler, /Applications/Notchland.app olarak kurar ve başlatır.
# "Oturum açılınca başlat" en sağlıklı /Applications'taki kopyayla çalışır.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
pkill -x Notchland 2>/dev/null || true
# Uygulamanın eski adıyla (UstBar) kurulmuş kopyası; verileri Notchland ilk açılışta taşır.
pkill -x UstBar 2>/dev/null || true
rm -rf /Applications/UstBar.app
rm -rf /Applications/Notchland.app
ditto build/Notchland.app /Applications/Notchland.app
open /Applications/Notchland.app
echo "Kuruldu: /Applications/Notchland.app"
