import CoreLocation
import Foundation
import Observation
import SwiftData

/// O que o Colar texto precisa do resto do app: board, listas, cidade, Places, fila de saída e o aparelho.
struct ColarContext {
    var board: [Place]
    var lists: [MustList]
    var city: City?
    /// Cidade onde os lugares novos entram (a da cidade de hoje, ou a primeira da viagem).
    var cityId: String
    /// Início da viagem: "Dia 1" vira essa data.
    var tripStart: Date?
    var region: Region
    var knownAreas: [String]
    var provider: any PlacesProviding
    /// Fila de saída do container da região (sem rede, a conferência espera aqui).
    var queue: ModelContext?
    var onDevice: Bool
    /// Lê os links com o leitor do Adicionar (IG/TT/YT/Maps). Desligado nos testes.
    var readLinks: Bool
    /// Ajuste "Reforço com Claude Haiku" (Ajustes). Só entra quando o aparelho acha menos de 2 lugares.
    var cloudBoost: Bool = false
}

/// Estado do "Colar texto" (prompt 18 · E): texto colado → análise → lugares marcados por dia → gravação.
@MainActor
@Observable
final class ColarTextoModel {
    enum Phase: Equatable { case editing, reading, done }

    /// Lugares de um dia sugerido ("Asakusa e Ueno"). `id` = índice do dia; -1 = sem dia.
    struct Group: Identifiable {
        let id: Int
        var title: String
        var number: Int?
        var matches: [MatchedPlace]
    }

    /// Texto como foi colado (o que aparece no campo).
    var text = ""
    private(set) var phase: Phase = .editing
    private(set) var draft: TravelTextDraft?
    private(set) var matches: [MatchedPlace] = []
    /// Lugares marcados (vão pro board, se novos, e pro dia).
    var included: Set<String> = []
    var listChoice: [String: String] = [:]
    /// Dias sugeridos que viram `PlannedDay` no "Adicionar … e criar dia".
    var dayOn: Set<Int> = []
    /// Grupos com mais de três lugares que foram abertos ("toque pra ver").
    var expanded: Set<Int> = []
    private(set) var placesChecked = false
    /// Sem rede: a conferência no Places ficou na fila (`OutboxKind.conferText`).
    private(set) var queued = false
    /// O reforço na nuvem ficou na fila (sem rede). Mostrado junto do "na fila" da conferência.
    private(set) var cloudQueued = false
    /// Estado de cada link colado ("lido · 2 lugares", "na fila").
    private(set) var linkStatus: [String: String] = [:]
    private(set) var key = ""
    /// Texto de exibição (sem marcação de Markdown): é o que o destaque procura.
    private(set) var shown = ""
    /// Dia em foco: o card recolhido começa nele (o último dia sugerido, até o usuário tocar outro).
    private(set) var focusId: Int?

    // MARK: Análise

    /// Lê o texto: aparelho ou regex por bloco, links, conferência no Places (ou fila sem rede), casamento com o board.
    func analyze(_ raw: String, env: ColarContext) async {
        text = raw
        let display = TravelTextParser.displayText(raw)
        guard !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        phase = .reading
        shown = display
        key = TextConference.key(for: display)

        var found = await TravelTextExtractor.analyze(display, onDevice: env.onDevice, knownAreas: env.knownAreas)
        linkStatus = [:]
        if env.readLinks { await readLinks(found.links, into: &found, env: env) }
        cloudQueued = false
        if env.cloudBoost, TravelTextExtractor.needsCloud(found), CloudBoost.isConfigured {
            found = await cloudStep(display, local: found, env: env)
        }

        var places = found.places
        queued = cloudQueued
        placesChecked = false
        if let queue = env.queue, let done = TextConference.done(for: key, context: queue) {
            places = TextConference.apply(done, to: places)
            placesChecked = true
        } else if env.provider.isConfigured, DevOverrides.liveData {
            if Connectivity.current == .offline, let queue = env.queue {
                TextConference.enqueue(places, key: key, context: queue)
                queued = true
            } else {
                let fallback = AddLinkModel.fallbackCenter(city: env.city, region: env.region)
                var centers: [String: CLLocationCoordinate2D] = [:]
                for area in Set(places.compactMap(\.area)) {
                    centers[area] = AddLinkModel.center(area: area, board: env.board, city: env.city, region: env.region)
                }
                places = await PlaceResolver.resolve(places, provider: env.provider, centers: centers, fallback: fallback)
                placesChecked = true
            }
        }
        places = places.map(Self.museumsAsArt)
        found.places = places
        let merged = PlaceResolver.merge(places)
        let details = await PlaceResolver.details(merged.compactMap(\.placeId), provider: env.provider)

        draft = found
        matches = PlaceMatcher.match(merged, places: env.board, lists: env.lists, city: env.city, region: env.region, details: details)
        listChoice = Dictionary(matches.compactMap { m in m.suggestedListId.map { (m.id, $0) } }, uniquingKeysWith: { a, _ in a })
        expanded = []
        focusId = groups.last { $0.id >= 0 }?.id
        dayOn = Set(groups.map(\.id).filter { $0 >= 0 })
        // Sem Places (offline ou sem chave), todo mundo entra marcado; com Places, só o que foi achado no mapa.
        included = Set(matches.filter { !placesChecked || $0.located }.map(\.id))
        for group in groups where group.id >= 0 {
            for m in group.matches.dropFirst(Self.visibleLimit) { included.remove(m.id) }
        }
        phase = .done
    }

