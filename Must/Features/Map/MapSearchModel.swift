import CoreLocation
import Foundation
import Observation

/// O que a busca do mapa lê do aparelho antes de sair do main (rápido, sem rede).
struct MapSearchEnv: Sendable {
    var region: Region
    /// De onde se mede (GPS; sem GPS, o centro da cidade).
    var center: CLLocationCoordinate2D
    var cityGroup: String
    var online: Bool
    var board: [MapBoardEntry]
    var useModel: Bool
    /// O mesmo ambiente do Quero…: "Encaixar hoje" usa o `DayFit` de lá.
    var quero: QueroEnv
    var enterprise: Bool
}

/// Busca "o melhor X perto de mim agora" no topo do mapa (prompt 27 §2.c). Só busca no "buscar"/enter ou num chip;
/// uma de cada vez (a nova cancela a anterior). Board e cache primeiro; a rede, uma vez, só se não bastar.
@MainActor
@Observable
final class MapSearchModel {
    enum Phase: Equatable { case idle, searching, done }

    var text = ""
    private(set) var phase: Phase = .idle
    private(set) var intent: WantIntent?
    /// Chip "aberto agora" (ligado por padrão: fechado nunca entra).
    private(set) var openOnly = true
    private(set) var output: MapSearchOutput?
    /// Linhas do Quero… pros 3 de cima (o "cabe HH:MM" do `DayFit`).
    private(set) var rows: [String: QueroRow] = [:]
    /// O escolhido (pino laranja, alvo do "Encaixar"). Padrão: o primeiro.
    var chosenId: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored let provider: (any WantPlacesSearching)?
    @ObservationIgnored let rated: (any RatedPlacesSearching)?

    init(provider: (any WantPlacesSearching)?, rated: (any RatedPlacesSearching)?) {
        self.provider = provider
        self.rated = rated
    }

    var isActive: Bool { phase != .idle }
    var top: [MapSearchCandidate] { Array(output?.ranked.prefix(MapSearch.shown) ?? []) }
    var chosen: MapSearchCandidate? { top.first { $0.id == chosenId } ?? top.first }

    /// Places real, o fake dos prints ou nenhum; com nota (Enterprise) só com o flag do Vinicius ligado.
    static func providers() -> (plain: (any WantPlacesSearching)?, rated: (any RatedPlacesSearching)?) {
        let plain = QueroView.provider()
        guard PlacesEnterpriseFlag.isOn() else { return (plain, nil) }
        #if DEBUG
        if plain is FakeWantPlaces { return (plain, FakeRatedPlaces()) }
        #endif
        guard plain != nil else { return (nil, nil) }
        return (plain, PlacesService())
    }

