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

    @ObservationIgnored private var debounce: Task<Void, Never>?

    init(query: String = "") {
        self.query = query
    }

    /// Pedido de Autocomplete com 350 ms de pausa (cada tecla não vira uma chamada).
    func typed(_ text: String, near: CLLocationCoordinate2D, provider: any AutocompleteProviding) {
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
            guard !Task.isCancelled else { return }
            let found = (try? await provider.suggest(text, sessionToken: token, near: near, radius: 3_000)) ?? []
            guard !Task.isCancelled, let self else { return }
            self.suggestions = found
            self.searching = false
        }
    }

    /// Escolhida: Details (o fim da sessão) e até 3 fotos do Google.
    func choose(_ suggestion: PlaceSuggestion, places: any PlacesProviding, photoProvider: any PlacePhotosProviding) async {
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
}
