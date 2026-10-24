import CoreLocation
import Foundation

/// Open-Meteo (anahtarsız, ücretsiz) ile hava durumu. Konum izni yoksa saat dilimindeki şehir kullanılır.
@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    struct Hour: Identifiable {
        let date: Date
        let temperature: Double
        let code: Int
        var id: Date { date }
    }

    struct Weather {
        var place: String
        var temperature: Double
        var apparentTemperature: Double
        var code: Int
        var isDay: Bool
        var high: Double
        var low: Double
        var precipitationChance: Int?
        var hours: [Hour]
    }

    private(set) var weather: Weather?

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var location: CLLocation?
    @ObservationIgnored private var placeName: String?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastFetch: Date?

    func start() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.requestWhenInUseAuthorization()
        resolveLocation()

        let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Ayarlar (şehir, birim) değişince baştan yükler.
    func reload() {
        location = nil
        placeName = nil
        lastFetch = nil
        resolveLocation()
    }

    // MARK: - Konum

    private var manualCity: String { AppSettings.shared.weatherCity }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        resolveLocation()
    }

    private func resolveLocation() {
        if !manualCity.isEmpty {
            Task { await geocode(manualCity) }
            return
        }
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            Task { await useTimeZoneLocation() }
        default:
            // Karar verilmediyse beklerken en azından saat diliminden bir tahmin göster.
            if weather == nil { Task { await useTimeZoneLocation() } }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manualCity.isEmpty, let newLocation = locations.last else { return }
        let moved = location.map { $0.distance(from: newLocation) > 5_000 } ?? true
        location = newLocation
        guard moved else { return }
        CLGeocoder().reverseGeocodeLocation(newLocation) { [weak self] placemarks, _ in
            let mark = placemarks?.first
            self?.placeName = mark?.locality ?? mark?.administrativeArea
            self?.refresh(force: true)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if location == nil && manualCity.isEmpty { Task { await useTimeZoneLocation() } }
    }

    /// "Europe/Istanbul" → "Istanbul".
    private func useTimeZoneLocation() async {
        let city = TimeZone.current.identifier.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "_", with: " ") ?? ""
        await geocode(city)
    }

    /// Şehir adını Open-Meteo geocoding ile koordinata çevirip hava durumunu yükler.
    private func geocode(_ city: String) async {
        guard location == nil, !city.isEmpty else { return }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"),
                                 .init(name: "language", value: "tr")]
        struct Response: Decodable {
            struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double }
            let results: [Result]?
        }
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let result = (try? JSONDecoder().decode(Response.self, from: data))?.results?.first
        else { return }
        await MainActor.run {
            guard self.location == nil else { return }
            self.location = CLLocation(latitude: result.latitude, longitude: result.longitude)
            self.placeName = result.name
            self.refresh(force: true)
        }
    }

    // MARK: - Hava durumu

    private func refresh(force: Bool = false) {
        guard let location else { return }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 10 * 60 { return }
        lastFetch = Date()
        let place = placeName ?? ""
        Task {
            guard let weather = try? await Self.fetch(location: location, place: place) else { return }
            await MainActor.run { self.weather = weather }
        }
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Hourly: Decodable {
            let time: [Double]
            let temperature_2m: [Double]
            let weather_code: [Int]
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    private static func fetch(location: CLLocation, place: String) async throws -> Weather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", location.coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", location.coordinate.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "forecast_days", value: "2"),
            .init(name: "temperature_unit", value: AppSettings.shared.temperatureUnit.rawValue),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let r = try JSONDecoder().decode(Response.self, from: data)

        let now = Date()
        let hours = zip(r.hourly.time, zip(r.hourly.temperature_2m, r.hourly.weather_code))
            .map { Hour(date: Date(timeIntervalSince1970: $0), temperature: $1.0, code: $1.1) }
            .filter { $0.date > now.addingTimeInterval(-30 * 60) }
            .prefix(5)

        return Weather(
            place: place,
            temperature: r.current.temperature_2m,
            apparentTemperature: r.current.apparent_temperature,
            code: r.current.weather_code,
            isDay: r.current.is_day == 1,
            high: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
            low: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
            precipitationChance: r.daily.precipitation_probability_max.first ?? nil,
            hours: Array(hours)
        )
    }

    // MARK: - WMO hava kodları

    static func symbol(for code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: "cloud.rain.fill"
        case 65, 67, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(for code: Int) -> String {
        switch code {
        case 0: "Açık"
        case 1: "Çoğunlukla açık"
        case 2: "Parçalı bulutlu"
        case 3: "Kapalı"
        case 45, 48: "Sisli"
        case 51, 53, 55: "Çisenti"
        case 56, 57: "Dondurucu çisenti"
        case 61, 80: "Hafif yağmur"
        case 63, 81: "Yağmurlu"
        case 65, 82: "Şiddetli yağmur"
        case 66, 67: "Dondurucu yağmur"
        case 71, 85: "Hafif kar"
        case 73, 75, 86: "Karlı"
        case 77: "Kar taneleri"
        case 95: "Gök gürültülü"
        case 96, 99: "Dolu ve fırtına"
        default: "Bulutlu"
        }
    }
}
