import CoreLocation
import Foundation
import Observation
import SwiftData

/// Política do pré-download (CLAUDE.md, premissa de dados): só no Wi-Fi e fora do Modo de Pouco Dados.
/// No celular, nada: o que está na tela é o que baixa.
enum PrefetchPolicy {
    struct Network: Equatable, Sendable {
        var status: Connectivity.Status
        var wifi: Bool
        var expensive: Bool
    }

    static func allows(_ network: Network) -> Bool {
        network.status == .online && network.wifi && !network.expensive
    }
}

/// Pré-download do dia aceito (prompt 18 · A.5): horários (já estão no `Place`), foto principal de cada parada,
/// previsão da cidade e a checagem do mapa offline. Nunca chama Routes nem Street View (custam cota) e nunca baixa
/// o mapa da cidade (são ~100 MB): só mostra a sugestão. Roda ao aceitar o dia, às 07:00 e quando o Wi-Fi volta,
/// com o app aberto (sem background task).
@MainActor
@Observable
final class DayPrefetch {
    struct Progress: Equatable {
        var date: Date
        var done: Int
        var total: Int
    }

    /// O dia que está baixando agora (pra "salvando… 3/7" na Hoje).
    private(set) var progress: Progress?

    /// O que o pré-download toca. Injetado: o teste roda sem rede.
    struct Sources {
        /// Foto principal da parada: Google (se tem placeId, prompt 19), senão Commons, senão a da lista. `nil`: sem foto.
        /// Erro de rede ou de cota lança: a parada conta como "ainda não" e tenta no próximo Wi-Fi.
        var heroURL: @MainActor (_ place: Place, _ cityName: String, _ commons: Bool) async throws -> URL?
        /// Garante a foto no disco (`PhotoLoader.prefetch`).
        var image: @Sendable (_ url: URL) async -> Bool
        /// Previsão da cidade (cache do Weather, guardada pra Hoje).
        var forecast: @MainActor (_ at: CLLocationCoordinate2D, _ region: Region) async throws -> Void
    }

    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private var inFlight: Set<Date> = []

    init(sources: Sources) {
        self.sources = sources
    }

    /// Fontes reais: foto do Google (pelo `PlacePhotoResolver`, cota e Wi-Fi já na política), Commons de reserva,
    /// `PhotoLoader` e o Weather do `SyncCoordinator`.
    static func live(sync: SyncCoordinator, resolver: PlacePhotoResolver, photos: any PhotoProviding) -> Sources {
        Sources(
            heroURL: { place, cityName, commons in
                if let hero = try await resolver.hero(for: place, cityName: cityName, commonsAllowed: commons, purpose: .prefetch) {
                    return URL(string: hero.url)
                }
                return place.list?.photo?.url.flatMap(URL.init(string:))
            },
            image: { url in await PhotoLoader.prefetch(url) },
            forecast: { at, region in try await sync.prefetchForecast(at: at, region: region) }
        )
    }

    /// Baixa o que o dia aceito pede. `false` quando a política não deixa, não há dia aceito, já está salvo, ou
    /// algum item falhou (o dia fica "salvo 5/7" e tenta de novo no próximo Wi-Fi).
    @discardableResult
    func run(date: Date, context: ModelContext, region: Region, network: PrefetchPolicy.Network) async -> Bool {
        guard PrefetchPolicy.allows(network) else { return false }
        let start = region.calendar.startOfDay(for: date)
        guard !inFlight.contains(start),
              let day = try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == start && $0.accepted })).first,
              day.offlineSavedAt == nil else { return false }
        inFlight.insert(start)
        defer {
            inFlight.remove(start)
            progress = nil
        }

        let trip = try? context.fetch(FetchDescriptor<TripInfo>()).first
        let city = trip?.city(on: start, calendar: region.calendar)
        let center = CLLocationCoordinate2D(latitude: city?.lat ?? region.defaultCenter.latitude,
                                            longitude: city?.lng ?? region.defaultCenter.longitude)
        let cityName = city?.name ?? region.displayName
        let commons = context.settings(for: region).flickrPhotos
        let places = day.orderedStops.compactMap(\.place)
        let total = places.count + 1 // uma foto por parada + a previsão da cidade
        var processed = 0, done = 0
        progress = Progress(date: start, done: 0, total: total)

        for place in places {
            guard !Task.isCancelled else { return false }
            if await photoReady(place, cityName: cityName, commons: commons) { done += 1 }
            processed += 1
            progress = Progress(date: start, done: processed, total: total)
        }
        guard !Task.isCancelled else { return false }
        if (try? await sources.forecast(center, region)) != nil { done += 1 }

        day.offlineDone = done
        day.offlineTotal = total
        day.offlineSavedAt = done == total ? Date() : nil
        try? context.save()
        Log.data.info("dia salvo offline: \(done)/\(total)")
        return done == total
    }

    /// Hoje e amanhã (quando o Wi-Fi volta, às 07:00, ou o app abre no Wi-Fi): o que ainda não está salvo.
    func runPending(context: ModelContext, region: Region, network: PrefetchPolicy.Network, now: Date) async {
        for offset in 0...1 {
            let date = region.calendar.date(byAdding: .day, value: offset, to: now) ?? now
            await run(date: date, context: context, region: region, network: network)
        }
    }

    /// Foto da parada no aparelho. Sem foto nenhuma, conta como pronto (não há o que baixar); erro de rede, não.
    private func photoReady(_ place: Place, cityName: String, commons: Bool) async -> Bool {
        do {
            guard let url = try await sources.heroURL(place, cityName, commons) else { return true }
            return await sources.image(url)
        } catch {
            return false
        }
    }

    /// Próximas 07:00 (no fuso da região) depois de `after`.
    static func nextSevenAM(after: Date, calendar: Calendar) -> Date {
        let today = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: after) ?? after
        if today > after { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}

/// Como a Hoje mostra o pré-download do dia (prompt 18 · A.5).
enum OfflineState: Equatable {
    case running(done: Int, total: Int)
    case saved
    case partial(done: Int, total: Int)
    case waitingWiFi

    static func of(_ day: PlannedDay, progress: DayPrefetch.Progress?) -> OfflineState {
        if let progress, progress.date == day.date { return .running(done: progress.done, total: progress.total) }
        if day.offlineSavedAt != nil { return .saved }
        if day.offlineTotal > 0 { return .partial(done: day.offlineDone, total: day.offlineTotal) }
        return .waitingWiFi
    }
}
