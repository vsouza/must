import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Prompt 13: tipos photo / art / sport — dados, regras do solver e migração do board.
private enum K {
    final class Token {}

    static func board(_ region: Region) -> Board {
        try! BoardCodec.decode(Data(contentsOf: region.seedURL(in: Bundle(for: Token.self))!))
    }

    static func catalog(_ region: Region, edit: (inout [SolverPlace]) -> Void = { _ in }) -> [SolverPlace] {
        let b = board(region)
        let lists = Dictionary(uniqueKeysWithValues: b.lists.map { ($0.id, $0) })
        var out = b.places.map { SolverPlace($0, color: lists[$0.listId]?.color ?? .eat, kind: lists[$0.listId]?.kind ?? .place) }
        edit(&out)
        return out
    }

    static let yanaka = CLLocationCoordinate2D(latitude: 35.7270, longitude: 139.7700)
    static let savassi = CLLocationCoordinate2D(latitude: -19.9385, longitude: -43.9343)

    static func request(_ region: Region, day: String, kind: DayKind = .free, city: String, origin: CLLocationCoordinate2D,
                        start: String = "09:30", weather: DayWeather? = nil, budget: Double? = nil) -> DayRequest {
        let d = BoardDates(timeZone: region.timeZone)
        let date = d.day(from: day)!
        return DayRequest(date: date, timeZone: region.timeZone, kind: kind, budget: budget ?? region.defaultBudget * 3,
                          startAt: d.time(start, on: date)!, origin: origin, cityId: city, daysLeftInCity: nil, weather: weather)
    }

    /// Previsão com nuvens/temperatura/UV por hora (06h → 21h).
    static func weather(_ region: Region, day: String, cloud: (Int) -> Int = { _ in 20 }, temp: (Int) -> Double = { _ in 15 },
                        uv: (Int) -> Double = { _ in 2 }) -> DayWeather {
        let d = BoardDates(timeZone: region.timeZone)
        let date = d.day(from: day)!
        let hours = (5...21).map { h in
            HourWeather(time: date.addingTimeInterval(Double(h) * 3600), temp: temp(h), apparent: temp(h), humidity: 60, cloud: cloud(h),
                        visibility: 18000, precipProb: 5, wind: 9, windDir: 45, uv: uv(h), aqi: 38)
        }
        return DayWeather(tempMin: 10, tempMax: 30, code: 1, precipProb: 5, sunrise: nil, sunset: nil, hours: hours)
    }
}

private extension DayProposal {
    func stop(_ id: String) -> ProposedStop? { stops.first { $0.place.id == id } }
    func minute(_ s: ProposedStop) -> Int { Int(s.at.timeIntervalSince(request.date) / 60) }
}

struct ExtrasDataTests {
    @Test func seedsCarryKindsAndExtras() throws {
        let jp = K.board(.jp)
        #expect(jp.lists.first { $0.id == "photo" }?.kind == .photo)
        #expect(jp.lists.first { $0.id == "see" }?.color == .temple)
        let moriyama = try #require(jp.places.first { $0.id == "j20" })
        let art = try #require(moriyama.extra?.art)
        #expect(art.priceAdult == 1400 && art.lastEntryMinutes == 30 && art.sessions.count == 2)
        #expect(art.sessions[1].soldOut)
        let cal = Region.jp.calendar
        let day26 = BoardDates(timeZone: Region.jp.timeZone).day(from: "2026-11-26")!
        #expect(art.daysLeft(from: day26, calendar: cal) == 4)
        #expect(art.isRunning(on: day26, calendar: cal))
        #expect(!art.isRunning(on: BoardDates(timeZone: Region.jp.timeZone).day(from: "2026-12-01")!, calendar: cal))
        #expect(jp.places.first { $0.id == "j18" }?.extra?.photo?.facing == 248)

        let bh = K.board(.bh)
        let lagoa = try #require(bh.places.first { $0.id == "p28" }?.extra?.sport)
        #expect(lagoa.activity == .run && lagoa.distanceKm == 7 && lagoa.tempMax == 28 && lagoa.uvMax == 6)
        #expect(lagoa.estimatedMinutes == 42)
        // "2026-11-16" em BH (UTC−3) continua sendo o dia 16, não o 15.
        let mostra = try #require(bh.places.first { $0.id == "p26" }?.extra?.art)
        let nov16 = BoardDates(timeZone: Region.bh.timeZone).day(from: "2026-11-16")!
        #expect(mostra.daysLeft(from: nov16, calendar: Region.bh.calendar) == 0)
    }

