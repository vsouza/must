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

    init(places: any PlacesProviding = PlacesService(), weather: any WeatherProviding = WeatherService(),
         photos: any PhotoProviding = CommonsPhotoService(), routes: any RoutesProviding = RoutesService()) {
        location = LocationService()
        self.places = places
        self.weather = weather
        self.photos = photos
        self.routes = routes
        eta = ETACache(routes: routes)
        sync = SyncCoordinator(places: places, weather: weather, photos: photos)
    }
}
