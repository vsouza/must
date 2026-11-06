import CoreLocation
import Foundation
import Observation
import SwiftUI

/// Eventos por cidade (prompt 26 §3, com as correções do orquestrador): Bandsintown e Ticketmaster (chave opcional no
/// `Secrets.plist`; sem chave a fonte some), feeds RSS/Atom públicos (`data/events-sources.json`; nada de HTML) e, 1×/dia
/// por cidade e só com chave, o Haiku completando datas de itens de feed. Tudo vira `ShowEvent` e fica no cache em disco
/// por região (6 h). A capa lê o cache na hora e atualiza em segundo plano; offline e Pouco Dados = só cache.
@MainActor
@Observable
final class EventsService: ShowEventsProviding {
    static let shared = EventsService()

    private(set) var events: [ShowEvent] = []
    private(set) var loadedRegion: Region?
    private(set) var sources: EventsSources

    @ObservationIgnored private let cache: EventsCache
    @ObservationIgnored private let http: HTTP
    @ObservationIgnored private var refreshing: Set<Region> = []
    @ObservationIgnored private var summaries: [String: String] = [:]

    init(sources: EventsSources = .load(), cache: EventsCache = .standard, http: HTTP = HTTP(kind: .prefetch, retries: 1)) {
        self.sources = sources
        self.cache = cache
        self.http = http
    }

    /// Fontes que valem pra esta região (rótulo do rodapé).
    func sourceName(for event: ShowEvent) -> String {
        switch event.source {
        case .bandsintown: "Bandsintown"
        case .ticketmaster: "Ticketmaster"
        case .feed: sources.sourceName(forEventId: event.id) ?? "agenda"
        case .board, .link, .poster: "board"
        }
    }

    /// Fonte de um evento pelo id (`bandsintown:…`, `ticketmaster:…`, `feed:<fonte>:…`).
    func sourceName(forId id: String) -> String? {
        if id.hasPrefix("bandsintown:") { return "Bandsintown" }
        if id.hasPrefix("ticketmaster:") { return "Ticketmaster" }
        return sources.sourceName(forEventId: id)
    }

    // MARK: Leitura (síncrona, só o que já está no aparelho)

    /// Carrega o cache da região (arquivo pequeno). Chamado ao abrir a capa e ao trocar de região.
    func loadCached(region: Region) {
        guard loadedRegion != region else { return }
        loadedRegion = region
        events = cache.read(region)?.events ?? []
        #if DEBUG
        if DebugFlags.string("debugEvents") == "fake" { events = EventsFakes.events(region: region, now: AppClock.now) }
        #endif
    }

    func today(region: Region, at date: Date) -> [ShowEvent] {
        guard loadedRegion == region else { return [] }
        let calendar = region.calendar
        return events.filter { EventsMapping.isOn($0, day: date, calendar: calendar) }
    }

    func upcoming(region: Region, from date: Date, days: Int) -> [ShowEvent] {
        guard loadedRegion == region else { return [] }
        let calendar = region.calendar
        let from = calendar.startOfDay(for: date)
        let to = from.addingTimeInterval(Double(days) * 86_400)
        return events.filter { e in
            guard let start = e.startsAt else { return false }
            return (e.runsUntil ?? start) >= from && start < to
        }
    }

    func events(placeId: String, at date: Date) -> [ShowEvent] { [] }

    // MARK: Atualização (segundo plano)

    /// Busca nas fontes se a política deixar (6 h, Wi-Fi, fora do Pouco Dados). Falha de fonte é ignorada em silêncio.
    func refresh(region: Region, center: CLLocationCoordinate2D, now: Date = AppClock.now, status: Connectivity.Status,
                 wifi: Bool) async {
        loadCached(region: region)
        #if DEBUG
        if DebugFlags.string("debugEvents") == "fake" { return }
        #endif
        let snapshot = cache.read(region)
        guard EventsFetchPolicy.shouldFetch(cache: snapshot, now: now, status: status, wifi: wifi),
              refreshing.insert(region).inserted else { return }
        defer { refreshing.remove(region) }

        var fetched = await withTaskGroup(of: [ShowEvent].self) { group in
            if let id = Secrets.bandsintownAppId {
                group.addTask { await self.fetchBandsintown(id, region: region, center: center, now: now) }
            }
            if let key = Secrets.ticketmasterKey {
                group.addTask { await self.fetchTicketmaster(key, region: region, center: center, now: now) }
            }
            for feed in self.sources.feeds(for: region) {
                group.addTask { await self.fetchFeed(feed, region: region, now: now) }
            }
            var all: [ShowEvent] = []
            for await part in group { all += part }
            return all
        }
        fetched = EventsMapping.dedupe(fetched)
        // Falha geral com cache velho: mantém o velho (melhor que nada) e tenta de novo na próxima.
        if fetched.isEmpty, let snapshot { events = snapshot.events; return }

        var haikuDay = snapshot?.haikuDay
        let today = BoardDates(timeZone: region.timeZone).dayString(now)
        if CloudBoost.isConfigured, haikuDay != today {
            haikuDay = today
            fetched = await completeWithHaiku(fetched, region: region, now: now)
        }
        let ttl = sources.ttl
        cache.write(EventsSnapshot(region: region, fetchedAt: now, expiresAt: now.addingTimeInterval(ttl), events: fetched, haikuDay: haikuDay))
        if loadedRegion == region { events = fetched }
    }

