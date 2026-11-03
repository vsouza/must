import Foundation
import SwiftData
import Testing
@testable import Must

/// Pré-download do dia aceito (prompt 18 · A.5): só no Wi-Fi e fora do Pouco Dados, sem Routes nem Street View,
/// e o dia só fica "salvo" quando tudo que ele pede chegou.
@MainActor
struct DayPrefetchTests {
    private final class Token {}

    /// O que o pré-download pediu, na ordem. Qualquer coisa fora de `hero:`, `image:` e `forecast` seria regressão de cota.
    private actor Calls {
        private(set) var events: [String] = []
        func log(_ event: String) { events.append(event) }
    }

    private let bh = Region.bh

    private func container() throws -> ModelContainer {
        let c = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try RegionStore.seedIfEmpty(c.mainContext, region: .bh, bundle: Bundle(for: Token.self))
        return c
    }

    private func startOfNov3() throws -> Date {
        try #require(BoardDates(timeZone: bh.timeZone).day(from: "2026-11-03"))
    }

    /// Dia aceito com duas paradas do seed de BH (Café Nice e Mercado Central).
    private func acceptedDay(_ ctx: ModelContext) throws -> PlannedDay {
        let start = try startOfNov3()
        let day = PlannedDay(date: start, budget: 200, accepted: true)
        ctx.insert(day)
        let places = try ctx.fetch(FetchDescriptor<Place>())
        for (i, id) in ["p07", "p01"].enumerated() {
            let place = try #require(places.first { $0.id == id })
            let stop = Stop(place: place, at: start.addingTimeInterval(Double(i) * 3600), order: i)
            ctx.insert(stop)
            day.stops.append(stop)
        }
        try ctx.save()
        return day
    }

    /// Fontes de mentira: registram o pedido. `photoOK` decide se cada foto chega.
    private func sources(_ calls: Calls, photoOK: @escaping @Sendable (String) -> Bool = { _ in true },
                         forecastOK: Bool = true) -> DayPrefetch.Sources {
        DayPrefetch.Sources(
            heroURL: { place, _, commons in
                await calls.log("hero:\(place.id):\(commons)")
                return URL(string: "https://upload.example.org/\(place.id).jpg")
            },
            image: { url in
                await calls.log("image:\(url.lastPathComponent)")
                return photoOK(url.lastPathComponent)
            },
            forecast: { _, _ in
                await calls.log("forecast")
                guard forecastOK else { throw ServiceError.offline }
            }
        )
    }

    private let wifi = PrefetchPolicy.Network(status: .online, wifi: true, expensive: false)

    // MARK: Política

    @Test func soBaixaNoWiFiForaDoPouco() {
        #expect(PrefetchPolicy.allows(.init(status: .online, wifi: true, expensive: false)))
        #expect(!PrefetchPolicy.allows(.init(status: .online, wifi: false, expensive: true)), "celular não")
        #expect(!PrefetchPolicy.allows(.init(status: .online, wifi: false, expensive: false)), "cabo ou outra rede não")
        #expect(!PrefetchPolicy.allows(.init(status: .constrained, wifi: true, expensive: false)), "Modo de Pouco Dados não")
        #expect(!PrefetchPolicy.allows(.init(status: .offline, wifi: true, expensive: false)), "sem rede não")
        #expect(!PrefetchPolicy.allows(.init(status: .online, wifi: true, expensive: true)), "Wi-Fi medido não")
    }

    @Test func celularNaoBaixaNada() async throws {
        let c = try container(), ctx = c.mainContext
        let day = try acceptedDay(ctx)
        let calls = Calls()
        let ok = await DayPrefetch(sources: sources(calls)).run(
            date: day.date, context: ctx, region: bh, network: .init(status: .online, wifi: false, expensive: true))
        #expect(!ok)
        #expect(await calls.events.isEmpty)
        #expect(day.offlineSavedAt == nil)
    }

    @Test func modoDePoucoDadosNoWiFiNaoBaixa() async throws {
        let c = try container(), ctx = c.mainContext
        let day = try acceptedDay(ctx)
        let calls = Calls()
        let ok = await DayPrefetch(sources: sources(calls)).run(
            date: day.date, context: ctx, region: bh, network: .init(status: .constrained, wifi: true, expensive: false))
        #expect(!ok)
        #expect(await calls.events.isEmpty)
    }

