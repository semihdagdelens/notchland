# CLAUDE.md

Notchland: MacBook çentiğini etkileşimli bir panele dönüştüren macOS 14+ menü çubuğu uygulaması (SwiftUI + AppKit, Swift Package, tek executable target). Kullanıcıya dönük ayrıntılar için README.md'ye bak.

## Komutlar

```sh
swift build                    # hızlı derleme denetimi (çalıştırmak için uygun değil, bkz. aşağısı)
./scripts/build-app.sh         # release derleme → build/Notchland.app (imzalı)
./scripts/install.sh           # derle + /Applications'a kur + başlat (çalışan Notchland'i kapatır)
./scripts/setup-signing.sh     # bir kez: "Notchland Dev" yerel imzalama kimliği
swift scripts/make-icon.swift icon.png   # ikonu 1024px çizer; ardından iconset + iconutil ile Resources/AppIcon.icns
```

- Uygulama `.app` paketi olarak çalışmalı: `Info.plist` (izin açıklamaları, `LSUIElement`) ve `Resources/MediaRemote` ancak pakette bulunur. `swift run` ile medya bilgisi ve izinler çalışmaz.
- Test hedefi yok. Değişikliği doğrulamak için en az `swift build` hatasız geçmeli; davranış için `./scripts/install.sh` ile kurup denemek gerekir.
- Yeni bir izin gerektiren API eklenirse `Resources/Info.plist`'e Türkçe kullanım açıklaması da eklenmeli; yoksa macOS izni sormadan reddeder veya uygulamayı kapatır.

## Mimari

- `main.swift` → `AppDelegate`: uygulamayı `.accessory` olarak başlatır, menü çubuğu simgesini ve `NotchWindowController`'ı kurar.
- Uygulamanın eski adı UstBar'dı (bundle id `com.best.ustbar`). `LegacyMigration` ilk açılışta eski ayarları ve `Application Support/UstBar` klasörünü taşır; `NotesService` Notlar'daki "UstBar" klasörünü yeniden adlandırır. Bu "UstBar" geçişlerini kaldırma.
- `NotchWindowController.swift`: merkez. Tüm servisleri (medya, pil, takvim, pano, dikte…) burada oluşturur, `NotchView`'a enjekte eder, fare takibini, kısayolları ve HUD tetiklemelerini bağlar. Aynı dosyada:
  - `NotchPanel`: saydam, etkinleştirmeyen `NSPanel`. Klavye odağı normalde öndeki uygulamada kalır (pano ⌘V'si oraya gitsin diye); yalnızca Notlar/Hesap makinesi sekmesinde veya klavyeyle gezinirken panel odak alır.
  - `NotchState`: açık/kapalı, seçili sekme (`Tab`), HUD, sürükleme durumu.
- `NotchView.swift`: çentik şekli ve boyutu (kapalı / HUD kulakları / canlı etkinlik / açık / dikte), sekme yönlendirmesi.
- Servisler `@Observable final class`, görünümler SwiftUI `struct`. Servis–görünüm çifti genelde `XService`/`XStore` + `XView` adlandırmasıyla ayrı dosyalarda.
- `AppSettings.shared`: tüm ayarlar; her özellik `didSet` ile UserDefaults'a yazar. Yeni ayar eklerken aynı kalıbı (`AppSettings.value(key, varsayılan)` + `save`) izle ve `SettingsView`'a ekle.
- Yeni sekme eklemek: `NotchState.Tab`'a case, `isTabEnabled`, `AppSettings`'te `showXTab`, `NotchView`'daki switch, gerekiyorsa `KeyboardNavigator`.

### Belgelenmemiş / özel API'ler

Bunlar bilerek kullanılıyor; değiştirirken kırılgan olduklarını unutma:
- **Medya bilgisi** (`MediaController`): macOS 15.4+ MediaRemote'u kapattığı için Apple imzalı `/usr/bin/perl` üzerinden `Resources/MediaRemote/MediaRemoteAdapter.framework` çalıştırılır.
- **Parlaklık** (`SystemControls`): `DisplayServices` özel çerçevesi `dlopen` ile.
- **Kulaklık pili** (`HeadphoneMonitor`): `IOBluetoothDevice`'in belgelenmemiş `batteryPercent…` özellikleri.
- **Bildirim yansıtma** (`NotificationMirror`): Bildirim Merkezi sürecinin pencereleri Erişilebilirlik API'siyle okunur.
- **Ses/parlaklık tuşları** (`MediaKeyTap`): `CGEventTap`, Erişilebilirlik izni ister; izin yoksa tuşlar sisteme bırakılır.
- **Notlar** (`NotesService`): JXA (`osascript`) ile; Notlar'ın genel API'si yok.
- **Ses dalgası**: `VisualizerEngine` kaynağı seçer → kayıtlı ritim (`RhythmRecording`, `~/Library/Application Support/Notchland/Ritimler/`) → yoksa `SystemAudioTap` (Core Audio process tap) ile dinleyip kaydetme → o da yoksa yapay dalga.

Ağ: yalnızca Open-Meteo (hava) ve LRCLIB (sözler); ikisi de anahtarsız. Yeni bir dış servis eklemeden önce sor.

## Kurallar

- Arayüz metinleri, kod yorumları ve commit mesajları **Türkçe**. Yorumlar `///` ile, kısa ve "neden"i anlatır; mevcut yoğunluğa uy.
- Commit başlıkları kısa bir isim öbeği (ör. "Hesap makinesi sekmesi", "Klavyeyle gezinme"); her özellik tek commit.
- Global kısayollar Carbon `GlobalHotKey` ile (Erişilebilirlik gerektirmez); her kısayol kendi örneğiyle kaydolur.
- Panel boyutu `NotchWindowController.expandedSize` (600×190); hiçbir içerik (dikte dahil) bundan büyük olmamalı.
- Gizlilik: ses kaydedilmez, şifre yöneticilerinin gizli işaretlediği pano içerikleri saklanmaz — bu davranışları koru.