    func submit(_ env: MapSearchEnv) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        task?.cancel()
        phase = .searching
        task = Task { [weak self] in
            guard var intent = await WantParser.parse(typed, useModel: env.useModel) else {
                self?.phase = .idle
                return
            }
            // No mapa, "agora" é o padrão: o chip "aberto agora" já vem ligado.
            if intent.when == nil { intent.when = .hoje }
            guard let self, !Task.isCancelled else { return }
            self.openOnly = intent.when != .amanha
            self.intent = intent
            await self.run(intent, env)
        }
    }

    /// Chips editáveis: refazem a busca com a vontade já entendida (cache primeiro, sem parser de novo).
    func cycleQuality(_ env: MapSearchEnv) {
        guard var intent else { return }
        let all = WantQuality.allCases
        intent.quality = all[((all.firstIndex(of: intent.quality) ?? 0) + 1) % all.count]
        rerun(intent, env)
    }

    func cycleRadius(_ env: MapSearchEnv) {
        guard var intent else { return }
        let steps = [1.5, 3.0, 0.5]
        let now = intent.radiusKm ?? output?.radiusKm ?? MapSearch.defaultRadiusKm
        let i = steps.firstIndex { abs($0 - now) < 0.01 } ?? 0
        intent.radiusKm = steps[(i + 1) % steps.count]
        rerun(intent, env)
    }

    func toggleOpen(_ env: MapSearchEnv) {
        guard let intent else { return }
        openOnly.toggle()
        rerun(intent, env)
    }

    func clear() {
        task?.cancel()
        phase = .idle
        intent = nil
        output = nil
        rows = [:]
        chosenId = nil
        openOnly = true
        text = ""
    }

    private func rerun(_ intent: WantIntent, _ env: MapSearchEnv) {
        task?.cancel()
        self.intent = intent
        phase = .searching
        task = Task { [weak self] in await self?.run(intent, env) }
    }

    private func run(_ intent: WantIntent, _ env: MapSearchEnv) async {
        let input = await Self.input(intent, env, openOnly: openOnly)
        let out = await MapSearch.run(input, provider: provider, rated: env.enterprise ? rated : nil)
        guard !Task.isCancelled else { return }
        output = out
        chosenId = out.ranked.first?.id
        let top = Array(out.ranked.prefix(MapSearch.shown))
        rows = Dictionary(QueroModel.rows(top.map(\.result), intent: intent, env: env.quero).map { ($0.id, $0) },
                          uniquingKeysWith: { a, _ in a })
        phase = .done
    }

    /// Junta o cache do "Por perto" e as notas que já estão no aparelho (só dos lugares do board que casam).
    static func input(_ intent: WantIntent, _ env: MapSearchEnv, openOnly: Bool) async -> MapSearchInput {
        let nearby = await MapRatings.nearbyBatch(lat: env.center.latitude, lng: env.center.longitude, region: env.region)
        let words = MapSearch.keywords(intent, category: WantCategory.of(intent))
        var board = env.board
        for i in board.indices {
            let p = board[i].place
            guard !p.done, MapSearch.contains("\(p.name) \(p.sub ?? "") \(p.notes)", any: words) else { continue }
            board[i].rating = await MapRatings.known(placeId: p.id, name: p.name, region: env.region, googlePlaceId: p.placeId,
                                                      nearby: nearby)
        }
        return MapSearchInput(intent: intent, region: env.region, center: env.center, cityGroup: env.cityGroup, online: env.online,
                              board: board, nearby: nearby, now: env.quero.now, openOnly: openOnly, enterprise: env.enterprise)
    }

    // MARK: Textos

    /// LÁMEN · ABERTO AGORA · MELHOR NOTA · ATÉ 1,5 KM (+ OFFLINE · SÓ O SEU BOARD).
    var chips: [(id: String, text: String)] {
        guard let intent else { return [] }
        var out: [(String, String)] = [("object", intent.display)]
        out.append(("open", openOnly ? "aberto agora" : "qualquer hora"))
        out.append(("quality", Self.qualityChip(intent.quality)))
        out.append(("radius", "até \(Self.km(output?.radiusKm ?? intent.radiusKm ?? MapSearch.defaultRadiusKm))"))
        // Offline logo depois do objeto: tem que aparecer sem rolar.
        if let output, output.offline {
            out.insert(("offline", output.sources.contains(.places) ? "offline · board e cache" : "offline · só o seu board"), at: 1)
        }
        return out
    }

    static func qualityChip(_ q: WantQuality) -> String {
        switch q {
        case .melhor: "melhor nota"
        case .barato: "mais barato"
        case .qualquer: "mais perto"
        }
    }

    /// "Melhor agora" / "Mais barato agora" / "Mais perto agora".
    var title: String {
        switch intent?.quality ?? .qualquer {
        case .melhor: "Melhor agora"
        case .barato: "Mais barato agora"
        case .qualquer: "Mais perto agora"
        }
    }

    /// "3 de 11 · por nota".
    var countLine: String {
        guard let output else { return "" }
        let how = output.byRating ? "por nota" : (intent?.quality == .barato ? "por preço" : "por distância")
        return "\(min(MapSearch.shown, output.ranked.count)) de \(output.ranked.count) · \(how)"
    }

    /// 1,5 → "1,5 km"; 3 → "3 km"; 0,5 → "500 m".
    static func km(_ value: Double) -> String {
        if value < 1 { return "\(Int((value * 1000).rounded())) m" }
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded)) km" : String(format: "%.1f km", rounded).replacingOccurrences(of: ".", with: ",")
    }

    /// "tsukemen · 4,4 ★ · até 15:00 · no seu board".
    static func meta(_ c: MapSearchCandidate, locale: Locale) -> String {
        var parts: [String] = []
        if let sub = c.sub { parts.append(sub) }
        if let rating = c.rating { parts.append("\(rating.formatted(.number.precision(.fractionLength(1)).locale(locale))) ★") }
        if let until = c.result.until { parts.append("até \(until)") } else if c.openNow == true { parts.append("aberto agora") }
        parts.append(c.onBoard ? "no seu board" : (c.result.origin == .places && c.result.boardPlaceId == nil ? "indicado" : "perto"))
        return parts.joined(separator: " · ")
    }
}
