import Foundation
import Observation

/// Serviços compartilhados do app (o único "singleton" além do `RegionStore`).
/// Injetado no root com `.environment(services)`. Cada serviço tem protocolo + real + Fake.
@MainActor
@Observable
final class Services {
    let location: LocationService
    let places: any PlacesProviding
    let weather: any WeatherProviding
    let photos: any PhotoProviding
    let routes: any RoutesProviding
    let eta: ETACache
    let sync: SyncCoordinator
    /// "Por perto": cache de 30 min por célula + fontes externas (prompt 14 · B).
    let nearby: NearbyLoader
    let maps = OfflineMaps()

    init(places: any PlacesProviding = PlacesService(), weather: any WeatherProviding = WeatherService(),
         photos: any PhotoProviding = CommonsPhotoService(), routes: any RoutesProviding = RoutesService(),
         nearby: any NearbyProviding = NearbyService()) {
        location = LocationService()
        let launched = Self.launchPlaces(places)
        self.places = launched
        self.weather = weather
        self.photos = photos
        self.routes = routes
        eta = ETACache(routes: routes)
        sync = SyncCoordinator(places: launched, weather: weather, photos: photos)
        self.nearby = Self.launchNearby(nearby)
    }

    /// `-debugNearby fake` (prints/simulador): fontes de mentira e um cache próprio, pra não misturar com o real.
    private static func launchNearby(_ live: any NearbyProviding) -> NearbyLoader {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "debugNearby") == "fake" {
            let cache = NearbyCache(directory: URL.temporaryDirectory.appending(path: "must-nearby-fake", directoryHint: .isDirectory))
            return NearbyLoader(provider: FakeNearbyProvider(places: FakeNearbyProvider.samples), cache: cache)
        }
        #endif
        return NearbyLoader(provider: live, cache: .shared)
    }

    /// `-debugPlaces fake` (simulador/prints): Places de mentira pro Adicionar por link.
    private static func launchPlaces(_ live: any PlacesProviding) -> any PlacesProviding {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "debugPlaces") == "fake" { return FakePlacesService.linkSamples }
        #endif
        return live
    }

    /// Fontes das "Dicas de quem foi" (prompt 11). `-debugTips fake` usa amostras (prints/simulador).
    func tipsProviders(for query: TipsQuery) -> [any TipsProviding] {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "debugTips") == "fake" {
            return [SourceCaptionTips()] + FakeTipsProvider.samples(for: query)
        }
        #endif
        return [SourceCaptionTips(), GoogleReviewsTips(), FoursquareTips(), RedditTips(), TripAdvisorTips()]
    }
}