    @MainActor @Test func oldBoardGainsNewKindsOnce() throws {
        let container = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        // Board antigo: só as listas "place" do seed.
        var old = K.board(.jp)
        old.lists = old.lists.filter { ($0.kind ?? .place) == .place }
        old.places = old.places.filter { p in old.lists.contains { $0.id == p.listId } }
        try BoardCodec(context: ctx, region: .jp).import(board: old)
        let before = try ctx.fetchCount(FetchDescriptor<Place>())

        try RegionStore.seedIfEmpty(ctx, region: .jp, bundle: Bundle(for: K.Token.self))
        let lists = try ctx.fetch(FetchDescriptor<MustList>())
        #expect(lists.count == 8)
        #expect(lists.first { $0.id == "art" }?.kind == .art)
        let after = try ctx.fetchCount(FetchDescriptor<Place>())
        #expect(after == before + 6) // j14 (teamLab, agora art) + j18…j22
        try RegionStore.seedIfEmpty(ctx, region: .jp, bundle: Bundle(for: K.Token.self))
        #expect(try ctx.fetchCount(FetchDescriptor<Place>()) == after)
    }
}

struct PhotoDayTests {
    @Test func photoDayFollowsTheLight() throws {
        let w = K.weather(.jp, day: "2026-11-15")
        let p = DaySolver.solve(K.request(.jp, day: "2026-11-15", kind: .photo, city: "tokyo1", origin: K.yanaka, weather: w),
                                catalog: K.catalog(.jp))
        let sun = SunService.day(p.request.date.addingTimeInterval(12 * 3600), K.yanaka, timeZone: Region.jp.timeZone)
        let first = try #require(p.stops.first)
        #expect(DateInterval(start: sun.goldenAM!.start.addingTimeInterval(-60), end: sun.goldenAM!.end).contains(first.at), "primeira parada fora do golden da manhã: \(first.place.name)")
        let museum = try #require(p.stops.first { $0.place.kind == .art })
        #expect((11 * 60..<15 * 60).contains(p.minute(museum)))
        #expect(museum.reason == "hora do sol alto = museu")
        let yanaka = try #require(p.stop("j18"))
        #expect(abs(yanaka.at.timeIntervalSince(sun.goldenPM!.start)) < 30 * 60)
        #expect(yanaka.reason == "golden")
        let nippori = try #require(p.stop("j19"))
        #expect(sun.bluePM!.contains(nippori.at) || abs(nippori.at.timeIntervalSince(sun.bluePM!.start)) < 60)
        #expect(nippori.reason == "hora azul")
        #expect(p.stops.contains { $0.place.role == .eat && $0.window == .lunch })
    }

    @Test func cloudyGoldenDropsTheSpot() {
        let w = K.weather(.jp, day: "2026-11-15", cloud: { $0 >= 14 ? 80 : 20 })
        let p = DaySolver.solve(K.request(.jp, day: "2026-11-15", kind: .photo, city: "tokyo1", origin: K.yanaka, weather: w),
                                catalog: K.catalog(.jp))
        #expect(p.stop("j18") == nil)
        #expect(p.reason(for: "j18")?.contains("nublado") == true)
    }
}

struct ArtRulesTests {
    @Test func endingSoonIsPrioritizedAndExplained() throws {
        let p = DaySolver.solve(K.request(.jp, day: "2026-11-26", city: "tokyo1", origin: K.yanaka), catalog: K.catalog(.jp))
        let moriyama = try #require(p.stop("j20"))
        #expect(moriyama.reason == "termina em 4 dias")
        #expect(p.explanation.contains("termina em 4 dias"))
    }

    @Test func endedSeasonStaysOut() {
        let p = DaySolver.solve(K.request(.jp, day: "2026-12-01", city: "tokyo1", origin: K.yanaka), catalog: K.catalog(.jp))
        #expect(p.stop("j20") == nil)
        #expect(p.reason(for: "j20") == "temporada acabou")
    }

    @Test func lastEntryIsRespected() {
        // Começando 17:45 (última entrada 17:30 no domingo): não entra.
        let p = DaySolver.solve(K.request(.jp, day: "2026-11-15", city: "tokyo1", origin: K.yanaka, start: "17:45"), catalog: K.catalog(.jp))
        #expect(p.stop("j20") == nil)
    }

    @Test func boughtTicketIsAnAnchor() throws {
        let catalog = K.catalog(.jp) { places in
            if let i = places.firstIndex(where: { $0.id == "j20" }) { places[i].extra?.art?.sessions[0].bought = true }
        }
        let p = DaySolver.solve(K.request(.jp, day: "2026-11-18", city: "tokyo1", origin: K.yanaka), catalog: catalog)
        let talk = try #require(p.stop("j20"))
        #expect(talk.isAnchor)
        #expect(p.minute(talk) == 19 * 60)
    }
}