    /// Volta pro campo (o texto fica).
    func edit() {
        phase = .editing
    }

    func focus(_ id: Int) {
        focusId = id
    }

    /// Onde o card recolhido começa: o título do dia em foco; sem ele, o primeiro lugar desse dia.
    func snippetStart() -> String.Index {
        guard let draft, let focusId, draft.days.indices.contains(focusId) else { return shown.startIndex }
        if let title = shown.range(of: draft.days[focusId].title, options: [.caseInsensitive]) {
            return title.lowerBound
        }
        let names = matches.filter { $0.extracted.dayIndex == focusId }.map(\.extracted.name)
        return names.compactMap { shown.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])?.lowerBound }.min()
            ?? shown.startIndex
    }

    /// "CHATGPT" quando o texto diz, "IA" quando a abertura é de resposta de assistente; senão nada.
    var origin: String? {
        let folded = TravelTextParser.foldedText(String(text.prefix(160)))
        if TravelTextParser.foldedText(text).contains("chatgpt") { return "CHATGPT" }
        let cues = ["claro!", "certamente", "com certeza", "aqui vai", "aqui esta"]
        return cues.contains { folded.contains($0) } ? "IA" : nil
    }

    /// Contagem com ponto de milhar pt-BR: "1.840".
    static func grouped(_ n: Int) -> String {
        n.formatted(.number.locale(Locale(identifier: "pt_BR")).grouping(.automatic))
    }

    /// Mostra os lugares de um grupo além dos três de cima.
    static let visibleLimit = 3

    // MARK: Grupos e contagens

    /// Lugares por dia sugerido, na ordem do texto. Sem dia no fim.
    var groups: [Group] {
        guard let draft else { return [] }
        var out: [Group] = []
        for (i, day) in draft.days.enumerated() {
            let ms = matches.filter { $0.extracted.dayIndex == i }
            guard !ms.isEmpty else { continue }
            out.append(Group(id: i, title: day.area ?? day.title, number: day.number ?? i + 1, matches: ms))
        }
        let loose = matches.filter { m in m.extracted.dayIndex.map { !draft.days.indices.contains($0) } ?? true }
        if !loose.isEmpty { out.append(Group(id: -1, title: "Sem dia", number: nil, matches: loose)) }
        return out
    }

    /// Números dos dias que vão ser criados (com pelo menos um lugar marcado), em ordem.
    var dayNumbersOn: [Int] {
        groups.filter { $0.id >= 0 && dayOn.contains($0.id) && $0.matches.contains { included.contains($0.id) } }
            .compactMap(\.number).sorted()
    }

    var counts: (eat: Int, see: Int, drink: Int, links: Int, tips: Int) {
        func count(_ colors: [MustColor]) -> Int {
            matches.filter { m in m.extracted.category.map { colors.contains($0) } ?? false }.count
        }
        return (count([.eat]), count([.see, .temple, .art, .photo, .sport]), count([.drink, .coffee]),
                draft?.links.count ?? 0, draft?.tips.count ?? 0)
    }

    /// Dicas que caem num lugar (pra mostrar "dica: …" na linha).
    func tips(for match: MatchedPlace) -> [TravelTip] {
        let names = Self.names(of: match)
        return (draft?.tips ?? []).filter { tip in
            if case .place(let name) = tip.target { return names.contains(PlaceMatcher.normalize(name)) }
            return false
        }
    }

    func toggle(_ id: String) {
        if included.contains(id) { included.remove(id) } else { included.insert(id) }
    }

    func toggleDay(_ id: Int) {
        if dayOn.contains(id) { dayOn.remove(id) } else { dayOn.insert(id) }
    }

    func toggleExpanded(_ id: Int) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Trechos marcados no texto de exibição.
    func spans() -> [ColarTextoHighlight.Span] {
        guard let draft else { return [] }
        let places: [(name: String, style: ColarTextoHighlight.Style)] = matches.flatMap { m in
            let style = Self.style(m.extracted.category)
            return ([m.extracted.name] + m.extracted.aliases).map { (name: $0, style: style) }
        }
        let links = TravelTextParser.linkRanges(in: shown).map {
            ColarTextoHighlight.Link(range: $0.range, label: ColarTextoHighlight.shortLabel($0.url))
        }
        return ColarTextoHighlight.spans(in: shown, links: links, tips: draft.tips.map(\.text), places: places,
                                         areas: draft.days.compactMap(\.area))
    }

    // MARK: Gravação

    /// Grava os marcados (lugares novos no board; dicas nas notas ou na Carteira) e, se `withDays`, cria os dias.
    /// Devolve quantos lugares entraram.
    @discardableResult
    func save(env: ColarContext, sync: SyncCoordinator?, context: ModelContext, withDays: Bool, now: Date = AppClock.now) -> Int {
        guard let draft else { return 0 }
        let region = env.region
        let source = Source(kind: .manual, url: nil, savedAt: BoardDates(timeZone: region.timeZone).dayString(now), caption: nil, author: nil)
        var placeById = PlaceImport.insert(matches, included: included, listChoice: listChoice, lists: env.lists, cityId: env.cityId,
                                           region: region, source: source, sync: sync, context: context)
        for m in matches where included.contains(m.id) {
            if let existing = m.existing { placeById[m.id] = existing }
        }
        let chosen = matches.filter { included.contains($0.id) && placeById[$0.id] != nil }
        for tip in draft.tips {
            applyTip(tip, chosen: chosen, placeById: placeById, context: context, now: now)
        }
        if withDays {
            makeDays(env: env, draft: draft, placeById: placeById, context: context, now: now)
        }
        TextConference.forget(key, context: context)
        TravelTextCloud.forget(key, context: context)
        try? context.save()
        return chosen.count
    }

    private func applyTip(_ tip: TravelTip, chosen: [MatchedPlace], placeById: [String: Place], context: ModelContext, now: Date) {
        switch tip.target {
        case .place(let name):
            let wanted = PlaceMatcher.normalize(name)
            guard let m = chosen.first(where: { Self.names(of: $0).contains(wanted) }), let place = placeById[m.id] else { return }
            Self.note(place, tip.text)
        case .wallet:
            let existing = context.walletItems()
            guard !existing.contains(where: { $0.name == tip.walletName }) else { return }
            context.insert(WalletItem(kind: tip.walletKind, name: tip.walletName, detail: "Do texto colado: \(tip.text)",
                                      order: existing.count, createdAt: now))
        case .general:
            guard let m = chosen.first, let place = placeById[m.id] else { return }
            Self.note(place, tip.text)
        }
    }

    /// Dia N = data do início da viagem + N − 1 (ou hoje, sem viagem). Dia que já existe ganha os lugares no fim.
    private func makeDays(env: ColarContext, draft: TravelTextDraft, placeById: [String: Place], context: ModelContext, now: Date) {
        let cal = env.region.calendar
        let base = cal.startOfDay(for: env.tripStart ?? now)
        let budget = context.settings(for: env.region).perDayBudget
        for (index, day) in draft.days.enumerated() where dayOn.contains(index) {
            let number = day.number ?? index + 1
            guard let date = cal.date(byAdding: .day, value: number - 1, to: base) else { continue }
            let target = date
            let existing = (try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == target })))?.first
            let planned: PlannedDay
            if let existing {
                planned = existing
            } else {
                planned = PlannedDay(date: date, budget: budget, accepted: true)
                context.insert(planned)
            }
            planned.accepted = true
            planned.focusAreaName = planned.focusAreaName ?? day.area
            var order = planned.stops.count
            for m in matches where m.extracted.dayIndex == index && included.contains(m.id) {
                guard let place = placeById[m.id], !planned.stops.contains(where: { $0.place?.id == place.id }) else { continue }
                // Horário sugerido só pra ordenar: 9h, 10h… (a Hoje e o Montar ajustam depois).
                let stop = Stop(place: place, at: date.addingTimeInterval(TimeInterval((9 + order) * 3600)), order: order)
                context.insert(stop)
                planned.stops.append(stop)
                order += 1
            }
        }
    }

    private static func note(_ place: Place, _ text: String) {
        let line = "Dica do texto: \(text)"
        guard !place.notes.contains(line) else { return }
        place.notes = place.notes.isEmpty ? line : place.notes + "\n" + line
    }

    // MARK: Reforço na nuvem

    /// Só com menos de dois lugares no aparelho. Ordem: resposta já na fila → sem rede, põe na fila → rede, uma chamada.
    /// Erro não repete (host cobrado): fica o resultado local e o texto segue normal.
    private func cloudStep(_ display: String, local: TravelTextDraft, env: ColarContext) async -> TravelTextDraft {
        if let queue = env.queue, let data = TravelTextCloud.done(for: key, context: queue),
           let cloud = try? TravelTextExtractor.draft(fromCloud: data, text: display, knownAreas: env.knownAreas) {
            return TravelTextDraft.merge([local, cloud])
        }
        if Connectivity.current == .offline {
            if let queue = env.queue {
                TravelTextCloud.enqueue(display, key: key, context: queue)
                cloudQueued = true
            }
            return local
        }
        do {
            let data = try await CloudBoost.extractText(display)
            let cloud = try TravelTextExtractor.draft(fromCloud: data, text: display, knownAreas: env.knownAreas)
            return TravelTextDraft.merge([local, cloud])
        } catch {
            Log.intelligence.error("reforço na nuvem do texto: \(error.localizedDescription, privacy: .public)")
            return local
        }
    }

    // MARK: Links

    /// Lê os links com o mesmo caminho do Adicionar: legenda guardada, depois rede, depois fila (sem rede).
    private func readLinks(_ urls: [URL], into draft: inout TravelTextDraft, env: ColarContext) async {
        for url in urls {
            let k = url.absoluteString
            var caption: Caption?
            if let queue = env.queue, let ready = Outbox.readyCaption(for: k, context: queue) {
                queue.delete(ready.item)
                try? queue.save()
                caption = ready.caption
            } else if let fake = Self.debugCaption(url) {
                caption = fake
            } else if Connectivity.current == .offline {
                if let queue = env.queue { Outbox.enqueue(.readLink, ref: k, context: queue) }
                linkStatus[k] = "na fila"
                continue
            } else {
                do {
                    caption = try await CaptionFetcher().fetch(LinkResolver.resolve(k))
                } catch {
                    if Outbox.isOffline(error), let queue = env.queue {
                        Outbox.enqueue(.readLink, ref: k, context: queue)
                        linkStatus[k] = "na fila"
                    } else {
                        linkStatus[k] = "sem legenda"
                    }
                    continue
                }
            }
            guard let caption else { continue }
            let found = PlaceExtractor.extract(from: caption, knownAreas: env.knownAreas)
            for place in found where !draft.places.contains(where: { PlaceMatcher.normalize($0.name) == PlaceMatcher.normalize(place.name) }) {
                draft.places.append(place)
            }
            linkStatus[k] = found.isEmpty ? "lido · sem lugar novo" : "lido · \(found.count) \(found.count == 1 ? "lugar" : "lugares")"
        }
    }

    private static func debugCaption(_ url: URL) -> Caption? {
        #if DEBUG
        guard DebugFlags.string("debugPlaces") == "fake" else { return nil }
        return ColarTextoSample.caption(for: url)
        #else
        return nil
        #endif
    }

    // MARK: Helpers

    /// Nomes que um lugar atende no texto (o nome do Places e os que o texto usou).
    static func names(of match: MatchedPlace) -> Set<String> {
        Set(([match.extracted.name] + match.extracted.aliases).map(PlaceMatcher.normalize))
    }

    static func style(_ category: MustColor?) -> ColarTextoHighlight.Style {
        switch category {
        case .eat: .eat
        case .see, .temple, .art, .photo, .sport: .see
        case .drink, .coffee: .drink
        default: .other
        }
    }

    /// Museu e galeria são "Must art" (prompt 13), mesmo quando o Places diz "museum" (`see`).
    static func museumsAsArt(_ place: ExtractedPlace) -> ExtractedPlace {
        var out = place
        let n = TravelTextParser.foldedText(place.name)
        if ["museu", "museum", "galeria", "gallery"].contains(where: { n.contains($0) }) { out.category = .art }
        return out
    }
}