    private func fetchFeed(_ feed: EventsSources.Feed, region: Region, now: Date) async -> [ShowEvent] {
        guard let data = try? await http.get(feed.url, headers: ["Accept": "application/rss+xml, application/atom+xml, text/xml"],
                                             service: "events-feed") else { return [] }
        let items = FeedParser.parse(data)
        let mapped = EventsMapping.feedEvents(items, feed: feed, region: region, now: now, maxAge: sources.maxItemAge)
        for item in items { // resumo pro Haiku (por id do evento)
            if let link = item.link { summaries["feed:\(feed.id):\(EventsMapping.stableHash(link.absoluteString))"] = item.summary }
        }
        return mapped
    }

    private func fetchTicketmaster(_ key: String, region: Region, center: CLLocationCoordinate2D, now: Date) async -> [ShowEvent] {
        var c = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/events.json")!
        c.queryItems = [.init(name: "apikey", value: key),
                        .init(name: "latlong", value: String(format: "%.4f,%.4f", center.latitude, center.longitude)),
                        .init(name: "radius", value: "25"), .init(name: "unit", value: "km"), .init(name: "size", value: "30"),
                        .init(name: "sort", value: "date,asc"),
                        .init(name: "startDateTime", value: ISO8601DateFormatter().string(from: now).replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression))]
        guard let url = c.url, let data = try? await http.get(url, service: "ticketmaster") else { return [] }
        return EventsMapping.ticketmaster(data, now: now)
    }

    private func fetchBandsintown(_ appId: String, region: Region, center: CLLocationCoordinate2D, now: Date) async -> [ShowEvent] {
        var c = URLComponents(string: "https://rest.bandsintown.com/v3/events/search")!
        c.queryItems = [.init(name: "app_id", value: appId),
                        .init(name: "location", value: String(format: "%.4f,%.4f", center.latitude, center.longitude)),
                        .init(name: "radius", value: "25"), .init(name: "date", value: "upcoming")]
        guard let url = c.url, let data = try? await http.get(url, service: "bandsintown") else { return [] }
        return EventsMapping.bandsintown(data, region: region, now: now)
    }

    /// Haiku (1×/dia por cidade): completa a data dos itens de feed que vieram sem. Qualquer erro = segue sem.
    private func completeWithHaiku(_ events: [ShowEvent], region: Region, now: Date) async -> [ShowEvent] {
        let list = EventsHaiku.candidates(events, items: summaries)
        guard !list.isEmpty, let key = Secrets.anthropicKey else { return events }
        var long = http
        long.kind = .long
        guard let data = try? await long.post(CloudBoost.textEndpoint, json: EventsHaiku.requestBody(list),
                                              headers: ["x-api-key": key, "anthropic-version": "2026-10-21"], service: "anthropic"),
              let completed = try? EventsHaiku.apply(data, to: list, now: now, calendar: region.calendar) else { return events }
        let byId = Dictionary(completed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return events.map { byId[$0.id] ?? $0 }
    }
}

private struct EventsServiceKey: EnvironmentKey {
    static var defaultValue: EventsService { MainActor.assumeIsolated { EventsService.shared } }
}

extension EnvironmentValues {
    /// Eventos das fontes (feeds, Bandsintown, Ticketmaster). O "Em cartaz" do agente A pode somar com `showEvents`.
    var eventsFeed: EventsService {
        get { self[EventsServiceKey.self] }
        set { self[EventsServiceKey.self] = newValue }
    }
}

/// Os feeds entram no Em cartaz do board (`BoardShowEvents.merging(source:)`): só o que já está no cache em memória,
/// nunca rede na leitura.
extension EventsService: @MainActor ShowEventSource {
    func events(region: Region, at date: Date) -> [ShowEvent] {
        loadedRegion == region ? events : []
    }
}
