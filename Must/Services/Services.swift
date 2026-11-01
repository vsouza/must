import Observation

/// Serviços compartilhados do app (o único "singleton" além do `RegionStore`).
/// Injetado no root com `.environment(services)`. Cada serviço tem protocolo + real + Fake.
@MainActor
@Observable
final class Services {
    let location: LocationService
    let places: any PlacesProviding
    let weather: any WeatherProviding
    let flickr: any FlickrProviding
    let routes: any RoutesProviding
    let eta: ETACache
    let sync: SyncCoordinator

    init(places: any PlacesProviding = PlacesService(), weather: any WeatherProviding = WeatherService(),
         flickr: any FlickrProviding = FlickrService(), routes: any RoutesProviding = RoutesService()) {
        location = LocationService()
        self.places = places
        self.weather = weather
        self.flickr = flickr
        self.routes = routes
        eta = ETACache(routes: routes)
        sync = SyncCoordinator(places: places, weather: weather, flickr: flickr)
    }
}
