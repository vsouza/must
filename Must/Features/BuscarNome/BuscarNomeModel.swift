import CoreLocation
import Foundation
import Observation
import SwiftData

/// Buscar por nome (prompt 17 · A): sugestões do Autocomplete com session token, e o Details (com as fotos) ao escolher.
/// A sessão fecha no Details; o token novo começa na busca seguinte.
@MainActor
@Observable
final class BuscarNomeModel {
    var query: String
    private(set) var suggestions: [PlaceSuggestion] = []
    private(set) var selected: PlaceSuggestion?
    private(set) var details: PlaceDetails?
    private(set) var photos: [CCPhoto] = []
    private(set) var searching = false
    private(set) var loadingCard = false
    /// Lista escolhida à mão ("outra lista"); nil = a sugerida pelo tipo.
    var listOverride: String?
    private(set) var sessionToken = UUID().uuidString

    @ObservationIgnored let places: any PlacesProviding
    @ObservationIgnored let photoProvider: any PlacePhotosProviding
    @ObservationIgnored let autocomplete: any AutocompleteProviding
    /// Posição atual, lida no momento do pedido (o GPS pode chegar depois da tela abrir).
    @ObservationIgnored let origin: () -> CLLocationCoordinate2D?
    /// Print de QA (`buscar-nome:<texto>:escolher`): escolhe a primeira sugestão sozinho, dentro do modelo.
    @ObservationIgnored let autoChooseFirst: Bool
    @ObservationIgnored private var debounce: Task<Void, Never>?

    /// Raio pra considerar "o mesmo lugar" quando não há coordenada da sugestão (só o placeId e a distância da origem).
    static let sameSpotMeters = 150.0

    init(query: String = "", places: any PlacesProviding, photos: any PlacePhotosProviding,
         autocomplete: any AutocompleteProviding, origin: @escaping () -> CLLocationCoordinate2D?, autoChooseFirst: Bool = false) {
        self.query = query
        self.places = places
        photoProvider = photos
        self.autocomplete = autocomplete
        self.origin = origin
        self.autoChooseFirst = autoChooseFirst
    }

    /// Pedido de Autocomplete com 350 ms de pausa (cada tecla não vira uma chamada).
    func typed(_ text: String, near: CLLocationCoordinate2D) {
        query = text
        debounce?.cancel()
        selected = nil
        details = nil
        photos = []
        guard text.trimmingCharacters(in: .whitespaces).count >= 3 else {
            suggestions = []
            searching = false
            return
        }
        let token = sessionToken
        searching = true
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            let found = (try? await self.autocomplete.suggest(text, sessionToken: token, near: near, origin: self.origin(), radius: 3_000)) ?? []
            guard !Task.isCancelled else { return }
            self.suggestions = found
            self.searching = false
            if self.autoChooseFirst, let first = found.first { await self.choose(first) }
        }
    }

    /// Escolhida: Details (o fim da sessão) e até 3 fotos do Google.
    func choose(_ suggestion: PlaceSuggestion) async {
        selected = suggestion
        details = nil
        photos = []
        loadingCard = true
        let token = sessionToken
        details = try? await places.details(suggestion.placeId, languageCode: "pt-BR", sessionToken: token)
        sessionToken = UUID().uuidString
        photos = (try? await photoProvider.photos(placeId: suggestion.placeId, limit: 3)) ?? []
        loadingCard = false
    }

    /// Lista sugerida pelo tipo do Google (a mesma regra da Descobrir). `nil` quando não há categoria clara.
    static func suggestedListId(types: [String]) -> String? {
        types.lazy.compactMap { type in
            NearbyRanker.suggestedListId(NearbyPlace(name: "", lat: 0, lng: 0, sources: [.google], category: type))
        }.first
    }

    func listId(for suggestion: PlaceSuggestion) -> String? {
        listOverride ?? Self.suggestedListId(types: suggestion.types)
    }

    /// "No board": o mesmo placeId, ou o mesmo nome a menos de 150 m. Com a coordenada da sugestão (Details), a distância é exata;
    /// sem ela (na lista), compara a distância de cada um à origem (o `distanceMeters` do Autocomplete).
    static func boardMatch(for suggestion: PlaceSuggestion, coordinate: CLLocationCoordinate2D?, origin: CLLocationCoordinate2D?,
                           places: [Place]) -> Place? {
        if let same = places.first(where: { $0.placeId == suggestion.placeId }) { return same }
        // Nome igual (sem acento/caixa/pontuação): "Koffee Mameya Roastery" não é "Koffee Mameya", mesmo a 120 m.
        let key = PlaceMatcher.normalize(suggestion.name)
        for place in places where PlaceMatcher.normalize(place.name) == key {
            if let coordinate {
                if distance(place.coordinate, coordinate) < sameSpotMeters { return place }
            } else if let origin, let meters = suggestion.distanceMeters {
                if abs(distance(origin, place.coordinate) - Double(meters)) < sameSpotMeters { return place }
            }
        }
        return nil
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Cria o lugar no board com o placeId, a coordenada e o horário/preço do Details (sem outra chamada ao Google).
    @discardableResult
    func add(to list: MustList, suggestion: PlaceSuggestion, details: PlaceDetails?, region: Region, now: Date, context: ModelContext) -> Place? {
        let trip = (try? context.fetch(FetchDescriptor<TripInfo>()))?.first
        let cityId = trip?.city(on: now, calendar: region.calendar)?.id ?? trip?.cities.first?.id ?? region.rawValue
        let lat = details?.lat ?? 0, lng = details?.lng ?? 0
        let place = Place(id: "g-\(UUID().uuidString.prefix(8).lowercased())", name: details?.name ?? suggestion.name,
                          cityId: cityId, lat: lat, lng: lng)
        place.list = list
        place.order = (list.places.map(\.order).max() ?? 0) + 1
        place.placeId = suggestion.placeId
        place.hours = details?.hours
        place.priceLevel = details?.priceLevel
        place.source = Source(kind: .manual, url: nil, savedAt: nil)
        place.approx = details?.lat == nil
        context.insert(place)
        try? context.save()
        return place
    }
}

extension PlaceSuggestion {
    /// Texto que a tela mostra embaixo do nome: "café · Omotesando, Shibuya".
    var subtitle: String {
        let type = types.lazy.compactMap { NearbyRanker.categoryLabel(NearbyPlace(name: "", lat: 0, lng: 0, sources: [.google], category: $0)) }.first
        return [type, secondary].compactMap { $0 }.joined(separator: " · ")
    }

    /// Café ou torrefação ganham a xícara; o resto, o pino.
    var isCafe: Bool { types.contains { $0 == "cafe" || $0 == "coffee_shop" } }
}
