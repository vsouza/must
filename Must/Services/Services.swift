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
    let maps = OfflineMaps()

    init(places: any PlacesProviding = PlacesService(), weather: any WeatherProviding = WeatherService(),
         photos: any PhotoProviding = CommonsPhotoService(), routes: any RoutesProviding = RoutesService()) {
        location = LocationService()
        let launched = Self.launchPlaces(places)
        self.places = launched
        self.weather = weather
        self.photos = photos
        self.routes = routes
        eta = ETACache(routes: routes)
        sync = SyncCoordinator(places: launched, weather: weather, photos: photos)
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
