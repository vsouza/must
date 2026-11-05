import CoreLocation
import Foundation
import Observation
import SwiftData

/// Estado da capa (Hoje). Recalcula só nos gatilhos (aparecer, minuto, salvar, posição, voltar pra frente).
/// A foto do bairro sai **só do disco** (ver `CapaPhotoPolicy`).
@MainActor
@Observable
final class CapaState {
    private(set) var content: CapaContent?
    private(set) var plan: DayPlan?
    private(set) var dayNow: DayNow?
    /// Bairro do dia (do plano) ou do GPS.
    private(set) var areaId: String?
    /// Foto do bairro já no aparelho (ou forçada nos prints).
    private(set) var photo: CCPhoto?
    @ObservationIgnored private var photoAreaId: String?

    struct Inputs {
        var region: Region
        var now: Date
        var engine: any DayEngine
        var context: ModelContext
        var trip: TripInfo?
        var expenses: [Expense]
        var currentArea: Area?
        var nowWeather: Forecast.Now?
        var todayWeather: DayWeather?
    }

    func refresh(_ i: Inputs) {
        let region = i.region
        let cal = region.calendar
        let start = cal.startOfDay(for: i.now)
        let plan = i.engine.plan(for: start, region: region, context: i.context)
        self.plan = plan
        dayNow = plan.flatMap { i.engine.now(in: $0, at: i.now) }

        let areas = AreaCatalog.areas(for: region)
        areaId = plan?.area ?? i.currentArea?.id
        let areaName = areaId.flatMap { id in areas.first { $0.id == id }?.name } ?? (plan == nil ? i.currentArea?.name : nil)

        let city = i.trip?.city(on: i.now, calendar: cal)
        let center = CLLocationCoordinate2D(latitude: city?.lat ?? region.defaultCenter.latitude,
                                            longitude: city?.lng ?? region.defaultCenter.longitude)
        let sunset = i.todayWeather?.sunset ?? SunService.day(i.now, center, timeZone: region.timeZone).sunset
        let spent = HomeState.spent(i.expenses, on: i.now, region: region)

        content = CapaContent.build(.init(
            region: region, now: i.now, plan: plan, dayNow: dayNow, areaName: areaName,
            cityName: city?.name ?? Self.cityName(region),
            tripDay: DayText.tripDay(start: i.trip?.start, end: i.trip?.end, on: i.now, calendar: cal),
            tempText: i.nowWeather.map { "\(Int($0.temp.rounded()))°" },
            sky: (i.nowWeather?.code ?? i.todayWeather?.code).map(DayText.sky),
            sunset: sunset,
            spentToday: spent > 0 ? spent : nil
        ))
    }

    static func cityName(_ region: Region) -> String {
        switch region {
        case .bh: "Belo Horizonte"
        case .jp: "Japão"
        case .it: "Roma"
        }
    }

    /// Foto do bairro: Google de um Must do bairro no disco › Commons já escolhida e baixada. Nunca baixa nada,
    /// salvo `forced` (prints com `-capaFoto`), que pode escolher e baixar a do Commons uma vez.
    func loadPhoto(region: Region, places: [Place], services: Services, forced: Bool) async {
        guard let areaId else { photo = nil; return }
        guard areaId != photoAreaId || photo == nil else { return }
        photoAreaId = areaId
        let refs = places.map(HomeState.areaPlace)
        let index = AreaIndex.build(areas: AreaCatalog.areas(for: region), places: refs, openIds: [])
        guard let entry = index.entry(areaId) else { photo = nil; return }
        let byId = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let candidates = entry.placeIds.compactMap { id in
            byId[id].map { AreaHeroes.Candidate(name: $0.name, coordinate: $0.coordinate, placeId: $0.placeId, photoRefs: $0.photoRefs) }
        }
        if let google = AreaHeroes.googleOnDisk(candidates) { photo = google; return }
        if let saved = await DiskCache.shared.stale(AreaHeroes.cacheKey(region: region, areaId: areaId)),
           let commons = try? JSONDecoder().decode(CCPhoto.self, from: saved),
           await DiskCache.shared.exists("photo|\(commons.largeURL ?? commons.url)") {
            photo = commons
            return
        }
        guard forced else { photo = nil; return }
        photo = await AreaHeroes(photos: services.photos).photo(region: region, area: entry.area, candidates: candidates,
                                                                 cityName: region.displayName)
    }
}
