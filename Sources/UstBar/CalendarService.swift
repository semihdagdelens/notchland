import AppKit
import EventKit

/// Takvim etkinliklerini EventKit ile okur ve yaklaşan etkinlikleri haber verir.
@Observable
final class CalendarService {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: NSColor
        let location: String?
    }

    enum Access {
        case unknown, granted, denied
    }

    private(set) var access: Access = .unknown
    /// Seçili günün etkinlikleri.
    private(set) var events: [Event] = []
    var selectedDay = Calendar.current.startOfDay(for: .now) {
        didSet { reload() }
    }

    /// Bir etkinliğe `reminderLead` kala bir kez çağrılır.
    @ObservationIgnored var onUpcoming: ((Event) -> Void)?
    static var reminderLead: TimeInterval { TimeInterval(AppSettings.shared.calendarReminderMinutes * 60) }

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var remindedIDs: Set<String> = []

    func start() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.access = granted ? .granted : .denied
                guard granted else { return }
                self.reload()
                NotificationCenter.default.addObserver(
                    forName: .EKEventStoreChanged, object: self.store, queue: .main
                ) { [weak self] _ in self?.reload() }
                let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.checkUpcoming() }
                timer.tolerance = 10
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
                self.checkUpcoming()
            }
        }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.open(url)
        }
    }

    func open(_ event: Event) {
        // Takvim uygulamasını etkinliğin gününde açar.
        let interval = event.start.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(interval)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func reload() {
        guard access == .granted else { return }
        let start = selectedDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        events = fetch(from: start, to: end)
    }

    private func fetch(from start: Date, to end: Date) -> [Event] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map {
                Event(
                    id: $0.calendarItemIdentifier + "\($0.startDate.timeIntervalSince1970)",
                    title: $0.title ?? "Etkinlik",
                    start: $0.startDate,
                    end: $0.endDate,
                    isAllDay: $0.isAllDay,
                    color: $0.calendar.color ?? .systemBlue,
                    location: $0.location?.isEmpty == false ? $0.location : nil
                )
            }
    }

    private func checkUpcoming() {
        guard Self.reminderLead > 0 else { return }
        let now = Date()
        let soon = fetch(from: now, to: now.addingTimeInterval(Self.reminderLead + 60))
            .filter { !$0.isAllDay && $0.start > now && $0.start.timeIntervalSince(now) <= Self.reminderLead }
        for event in soon where remindedIDs.insert(event.id).inserted {
            onUpcoming?(event)
        }
    }
}