struct SportRulesTests {
    /// Domingo em BH: 20° às 6h subindo até 31° às 11h; UV forte a partir das 10h.
    static let sunday = K.weather(.bh, day: "2026-11-01",
                                  temp: { h in [5: 19, 6: 20, 7: 22, 8: 23, 9: 25, 10: 28, 11: 31, 12: 31, 13: 32, 14: 31][h] ?? 26 },
                                  uv: { h in [9: 4, 10: 6, 11: 8, 12: 10, 13: 10, 14: 9, 15: 7][h] ?? 1 })

    @Test func earlyMorningRunEnters() throws {
        let p = DaySolver.solve(K.request(.bh, day: "2026-11-01", city: "bh", origin: K.savassi, start: "07:00", weather: Self.sunday),
                                catalog: K.catalog(.bh))
        let run = try #require(p.stop("p28"))
        #expect(p.minute(run) < 9 * 60 + 30)
        #expect(run.reason.hasPrefix("janela boa"))
    }

    @Test func noonIsTooHot() {
        let p = DaySolver.solve(K.request(.bh, day: "2026-11-01", city: "bh", origin: K.savassi, start: "12:00", weather: Self.sunday),
                                catalog: K.catalog(.bh))
        #expect(p.stop("p28") == nil)
    }

    @Test func scoreAndWindow() throws {
        let spot = SportSpot(activity: .run)
        let hours = Self.sunday.hours
        #expect(SportScore.isGood(hours.first { $0.temp == 23 }!, spot: spot))
        #expect(SportScore.level(hours.first { $0.temp == 31 }!, spot: spot) == 4)
        let at740 = hours[0].time.addingTimeInterval(2 * 3600 + 40 * 60)
        let until = try #require(SportScore.goodUntil(hours, from: at740, spot: spot))
        #expect(Calendar.current.dateComponents(in: Region.bh.timeZone, from: until).hour == 10)
        #expect(DaySolver.sportRejection(spot, at: hours[0].time.addingTimeInterval(7 * 3600), hourly: hours) == "quente · 31°")
    }
}

struct EventExtractorTests {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let bh = TimeZone(identifier: "America/Sao_Paulo")!
    static let now = BoardDates(timeZone: tokyo).time("10:00", on: BoardDates(timeZone: tokyo).day(from: "2026-11-01")!)!

    @Test func japaneseMuseumPage() throws {
        let text = "森山大道 回顧展 Daido Moriyama Retrospective 2026.10.3〜2026.11.30 東京都写真美術館 一般 ¥1,400 学生 ¥1,120 最終入場 30 min"
        #expect(EventExtractor.looksLikeEvent(text, url: nil))
        let art = EventExtractor.parse(text, url: nil, timeZone: Self.tokyo, now: Self.now)
        #expect(art.priceAdult == 1400)
        #expect(art.priceStudent == 1120)
        let until = try #require(art.runsUntil)
        #expect(BoardDates(timeZone: .gmt).dayString(until) == "2026-11-30")
        #expect(art.daysLeft(from: BoardDates(timeZone: Self.tokyo).day(from: "2026-11-26")!, calendar: Region.jp.calendar) == 4)
        #expect(art.lastEntryMinutes == 30)
    }

    @Test func symplaLinkInBH() throws {
        let url = URL(string: "https://www.sympla.com.br/evento/mostra-fotografia/123")!
        let text = "Mostra de fotografia em cartaz até 16/11. Inteira R$ 20, meia R$ 10."
        #expect(EventExtractor.looksLikeEvent(text, url: url))
        let art = EventExtractor.parse(text, url: url, timeZone: Self.bh, now: Self.now)
        #expect(art.priceAdult == 20 && art.priceStudent == 10)
        #expect(art.ticketURL == url && art.needsBooking)
        #expect(BoardDates(timeZone: .gmt).dayString(try #require(art.runsUntil)) == "2026-11-16")
    }

    @Test func plainRestaurantIsNotAnEvent() {
        #expect(!EventExtractor.looksLikeEvent("Melhor ramen de Nakano, fila de 20 min, vale cada minuto 🍜", url: nil))
        #expect(EventExtractor.runsUntil(in: "〜12月7日まで", timeZone: Self.tokyo, now: Self.now).map { BoardDates(timeZone: .gmt).dayString($0) } == "2026-12-07")
    }
}
