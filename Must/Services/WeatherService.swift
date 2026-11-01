import CoreLocation
import Foundation

/// Previsão de uma região: dias (meia-noite local → tempo) + agora.
struct Forecast: Sendable, Codable {
    struct Now: Sendable, Codable { var temp: Double; var code: Int }
    var days: [Date: DayWeather]
    var now: Now?
    var fetchedAt: Date

    func day(_ date: Date, calendar: Calendar) -> DayWeather? { days[calendar.startOfDay(for: date)] }
}

protocol WeatherProviding: Sendable {
    func forecast(at coordinate: CLLocationCoordinate2D, region: Region) async throws -> Forecast
}

/// Open-Meteo (sem chave). No Japão, modelo da JMA com o `best_match` completando o que faltar.
struct WeatherService: WeatherProviding {
    var http = HTTP()
    static let maxAge: TimeInterval = 3600

    func forecast(at c: CLLocationCoordinate2D, region: Region) async throws -> Forecast {
        let key = "weather-\(region.rawValue)-\(String(format: "%.2f,%.2f", c.latitude, c.longitude))"
        if let cached = await DiskCache.shared.data(for: key, maxAge: Self.maxAge), let f = try? JSONDecoder().decode(Forecast.self, from: cached) {
            return f
        }
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", c.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", c.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: region.timeZone.identifier),
            URLQueryItem(name: "forecast_days", value: "16"),
        ]
        if region == .jp { comps.queryItems?.append(URLQueryItem(name: "models", value: "jma_seamless,best_match")) }
        do {
            let data = try await http.get(comps.url!, service: "weather")
            let forecast = try Self.parse(data, timeZone: region.timeZone)
            if let encoded = try? JSONEncoder().encode(forecast) { await DiskCache.shared.store(encoded, for: key) }
            return forecast
        } catch {
            // Sem rede / dados ao vivo desligados: o último que tiver.
            if let stale = await DiskCache.shared.stale(key), let f = try? JSONDecoder().decode(Forecast.self, from: stale) { return f }
            throw error
        }
    }

    /// Lê variáveis com ou sem sufixo de modelo (`_jma_seamless`, `_best_match`), preferindo a JMA.
    static func parse(_ data: Data, timeZone: TimeZone, fetchedAt: Date = Date()) throws -> Forecast {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = json["daily"] as? [String: Any], let times = daily["time"] as? [String] else {
            throw ServiceError.decoding("open-meteo")
        }
        func series(_ name: String) -> [Any] {
            let candidates = ["\(name)_jma_seamless", name, "\(name)_best_match"]
            let arrays = candidates.compactMap { daily[$0] as? [Any] }
            return times.indices.map { i in arrays.lazy.compactMap { $0.indices.contains(i) && !($0[i] is NSNull) ? $0[i] : nil }.first ?? NSNull() }
        }
        let codes = series("weather_code"), maxT = series("temperature_2m_max"), minT = series("temperature_2m_min")
        let precip = series("precipitation_probability_max"), rise = series("sunrise"), set = series("sunset")
        let dates = BoardDates(timeZone: timeZone)

        func localTime(_ any: Any) -> Date? {
            guard let s = any as? String, s.count >= 16, let day = dates.day(from: String(s.prefix(10))) else { return nil }
            return dates.time(String(s.suffix(5)), on: day)
        }

        var days: [Date: DayWeather] = [:]
        for (i, t) in times.enumerated() {
            guard let day = dates.day(from: t), let code = (codes[i] as? NSNumber)?.intValue else { continue }
            let rainy = [51, 53, 55, 61, 63, 65, 80, 81, 82, 95, 96, 99].contains(code)
            days[day] = DayWeather(tempMin: (minT[i] as? NSNumber)?.doubleValue ?? 0, tempMax: (maxT[i] as? NSNumber)?.doubleValue ?? 0,
                                   code: code, precipProb: (precip[i] as? NSNumber)?.intValue ?? (rainy ? 70 : 10),
                                   sunrise: localTime(rise[i]), sunset: localTime(set[i]))
        }
        var now: Forecast.Now?
        if let current = json["current"] as? [String: Any] {
            let temp = (current["temperature_2m"] ?? current["temperature_2m_jma_seamless"] ?? current["temperature_2m_best_match"]) as? NSNumber
            let code = (current["weather_code"] ?? current["weather_code_jma_seamless"] ?? current["weather_code_best_match"]) as? NSNumber
            if let temp, let code { now = Forecast.Now(temp: temp.doubleValue, code: code.intValue) }
        }
        return Forecast(days: days, now: now, fetchedAt: fetchedAt)
    }
}

struct FakeWeatherService: WeatherProviding {
    var forecast: Forecast
    func forecast(at coordinate: CLLocationCoordinate2D, region: Region) async throws -> Forecast { forecast }
}

extension DayWeather {
    /// "sol", "nublado", "chuva forte"…
    var label: String {
        switch code {
        case 0: "sol"
        case 1: "quase sem nuvens"
        case 2: "sol entre nuvens"
        case 3: "nublado"
        case 45, 48: "neblina"
        case 51, 53, 55: "garoa"
        case 61, 80: "chuva fraca"
        case 63, 81: "chuva"
        case 65, 82: "chuva forte"
        case 71, 73, 75, 77, 85, 86: "neve"
        case 95, 96, 99: "tempestade"
        default: "tempo variável"
        }
    }

    /// "13° e sol"
    var short: String { "\(Int(tempMax.rounded()))° e \(label)" }

    var icon: MustIcon {
        switch code {
        case 0, 1: .sol
        case 2, 3, 45, 48: .nuvem
        default: .chuva
        }
    }
}
