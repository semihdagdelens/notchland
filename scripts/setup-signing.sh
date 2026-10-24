#!/bin/zsh
# Bir kez çalıştırılır: sadece bu Mac'te geçerli, kendinden imzalı "Notchland Dev" kod imzalama
# kimliği oluşturur. Kimlik login anahtar zincirine değil, Notchland'e ayrılmış ayrı bir
# anahtar zincirine konur; böylece codesign hiç parola sormaz. build-app.sh bunu görürse
# onunla imzalar ve Erişilebilirlik izni derlemeler arasında korunur.
set -euo pipefail

NAME="Notchland Dev"
KEYCHAIN="$HOME/Library/Keychains/notchland-signing.keychain-db"
# Bu anahtar zinciri yalnızca yerel geliştirme sertifikasını tutar; parola build-app.sh ile ortak.
KEYCHAIN_PASS="notchland-dev"
LOGIN="$HOME/Library/Keychains/login.keychain-db"

# Önceki denemeden login anahtar zincirinde kalan kimliği temizle (codesign parola soruyordu).
while security find-certificate -c "$NAME" "$LOGIN" >/dev/null 2>&1; do
    security delete-identity -c "$NAME" "$LOGIN" >/dev/null 2>&1 \
        || security delete-certificate -c "$NAME" "$LOGIN" >/dev/null
done

if [[ -f "$KEYCHAIN" ]] && security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" zaten kurulu."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

cat > cfg.cnf <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF

# Sistemdeki openssl'i kullan; Homebrew'un OpenSSL 3/4'ü macOS'in okuyamadığı .p12 üretir.
OPENSSL=/usr/bin/openssl
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cfg.cnf 2>/dev/null
P12_PASS="$("$OPENSSL" rand -hex 12)"
"$OPENSSL" pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -inkey key.pem -in cert.pem -name "$NAME" -out id.p12 -passout "pass:$P12_PASS"

[[ -f "$KEYCHAIN" ]] || security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # otomatik kilitlenmesin
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security import id.p12 -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign
# codesign'ın anahtara parola sormadan erişebilmesi için.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null

# Anahtar zincirini arama listesine ekle (mevcutları koruyarak).
existing=("${(@f)$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')}")
if [[ ${existing[(Ie)$KEYCHAIN]} -eq 0 ]]; then
    security list-keychains -d user -s "${existing[@]}" "$KEYCHAIN"
fi

if ! security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Hata: sertifika eklenemedi." >&2
    exit 1
fi
echo "\"$NAME\" kuruldu. Şimdi ./scripts/build-app.sh ile yeniden derle."
