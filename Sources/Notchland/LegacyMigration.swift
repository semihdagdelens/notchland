import Foundation

/// Uygulamanın eski adı (UstBar) döneminden kalan verileri ilk açılışta bir kez taşır:
/// eski bundle id'nin ayarları ve Application Support klasörü. Notlar klasörü `NotesService`'te
/// ilk kullanımda yeniden adlandırılır.
enum LegacyMigration {
    static let legacyName = "UstBar"
    private static let legacyBundleID = "com.best.ustbar"
    private static let doneKey = "migratedFromUstBar"

    /// Ayarlar ve klasörler okunmadan önce, uygulama açılırken çağrılmalı.
    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        if let old = defaults.persistentDomain(forName: legacyBundleID) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldFolder = support.appendingPathComponent(legacyName, isDirectory: true)
        let newFolder = support.appendingPathComponent("Notchland", isDirectory: true)
        if fileManager.fileExists(atPath: oldFolder.path), !fileManager.fileExists(atPath: newFolder.path) {
            try? fileManager.moveItem(at: oldFolder, to: newFolder)
            // Raf, kendi kaydettiği dosyaları mutlak yolla tutuyor.
            if let paths = defaults.stringArray(forKey: "shelf.paths") {
                let moved = paths.map { $0.replacingOccurrences(of: oldFolder.path + "/", with: newFolder.path + "/") }
                defaults.set(moved, forKey: "shelf.paths")
            }
        }

        defaults.set(true, forKey: doneKey)
    }
}
