import Foundation
import Testing

struct WeatherServiceTests {
    @Test(arguments: [
        (Int?.none, "AQI"),
        (0, "Good"),
        (50, "Good"),
        (51, "Moderate"),
        (100, "Moderate"),
        (101, "Unhealthy (SG)"),
        (150, "Unhealthy (SG)"),
        (151, "Unhealthy"),
        (420, "Unhealthy"),
    ])
    func aqiBands(_ aqi: Int?, expected: String) {
        #expect(WeatherService.aqiLabel(for: aqi) == expected)
    }

    @Test func decodesTheForecastFields() throws {
        let json = """
            {"latitude": 21.0, "longitude": 105.75, "timezone": "Asia/Bangkok",
             "current_units": {"temperature_2m": "°C"},
             "current": {"time": "2026-10-12T10:00", "interval": 900, "temperature_2m": 31.4, "weather_code": 3},
             "daily": {"time": ["2026-10-12", "2026-10-13"],
                       "temperature_2m_min": [25.1, 24.0], "temperature_2m_max": [33, 32.5]}}
            """
        let forecast = try JSONDecoder().decode(WeatherService.Forecast.self, from: Data(json.utf8))
        #expect(forecast.current?.temperature == 31.4)
        #expect(forecast.current?.weatherCode == 3)
        #expect(forecast.low == 25.1)
        #expect(forecast.high == 33)
    }

    @Test func missingSectionsDecodeAsUnknown() throws {
        let forecast = try JSONDecoder().decode(WeatherService.Forecast.self, from: Data(#"{"error": true}"#.utf8))
        #expect(forecast.current == nil)
        #expect(forecast.low == nil)
    }

    @Test func decodesTheAirQuality() throws {
        let json = #"{"current": {"time": "2026-10-12T10:00", "us_aqi": 42}}"#
        let air = try JSONDecoder().decode(WeatherService.AirQuality.self, from: Data(json.utf8))
        #expect(air.current?.usAQI == 42)
    }

    @Test func forecastURLCarriesTheQuery() throws {
        let url = try #require(WeatherService.forecastURL(latitude: 21.03, longitude: -105.85))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "api.open-meteo.com")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(query["latitude"] == "21.03")
        #expect(query["longitude"] == "-105.85")
        #expect(query["current"] == "temperature_2m,weather_code")
        #expect(query["timezone"] == "auto")
    }
}

struct SpeedTestTests {
    @Test(arguments: [
        (25_000_000, 2.0, Double?.some(100)),
        (8_000_000, 0.5, 128),
        (0, 1, 0),
        (1_000, 0, nil),
    ])
    func megabitsPerSecond(_ bytes: Int, seconds: TimeInterval, expected: Double?) {
        #expect(SpeedTest.megabitsPerSecond(bytes: bytes, seconds: seconds) == expected)
    }
}

struct WiFiMonitorTests {
    @Test(arguments: [(-40, 3), (-67, 3), (-68, 2), (-75, 2), (-76, 1), (-95, 1)])
    func barsFollowDuoBarThresholds(_ rssi: Int, expected: Int) {
        #expect(WiFiMonitor.bars(forRSSI: rssi) == expected)
    }
}
