#!/bin/zsh
# Derler, /Applications/UstBar.app olarak kurar ve başlatır.
# "Oturum açılınca başlat" en sağlıklı /Applications'taki kopyayla çalışır.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
pkill -x UstBar 2>/dev/null || true
rm -rf /Applications/UstBar.app
ditto build/UstBar.app /Applications/UstBar.app
open /Applications/UstBar.app
echo "Kuruldu: /Applications/UstBar.app"
