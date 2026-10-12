import CoreLocation
import Foundation
import os

/// Weather + AQI via Open-Meteo (free, no API key). Coordinates come from
/// Core Location. Nothing is fetched until the system returns a fix, so a
/// hardcoded city never shows up in place of where the Mac actually is.
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var temperatureC: Double?
    @Published private(set) var weatherCode: Int?
    @Published private(set) var aqi: Int?
    @Published private(set) var lowC: Double?
    @Published private(set) var highC: Double?

    private let locator = CLLocationManager()
    private let session: URLSession
    private var latitude: Double?
    private var longitude: Double?

    init(session: URLSession = .shared) {
        self.session = session
        super.init()
        locator.delegate = self
        locator.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    var aqiLabel: String { Self.aqiLabel(for: aqi) }

    /// US AQI bands: up to 50 good, 100 moderate, 150 unhealthy for
    /// sensitive groups.
    static func aqiLabel(for aqi: Int?) -> String {
        guard let aqi else { return "AQI" }
        switch aqi {
        case ..<51: return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Unhealthy (SG)"
        default: return "Unhealthy"
        }
    }

    func refresh() {
        switch locator.authorizationStatus {
        case .notDetermined:
            locator.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            locator.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard
            manager.authorizationStatus == .authorized
                || manager.authorizationStatus == .authorizedAlways
        else { return }
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        Task {
            async let weather: () = fetchWeather()
            async let air: () = fetchAQI()
            _ = await (weather, air)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.modules.error("[FreeTheNotch] location failed: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: Open-Meteo

    /// The fields of a `/v1/forecast` reply that the lock screen shows.
    struct Forecast: Decodable, Equatable {
        struct Current: Decodable, Equatable {
            let temperature: Double?
            let weatherCode: Int?

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case weatherCode = "weather_code"
            }
        }

        struct Daily: Decodable, Equatable {
            let minimums: [Double]?
            let maximums: [Double]?

            enum CodingKeys: String, CodingKey {
                case minimums = "temperature_2m_min"
                case maximums = "temperature_2m_max"
            }
        }

        let current: Current?
        let daily: Daily?

        var low: Double? { daily?.minimums?.first }
        var high: Double? { daily?.maximums?.first }
    }

    /// The `current.us_aqi` of an air-quality reply.
    struct AirQuality: Decodable, Equatable {
        struct Current: Decodable, Equatable {
            let usAQI: Int?

            enum CodingKeys: String, CodingKey {
                case usAQI = "us_aqi"
            }
        }

        let current: Current?
    }

    static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_min,temperature_2m_max"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components?.url
    }

    static func airQualityURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "us_aqi"),
        ]
        return components?.url
    }

    private func fetchWeather() async {
        guard let latitude, let longitude,
            let url = Self.forecastURL(latitude: latitude, longitude: longitude),
            let (data, _) = try? await session.data(from: url),
            let forecast = try? JSONDecoder().decode(Forecast.self, from: data)
        else { return }
        await MainActor.run {
            self.temperatureC = forecast.current?.temperature
            self.weatherCode = forecast.current?.weatherCode
            self.lowC = forecast.low
            self.highC = forecast.high
        }
    }

    private func fetchAQI() async {
        guard let latitude, let longitude,
            let url = Self.airQualityURL(latitude: latitude, longitude: longitude),
            let (data, _) = try? await session.data(from: url),
            let value = (try? JSONDecoder().decode(AirQuality.self, from: data))?.current?.usAQI
        else { return }
        await MainActor.run { self.aqi = value }
    }
}