    @Test func semRedeNaoBaixaNada() async throws {
        let c = try container(), ctx = c.mainContext
        let day = try acceptedDay(ctx)
        let calls = Calls()
        let ok = await DayPrefetch(sources: sources(calls)).run(
            date: day.date, context: ctx, region: bh, network: .init(status: .offline, wifi: true, expensive: false))
        #expect(!ok)
        #expect(await calls.events.isEmpty)
    }

    // MARK: Pré-download

    @Test func wiFiBaixaFotosEPrevisaoENaoChamaRotas() async throws {
        let c = try container(), ctx = c.mainContext
        let day = try acceptedDay(ctx)
        let calls = Calls()
        let ok = await DayPrefetch(sources: sources(calls)).run(date: day.date, context: ctx, region: bh, network: wifi)

        #expect(ok)
        // Uma foto por parada (na ordem do roteiro) e a previsão. Sem Routes, sem Street View, sem Google.
        #expect(await calls.events == ["hero:p07:true", "image:p07.jpg", "hero:p01:true", "image:p01.jpg", "forecast"])
        #expect(day.offlineSavedAt != nil)
        #expect(day.offlineDone == 3)
        #expect(day.offlineTotal == 3)
    }

    @Test func fotoQueFalhaDeixaODiaParcialEDaORetryNoProximoWiFi() async throws {
        let c = try container(), ctx = c.mainContext
        let day = try acceptedDay(ctx)
        let prefetch = DayPrefetch(sources: sources(Calls(), photoOK: { $0 != "p01.jpg" }))

        let first = await prefetch.run(date: day.date, context: ctx, region: bh, network: wifi)
        #expect(!first)
        #expect(day.offlineSavedAt == nil)
        #expect(day.offlineDone == 2)
        #expect(day.offlineTotal == 3)
        #expect(OfflineState.of(day, progress: nil) == .partial(done: 2, total: 3))

        // Próximo Wi-Fi: tenta de novo e fecha.
        let second = await DayPrefetch(sources: sources(Calls())).run(date: day.date, context: ctx, region: bh, network: wifi)
        #expect(second)
        #expect(day.offlineSavedAt != nil)
        #expect(OfflineState.of(day, progress: nil) == .saved)
    }

    @Test func diaJaSalvoNaoBaixaDeNovo() async throws {
        let c = try container(), ctx = c.mainContext
        let day = try acceptedDay(ctx)
        let calls = Calls()
        let prefetch = DayPrefetch(sources: sources(calls))
        #expect(await prefetch.run(date: day.date, context: ctx, region: bh, network: wifi))
        let before = await calls.events.count

        #expect(!(await prefetch.run(date: day.date, context: ctx, region: bh, network: wifi)))
        #expect(await calls.events.count == before)
    }

    @Test func diaSemAceiteNaoBaixa() async throws {
        let c = try container(), ctx = c.mainContext
        let calls = Calls()
        let start = try startOfNov3()
        #expect(!(await DayPrefetch(sources: sources(calls)).run(date: start, context: ctx, region: bh, network: wifi)))
        #expect(await calls.events.isEmpty)
    }

    // MARK: 07:00 e estado da Hoje

    @Test func proximaSeteDaManha() throws {
        let cal = bh.calendar
        func at(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) throws -> Date {
            try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second)))
        }
        #expect(DayPrefetch.nextSevenAM(after: try at(3, 6, 0), calendar: cal) == (try at(3, 7, 0)))
        #expect(DayPrefetch.nextSevenAM(after: try at(3, 7, 0), calendar: cal) == (try at(4, 7, 0)), "07:00 em ponto já passou")
        #expect(DayPrefetch.nextSevenAM(after: try at(3, 23, 30), calendar: cal) == (try at(4, 7, 0)))
    }

    @Test func estadoDaHojeSegueOPreDownload() throws {
        let day = PlannedDay(date: try startOfNov3(), budget: 200, accepted: true)
        #expect(OfflineState.of(day, progress: nil) == .waitingWiFi, "aceito e ainda não baixado: no celular, 'salva no Wi-Fi'")
        let running = DayPrefetch.Progress(date: day.date, done: 3, total: 7)
        #expect(OfflineState.of(day, progress: running) == .running(done: 3, total: 7))
        #expect(OfflineState.of(day, progress: .init(date: day.date.addingTimeInterval(86_400), done: 1, total: 7)) == .waitingWiFi,
                "progresso de outro dia não conta")
        day.offlineDone = 5
        day.offlineTotal = 7
        #expect(OfflineState.of(day, progress: nil) == .partial(done: 5, total: 7))
        day.offlineSavedAt = Date()
        #expect(OfflineState.of(day, progress: nil) == .saved)
    }
}
