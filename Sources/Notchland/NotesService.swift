import AppKit

/// Notlar uygulamasındaki "Notchland" klasörüyle eşitlenir (yoksa oluşturur). Notlar'ın genel bir
/// API'si olmadığından betik arayüzü (JavaScript for Automation, osascript) kullanılır;
/// ilk kullanımda macOS "Notchland, Notlar'ı denetlemek istiyor" izni sorar.
/// Notlar iCloud'daysa iPhone'daki Notlar'da da aynı klasörde görünür.
@Observable
final class NotesService {
    struct Note: Identifiable, Equatable {
        let id: String
        let title: String
        /// Başlık satırı dahil düz metin.
        let text: String
        let modified: Date

        /// Başlıktan sonraki ilk dolu satır.
        var preview: String {
            text.split(whereSeparator: \.isNewline).dropFirst()
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map(String.init) ?? ""
        }
    }

    static let folderName = "Notchland"

    private(set) var notes: [Note] = []
    private(set) var isLoading = false
    /// Son işlem başarısızsa kullanıcıya gösterilecek açıklama.
    private(set) var error: String?

    @ObservationIgnored private let queue = DispatchQueue(label: "notchland.notes", qos: .userInitiated)

    func refresh() {
        isLoading = notes.isEmpty
        run(Self.listScript, [Self.folderName]) { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            switch result {
            case let .success(output):
                self.error = nil
                self.notes = Self.parse(output)
            case let .failure(failure):
                self.error = failure.message
            }
        }
    }

    /// `id` nil ise yeni not oluşturur. Boş metin mevcut notu siler.
    func save(id: String?, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if let id { delete(id: id) }
            return
        }
        let html = Self.html(from: trimmed)
        if let id {
            run(Self.updateScript, [id, html]) { [weak self] in self?.finish($0) }
        } else {
            run(Self.createScript, [Self.folderName, html]) { [weak self] in self?.finish($0) }
        }
    }

    func delete(id: String) {
        notes.removeAll { $0.id == id }
        run(Self.deleteScript, [id]) { [weak self] in self?.finish($0) }
    }

    /// Notu Notlar uygulamasında açar (id yoksa yalnızca uygulamayı).
    func open(id: String?) {
        run(Self.showScript, [id ?? ""]) { _ in }
    }

    private func finish(_ result: Result<String, Failure>) {
        if case let .failure(message) = result { error = message.message }
        refresh()
    }

    // MARK: - osascript

    struct Failure: Error {
        let message: String
    }

    private func run(_ script: String, _ arguments: [String], completion: @escaping (Result<String, Failure>) -> Void) {
        queue.async {
            let result = Self.execute(script, arguments)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func execute(_ script: String, _ arguments: [String]) -> Result<String, Failure> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-l", "JavaScript", "-e", script] + arguments
        let output = Pipe()
        let errors = Pipe()
        task.standardOutput = output
        task.standardError = errors
        do {
            try task.run()
        } catch {
            return .failure(Failure(message: error.localizedDescription))
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8) ?? ""
            // -1743: Otomasyon izni verilmedi.
            if detail.contains("-1743") || detail.lowercased().contains("not authorized") {
                return .failure(Failure(message: "Notlar izni yok: Sistem Ayarları › Gizlilik › Otomasyon"))
            }
            NSLog("[Notchland] Notlar betiği başarısız: \(detail)")
            return .failure(Failure(message: "Notlar'a ulaşılamadı"))
        }
        return .success(String(data: data, encoding: .utf8) ?? "")
    }

    private static func parse(_ output: String) -> [Note] {
        guard let data = output.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row -> Note? in
            guard let id = row["id"] as? String else { return nil }
            let modified = (row["modified"] as? NSNumber)?.doubleValue ?? 0
            return Note(
                id: id,
                title: (row["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Yeni Not",
                text: row["text"] as? String ?? "",
                modified: Date(timeIntervalSince1970: modified / 1000)
            )
        }
        .sorted { $0.modified > $1.modified }
    }

    /// Notlar gövdeyi HTML olarak saklar; ilk satır başlık olur.
    private static func html(from text: String) -> String {
        text.components(separatedBy: .newlines).map { line in
            let escaped = line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return escaped.isEmpty ? "<div><br></div>" : "<div>\(escaped)</div>"
        }
        .joined()
    }

    // Betikler argümanları `argv` ile alır; metin betiğe gömülmediği için kaçış derdi yoktur.

    private static let folderLookup = """
    function appFolder(Notes, name) {
        const found = Notes.folders.whose({ name: name })();
        if (found.length > 0) return found[0];
        const legacy = Notes.folders.whose({ name: '\(LegacyMigration.legacyName)' })();
        if (legacy.length > 0) { legacy[0].name = name; return legacy[0]; }
        Notes.make({ new: 'folder', withProperties: { name: name } });
        return Notes.folders.whose({ name: name })()[0];
    }
    """

    private static let listScript = folderLookup + """
    function run(argv) {
        const Notes = Application('Notes');
        const notes = appFolder(Notes, argv[0]).notes;
        const ids = notes.id(), names = notes.name(), texts = notes.plaintext(), dates = notes.modificationDate();
        return JSON.stringify(ids.map((id, i) => ({ id: id, name: names[i], text: texts[i], modified: dates[i].getTime() })));
    }
    """

    private static let createScript = folderLookup + """
    function run(argv) {
        const Notes = Application('Notes');
        Notes.make({ new: 'note', at: appFolder(Notes, argv[0]), withProperties: { body: argv[1] } });
        return 'ok';
    }
    """

    private static let updateScript = """
    function run(argv) {
        Application('Notes').notes.byId(argv[0]).body = argv[1];
        return 'ok';
    }
    """

    private static let deleteScript = """
    function run(argv) {
        const Notes = Application('Notes');
        Notes.delete(Notes.notes.byId(argv[0]));
        return 'ok';
    }
    """

    private static let showScript = """
    function run(argv) {
        const Notes = Application('Notes');
        Notes.activate();
        if (argv[0]) Notes.notes.byId(argv[0]).show();
        return 'ok';
    }
    """
}
