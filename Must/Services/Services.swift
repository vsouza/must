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
    /// Buscar por nome (prompt 17 · A): sugestões e fotos do Google (com `ApiBudget`).
    let autocomplete: any AutocompleteProviding
    let placePhotos: any PlacePhotosProviding
    /// Foto principal e galeria do lugar: Google primeiro, Commons de reserva (prompt 19).
    let photoResolver: PlacePhotoResolver
    /// Ajustes › Dados › "Baixar fotos dos lugares" (prompt 19 · item 5).
    let photoBatch: PhotoBatch
    let eta: ETACache
    let sync: SyncCoordinator
    /// Dia aceito no aparelho: foto das paradas, previsão e estado do mapa (prompt 18 · A.5).
    let prefetch: DayPrefetch
    /// "Por perto": cache de 30 min por célula + fontes externas (prompt 14 · B).
    let nearby: NearbyLoader
    let maps = OfflineMaps()
    /// Rede do aparelho (prompt 18 · A.4): chip "sem internet · offline ok" e fila de saída.
    let connectivity = Connectivity()
    /// Bairro do GPS (prompt 21 · fatia 2): tabela curada, depois `CLGeocoder` por célula de ~300 m. Fora do main.
    let currentArea = CurrentAreaService()

    init(places: any PlacesProviding = PlacesService(), weather: any WeatherProviding = WeatherService(),
         photos: any PhotoProviding = CommonsPhotoService(), routes: any RoutesProviding = RoutesService(),
         nearby: any NearbyProviding = NearbyService(), autocomplete: any AutocompleteProviding = PlaceAutocomplete(),
         placePhotos: any PlacePhotosProviding = GooglePlacePhotos()) {
        location = LocationService()
        connectivity.start()
        let launched = Self.launchPlaces(places)
        self.places = launched
        self.autocomplete = Self.launchAutocomplete(autocomplete)
        let launchedPhotos = Self.launchPhotos(placePhotos)
        self.placePhotos = launchedPhotos
        let resolver = PlacePhotoResolver(provider: launchedPhotos, commons: photos)
        photoResolver = resolver
        photoBatch = PhotoBatch(provider: launchedPhotos)
        self.weather = weather
        self.photos = photos
        self.routes = routes
        eta = ETACache(routes: routes)
        let coordinator = SyncCoordinator(places: launched, weather: weather, photos: photos)
        sync = coordinator
        prefetch = DayPrefetch(sources: DayPrefetch.live(sync: coordinator, resolver: resolver, photos: photos))
        self.nearby = Self.launchNearby(nearby)
    }

    /// `-debugNearby fake` (prints/simulador): fontes de mentira e um cache próprio, pra não misturar com o real.
    private static func launchNearby(_ live: any NearbyProviding) -> NearbyLoader {
        #if DEBUG
        if DebugFlags.string("debugNearby") == "fake" {
            let cache = NearbyCache(directory: URL.temporaryDirectory.appending(path: "must-nearby-fake", directoryHint: .isDirectory))
            return NearbyLoader(provider: FakeNearbyProvider(places: FakeNearbyProvider.samples), cache: cache)
        }
        #endif
        return NearbyLoader(provider: live, cache: .shared)
    }

    /// `-debugPlaces fake` (simulador/prints): Places de mentira pro Adicionar por link.
    private static func launchPlaces(_ live: any PlacesProviding) -> any PlacesProviding {
        #if DEBUG
        if DebugFlags.string("debugAutocomplete") == "fake" { return FakePlacesService.koffeeSamples }
        if DebugFlags.string("debugPlaces") == "fake" { return FakePlacesService.linkSamples }
        #endif
        return live
    }

    /// `-debugPhotos fake` (ou `-debugAutocomplete fake`): fotos de mentira (sem cota) pros prints.
    private static func launchPhotos(_ live: any PlacePhotosProviding) -> any PlacePhotosProviding {
        #if DEBUG
        if DebugFlags.string("debugPhotos") == "fake" || DebugFlags.string("debugAutocomplete") == "fake" { return FakePlacePhotos() }
        #endif
        return live
    }

    /// `-debugAutocomplete fake` (prints): sugestões de mentira pra Buscar por nome.
    private static func launchAutocomplete(_ live: any AutocompleteProviding) -> any AutocompleteProviding {
        #if DEBUG
        if DebugFlags.string("debugAutocomplete") == "fake" { return FakeAutocomplete() }
        #endif
        return live
    }

    /// Fontes das "Dicas de quem foi" (prompt 11). `-debugTips fake` usa amostras (prints/simulador).
    func tipsProviders(for query: TipsQuery) -> [any TipsProviding] {
        #if DEBUG
        if DebugFlags.string("debugTips") == "fake" {
            return [SourceCaptionTips()] + FakeTipsProvider.samples(for: query)
        }
        #endif
        return [SourceCaptionTips(), GoogleReviewsTips(), FoursquareTips(), RedditTips(), TripAdvisorTips()]
    }
}
