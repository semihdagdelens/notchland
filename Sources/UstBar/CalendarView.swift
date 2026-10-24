import SwiftUI

/// Takvim sekmesi: solda hafta şeridi ve günün etkinlikleri, sağda hava durumu detayı.
struct CalendarTabView: View {
    let calendar: CalendarService
    let weather: WeatherService

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                WeekStrip(calendar: calendar)
                EventList(calendar: calendar)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let current = weather.weather {
                WeatherDetail(weather: current)
                    .frame(width: 200)
            }
        }
    }
}

private struct WeekStrip: View {
    let calendar: CalendarService

    private var days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (-1...5).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: calendar.selectedDay)
                let isToday = Calendar.current.isDateInToday(day)
                Button {
                    calendar.selectedDay = day
                } label: {
                    VStack(spacing: 1) {
                        Text(day, format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(day, format: .dateTime.day())
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isToday && !isSelected ? Color.red : .white)
                    }
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.white.opacity(0.18) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct EventList: View {
    let calendar: CalendarService

    var body: some View {
        switch calendar.access {
        case .denied:
            Label("Takvim izni verilmedi", systemImage: "calendar.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unknown:
            EmptyView()
        case .granted:
            if calendar.events.isEmpty {
                Button {
                    calendar.openCalendarApp()
                } label: {
                    Text("Etkinlik yok")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(calendar.events) { event in
                            EventRow(event: event)
                                .contentShape(Rectangle())
                                .onTapGesture { calendar.open(event) }
                        }
                    }
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarService.Event

    var body: some View {
        let isPast = event.end < .now
        HStack(spacing: 8) {
            Capsule()
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Group {
                    if event.isAllDay {
                        Text("Tüm gün")
                    } else {
                        Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                            + Text(event.location.map { " · \($0)" } ?? "")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .opacity(isPast ? 0.45 : 1)
    }
}

private struct WeatherDetail: View {
    let weather: WeatherService.Weather

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: WeatherService.symbol(for: weather.code, isDay: weather.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 26))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(weather.temperature.rounded()))°")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(weather.place.isEmpty ? WeatherService.description(for: weather.code) : weather.place)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text("\(WeatherService.description(for: weather.code)) · Y:\(Int(weather.high.rounded()))° D:\(Int(weather.low.rounded()))°")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 0) {
                ForEach(weather.hours) { hour in
                    VStack(spacing: 3) {
                        Text(hour.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Image(systemName: WeatherService.symbol(for: hour.code))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 12))
                        Text("\(Int(hour.temperature.rounded()))°")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Ana sayfada saatin altındaki küçük hava durumu.
struct WeatherBadge: View {
    let weather: WeatherService

    var body: some View {
        if let current = weather.weather {
            HStack(spacing: 4) {
                Image(systemName: WeatherService.symbol(for: current.code, isDay: current.isDay))
                    .symbolRenderingMode(.multicolor)
                Text("\(Int(current.temperature.rounded()))°")
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
            .help("\(current.place) · \(WeatherService.description(for: current.code)), hissedilen \(Int(current.apparentTemperature.rounded()))°")
        }
    }
}
