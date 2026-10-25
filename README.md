# Notchland

MacBook'un çentiğini (notch) etkileşimli bir panele dönüştüren macOS menü çubuğu uygulaması. Fareyi çentiğin üzerine getirince açılır; kapalıyken de ses, parlaklık, pil ve çalan müzik gibi bilgileri çentiğin iki yanında gösterir.

SwiftUI + AppKit ile yazılmıştır, macOS 14 veya üstü gerekir.

## Özellikler

**Kapalı çentikte**
- Ses, parlaklık ve pil göstergeleri (sistem HUD'unun yerine), düşük pil uyarısı
- Bluetooth kulaklık bağlanınca pil seviyeleri (AirPods için sol/sağ/kutu)
- Canlı müzik etkinliği: solda kapak, sağda müziğin ritmine oturan ses dalgası
- Işık şovu: müzik çalarken çentiğin çevresinde kapak renginde, basla birlikte atan ışık
- Yaklaşan takvim etkinliği hatırlatması
- Ekrana gelen bildirimlerin çentikte yansıtılması
- **Koci**: Kocinyo'nun yıldız gözlü kedisi, piksel hâliyle çentiğin altına tutunur; müzikte kafa sallar, pil azalınca ağlar, Mac ısınınca terler, gece uyur, şarj takılınca sevinir. Çalan bir şey yokken ana sayfada oturup konuşur, tıklanınca tepki verir.

**Açık çentikte (sekmeler)**
- **Ana sayfa** — Spotify, Music, tarayıcıdaki YouTube vb. için sistem genelinde medya bilgisi ve kontrolü, senkron şarkı sözleri ve yabancı sözlerin satır satır Türkçe çevirisi (macOS'un cihaz içi çevirisiyle), kapak rengine bürünen arka plan
- **Takvim** — haftalık şerit, günün etkinlikleri ve hava durumu
- **Pano** — metin, bağlantı, görsel ve dosya geçmişi; kaydedilen ekran görüntüleri de eklenir. Şifre yöneticilerinin gizli olarak işaretlediği kopyalar kaydedilmez.
- **Sistem** — CPU, bellek, GPU, ağ ve disk kullanımı, küçük grafiklerle
- **Notlar** — Hatırlatıcılar ile Notlar uygulamasındaki “Notchland” klasörüyle eşitlenen hızlı notlar
- **Hesap makinesi** — geçmişli, klavyeyle de kullanılabilir
- **Wrapped** — bugün, bu hafta, bu ay ve tüm zamanlarda ne kadar müzik dinlediğin; en çok dinlenen şarkılar ve sanatçılar, seri ve en çok dinlenen saat (yalnızca bu Mac'te tutulur)
- **Raf** — çentiğe sürüklenen dosyalar için geçici raf; AirDrop'a bırakma alanı

**Diğer**
- Kısayolla açılan Türkçe dikte (cihaz üzerinde tanıma); bitince metni öndeki uygulamaya yapıştırır
- Klavyeyle gezinme: kısayolla çentiği açıp sekmeler ve içerikler arasında tuşlarla dolaşma
- Oturum açılınca başlatma

Hepsi menü çubuğundaki simgeden açılan **Ayarlar** penceresinden açılıp kapatılabilir.

## Kurulum

Gereksinimler: macOS 14+, Xcode komut satırı araçları (Swift 5.10+).

```sh
# Bir kez: yerel kod imzalama kimliği oluştur (izinler derlemeler arasında korunsun diye)
./scripts/setup-signing.sh

# Derle, /Applications/Notchland.app olarak kur ve başlat
./scripts/install.sh
```

Yalnızca paketi oluşturmak için `./scripts/build-app.sh` kullanılır; çıktı `build/Notchland.app` olur.

`setup-signing.sh` çalıştırılmazsa uygulama ad-hoc imzalanır; bu durumda Erişilebilirlik gibi izinler her derlemede sıfırlanır.

## İzinler

Her özellik yalnızca gerektiğinde izin ister:

| İzin | Ne için |
|---|---|
| Erişilebilirlik | Ses/parlaklık tuşlarını yakalamak, bildirimleri yansıtmak, dikteyi otomatik yapıştırmak |
| Takvim, Hatırlatıcılar | Takvim sekmesi ve etkinlik hatırlatmaları, Notlar sekmesindeki hatırlatıcılar |
| Otomasyon (Notlar) | Hızlı notları Notlar uygulamasıyla eşitlemek |
| Mikrofon, Konuşma Tanıma | Dikte |
| Sistem sesi kaydı | Ses dalgasını müziğin ritmine oturtmak (ses kaydedilmez, yalnızca ritim bilgisi saklanır) |
| Konum | Bulunduğun yerin hava durumu (verilmezse saat dilimindeki şehir kullanılır) |
| Bluetooth | Kulaklık pil seviyesi |

## Veriler ve ağ

- Yerel veriler `~/Library/Application Support/Notchland/` altında durur (pano geçmişi, raf, şarkı ritimleri, dinleme geçmişi).
- Hava durumu için [Open-Meteo](https://open-meteo.com), şarkı sözleri için [LRCLIB](https://lrclib.net) kullanılır; ikisi de anahtar gerektirmez.

## Teşekkür

macOS 15.4 ve sonrasında sistem genelindeki medya bilgisi, [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3) ile okunur; `Resources/MediaRemote/` altında kendi lisansıyla ([LICENSE](Resources/MediaRemote/LICENSE)) paketlenmiştir.

## Lisans

[MIT](LICENSE) © 2026 Semih Dağdelen
