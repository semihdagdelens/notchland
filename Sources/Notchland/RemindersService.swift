import AppKit
import EventKit

/// Hatırlatıcılar uygulamasıyla EventKit üzerinden eşitlenir: tamamlanmamışları listeler,
/// yeni ekler ve tamamlar. Değişiklikler iCloud üzerinden diğer cihazlara da gider.
@Observable
final class RemindersService {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
        let hasTime: Bool
        let color: NSColor
        var isCompleted = false

        var isOverdue: Bool {
            guard let due else { return false }
            return hasTime ? due < .now : due < Calendar.current.startOfDay(for: .now)
        }
    }

    enum Access {
        case unknown, granted, denied
    }

    private(set) var access: Access = .unknown
    private(set) var items: [Item] = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var didRequest = false
    /// Tamamlanması bekleyenler; kısa bir süre işaretli görünür, sonra kaydedilir.
    @ObservationIgnored private var pendingCompletions: [String: DispatchWorkItem] = [:]

    /// Sekme ilk açıldığında izin ister; sonraki çağrılar yalnızca yeniler.
    func activate() {
        guard !didRequest else {
            reload()
            return
        }
        didRequest = true
        store.requestFullAccessToReminders { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.access = granted ? .granted : .denied
                guard granted else { return }
                self.reload()
                NotificationCenter.default.addObserver(
                    forName: .EKEventStoreChanged, object: self.store, queue: .main
                ) { [weak self] _ in self?.reload() }
            }
        }
    }

    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard access == .granted, !title.isEmpty, let calendar = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        do {
            try store.save(reminder, commit: true)
            reload()
        } catch {
            NSLog("[Notchland] Hatırlatıcı eklenemedi: \(error.localizedDescription)")
        }
    }

    /// İşaretler; bir an sonra kaydeder ki yanlış tıklama geri alınabilsin.
    func toggle(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if let pending = pendingCompletions.removeValue(forKey: item.id) {
            pending.cancel()
            items[index].isCompleted = false
            return
        }
        items[index].isCompleted = true
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCompletions.removeValue(forKey: item.id)
            guard let reminder = self.store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
            reminder.isCompleted = true
            try? self.store.save(reminder, commit: true)
            self.reload()
        }
        pendingCompletions[item.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func openApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    private func reload() {
        guard access == .granted else { return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let items = (reminders ?? [])
                .sorted(by: Self.order)
                .prefix(60)
                .map { reminder in
                    let components = reminder.dueDateComponents
                    return Item(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        due: components.flatMap { Calendar.current.date(from: $0) },
                        hasTime: components?.hour != nil,
                        color: reminder.calendar?.color ?? .systemOrange
                    )
                }
            DispatchQueue.main.async {
                guard let self else { return }
                // Tamamlanmayı bekleyenler işaretli kalsın.
                self.items = items.map { item in
                    var item = item
                    item.isCompleted = self.pendingCompletions[item.id] != nil
                    return item
                }
            }
        }
    }

    /// Önce tarihi olanlar (yakından uzağa), sonra öncelik, sonra eklenme sırası.
    private static func order(_ a: EKReminder, _ b: EKReminder) -> Bool {
        let dueA = a.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        let dueB = b.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        switch (dueA, dueB) {
        case let (x?, y?) where x != y: return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        // EventKit önceliği: 1 en yüksek, 0 yok.
        let priorityA = a.priority == 0 ? 10 : a.priority
        let priorityB = b.priority == 0 ? 10 : b.priority
        if priorityA != priorityB { return priorityA < priorityB }
        return (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
    }
}
