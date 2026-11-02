import CoreLocation
import Foundation
import SwiftData

/// Estado do fluxo "Adicionar por link".
@MainActor
@Observable
final class AddLinkModel {
    enum Phase: Equatable { case idle, reading, needsText(String), done, failed(String) }

    var input = ""
    var phase: Phase = .idle
    var resolved: ResolvedLink?
    var caption: Caption?
    var matches: [MatchedPlace] = []
    /// Lista escolhida por resultado.
    var listChoice: [String: String] = [:]
    /// Resultados marcados pra adicionar.
    var included: Set<String> = []
    var pastedText = ""
    /// Lugar selecionado (pino do mapa ↔ linha da lista).
    var selectedId: String?
    /// "um por lugar…": cada linha ganha o seletor de lista.
    var perPlaceLists = false
    /// O Places foi consultado (senão, só entra o que o link trouxe com coordenada).
    var placesChecked = false

    var detectedSource: LinkSource? {
        let source = LinkResolver.resolve(input).source
        return source.badge == nil ? nil : source
    }

    /// Modelo no aparelho / reforço na nuvem (de Ajustes).
    var extractorOptions = AIPlaceExtractor.Options(onDevice: true, cloudBoost: false, knownAreas: [])
    /// Por onde a extração passou ("no aparelho", "reforço na nuvem", "palavras-chave").
    var extractedVia: String?

    var includedMatches: [MatchedPlace] { matches.filter { included.contains($0.id) } }

    /// Lista comum a todos os marcados (nil se há mais de uma).
    var sharedListId: String? {
        let chosen = includedMatches.map { listChoice[$0.id] }
        guard let first = chosen.first ?? nil, chosen.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    func run(board: [Place], lists: [MustList], city: City?, region: Region, knownAreas: [String], provider: any PlacesProviding) async {
        let link = LinkResolver.resolve(input)
        guard !link.text.isEmpty || link.url != nil else { return }
        resolved = link
        phase = .reading
        matches = []
        do {
            let caption = try await CaptionFetcher().fetch(link)
            await finish(caption, board: board, lists: lists, city: city, region: region, knownAreas: knownAreas, provider: provider)
        } catch {
            Log.network.error("legenda falhou: \(error.localizedDescription, privacy: .public)")
            phase = .needsText((error as? LocalizedError)?.errorDescription ?? "Não consegui ler a legenda.")
        }
    }

    /// Fallback: o usuário cola o texto da legenda.
    func runPasted(board: [Place], lists: [MustList], city: City?, region: Region, knownAreas: [String], provider: any PlacesProviding) async {
        let source = resolved?.source ?? .text
        let caption = Caption(source: source, title: nil, text: String(pastedText.prefix(CaptionFetcher.maxLength)), url: resolved?.url)
        await finish(caption, board: board, lists: lists, city: city, region: region, knownAreas: knownAreas, provider: provider)
    }

    /// Extrai → confere no Places → junta o mesmo lugar → casa com o board.
    private func finish(_ caption: Caption, board: [Place], lists: [MustList], city: City?, region: Region,
                        knownAreas: [String], provider: any PlacesProviding) async {
        self.caption = caption
        var options = extractorOptions
        options.knownAreas = knownAreas
        let (extracted, via) = await AIPlaceExtractor.extract(from: caption, options: options)
        extractedVia = via
        placesChecked = provider.isConfigured && DevOverrides.liveData
        // Centros de busca calculados aqui (o board é do MainActor, a busca roda fora).
        let fallback = Self.fallbackCenter(city: city, region: region)
        var centers: [String: CLLocationCoordinate2D] = [:]
        for area in Set(extracted.compactMap(\.area)) {
            centers[area] = Self.center(area: area, board: board, city: city, region: region)
        }
        let conferred = await PlaceResolver.resolve(extracted, provider: provider, centers: centers, fallback: fallback)
        let merged = PlaceResolver.merge(conferred)
        let details = await PlaceResolver.details(merged.compactMap(\.placeId), provider: provider)
        matches = PlaceMatcher.match(merged, places: board, lists: lists, city: city, region: region, details: details)
        listChoice = Dictionary(uniqueKeysWithValues: matches.compactMap { m in m.suggestedListId.map { (m.id, $0) } })
        // Já marcados: o que foi conferido e não está no board. O resto fica desmarcado ("manter").
        included = Set(matches.filter { $0.existing == nil && $0.located }.map(\.id))
        selectedId = nil
        phase = matches.isEmpty ? .needsText("Li a legenda, mas não achei nome de lugar. Cola o trecho com o nome:") : .done
    }

    /// Volta pro campo do link (o texto fica pra editar).
    func reset() {
        phase = .idle
        matches = []
        caption = nil
        listChoice = [:]
        included = []
        selectedId = nil
        perPlaceLists = false
        placesChecked = false
    }

    func toggle(_ id: String) {
        if included.contains(id) { included.remove(id) } else { included.insert(id) }
    }

    /// Escolhe a lista dos marcados de uma vez ("Lista · Must eat").
    func setList(_ listId: String) {
        for match in includedMatches { listChoice[match.id] = listId }
    }

    /// Lista de um lugar só ("um por lugar…").
    func setList(_ listId: String, for id: String) {
        listChoice[id] = listId
    }

    static func fallbackCenter(city: City?, region: Region) -> CLLocationCoordinate2D {
        city.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? region.defaultCenter
    }

    /// Média dos lugares do board na mesma área; sem nenhum, o centro da cidade.
    static func center(area: String, board: [Place], city: City?, region: Region) -> CLLocationCoordinate2D {
        let key = PlaceMatcher.normalize(area)
        let inArea = board.filter { $0.area.map(PlaceMatcher.normalize) == key }
        guard !inArea.isEmpty else { return fallbackCenter(city: city, region: region) }
        let lat = inArea.map(\.lat).reduce(0, +) / Double(inArea.count)
        let lng = inArea.map(\.lng).reduce(0, +) / Double(inArea.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var stepLines: [(done: Bool, text: String)] {
        guard let resolved else { return [] }
        var lines: [(Bool, String)] = []
        switch resolved.source {
        case .maps: lines.append((caption != nil, "Link do Maps lido · nome e coordenada"))
        case .text: lines.append((true, "Texto lido"))
        default:
            let what = resolved.source == .youtube ? "título e descrição do vídeo" : "legenda do post"
            lines.append((caption != nil, caption != nil ? "Legenda lida · \(what)" : "Lendo a \(what)…"))
        }
        if caption != nil {
            let n = matches.count
            let via = extractedVia.map { " · \($0)" } ?? ""
            lines.append((n > 0, (n == 1 ? "1 lugar encontrado" : "\(n) lugares encontrados") + via))
        }
        return lines
    }
}
