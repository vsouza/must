import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Prompt 15 · C (fatia 6): voos, status (AeroDataBox), cota, checklist e importação.
private enum F {
    final class Token {}

    static let jp = Region.jp
    static let dates = BoardDates(timeZone: Region.jp.timeZone)

    static func container() throws -> ModelContainer {
        try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    static func iso(_ text: String) -> Date {
        // Datas com fuso explícito ("2026-11-14T23:55:00-03:00").
        BoardDates.parseDateTime(text)!
    }

    /// GRU → DOH → HND (LATAM + Qatar), 14–15 nov, em horário local de cada aeroporto.
    static func gruToHnd() -> [FlightSegment] {
        [FlightSegment(number: "LA 8084", from: "GRU", to: "DOH", departs: iso("2026-11-14T23:55:00-03:00"),
                       arrives: iso("2026-11-15T06:20:00+03:00")),
         FlightSegment(number: "QR 0758", from: "DOH", to: "HND", departs: iso("2026-11-15T02:30:00+03:00"),
                       arrives: iso("2026-11-15T19:00:00+09:00"))]
    }

    static func defaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "must-tests-\(UUID().uuidString)")!
        return suite
    }

    /// Sem rede: o Places nunca é chamado.
    struct NoPlaces: PlacesProviding {
        var isConfigured: Bool { false }
        func searchText(_ query: String, near: CLLocationCoordinate2D, radius: Double, languageCode: String) async throws -> [PlaceCandidate] { [] }
        func details(_ placeId: String, languageCode: String) async throws -> PlaceDetails { throw URLError(.notConnectedToInternet) }
    }
}

// MARK: - AeroDataBox

struct AeroDataBoxParserTests {
    /// Forma real da resposta (`/flights/number/LA8084/…`): lista, `revisedTime` e portão quando há.
    static let sample = Data("""
    [{"number":"LA 8084","status":"Expected",
      "departure":{"airport":{"iata":"GRU"},"scheduledTime":{"local":"2026-11-14 23:55-03:00","utc":"2026-11-15 02:55Z"},
                   "revisedTime":{"local":"2026-11-15 00:15-03:00","utc":"2026-11-15 03:15Z"},"terminal":"3","gate":"B12","checkInDesk":"45-60","baggageBelt":null},
      "arrival":{"airport":{"iata":"DOH"},"scheduledTime":{"local":"2026-11-15 06:20+03:00","utc":"2026-11-15 03:20Z"}}}]
    """.utf8)

    @Test func parsesStatusRevisedTimeTerminalAndGate() throws {
        let report = try #require(try AeroDataBoxParser.parse(Self.sample, departureIATA: "GRU"))
        // "Expected" com partida revista 20 min depois: atrasado.
        #expect(report.status == .delayed)
        #expect(report.departs == F.iso("2026-11-15T00:15:00-03:00"))
        #expect(report.arrives == F.iso("2026-11-15T06:20:00+03:00"))
        #expect(report.terminal == "3")
        #expect(report.gate == "B12")
    }

    @Test func missingFieldsAreTolerated() throws {
        let data = Data(#"[{"number":"LA 8084"}]"#.utf8)
        let report = try #require(try AeroDataBoxParser.parse(data, departureIATA: "GRU"))
        #expect(report.status == nil)
        #expect(report.departs == nil)
        #expect(report.gate == nil)
    }

    @Test func emptyListMeansNoFlight() throws {
        #expect(try AeroDataBoxParser.parse(Data("[]".utf8), departureIATA: "GRU") == nil)
    }

    @Test func singleObjectIsAccepted() throws {
        let data = Data(#"{"number":"LA 8084","status":"Arrived","departure":{"airport":{"iata":"GRU"}}}"#.utf8)
        let report = try #require(try AeroDataBoxParser.parse(data, departureIATA: "GRU"))
        #expect(report.status == .landed)
    }

    @Test func picksTheEntryThatDepartsFromTheAirportAsked() throws {
        let data = Data("""
        [{"number":"LA 8084","status":"Departed","departure":{"airport":{"iata":"GRU"}}},
         {"number":"LA 8084","status":"Canceled","departure":{"airport":{"iata":"CNF"}}}]
        """.utf8)
        let report = try #require(try AeroDataBoxParser.parse(data, departureIATA: "GRU"))
        #expect(report.status == .departed)
    }

    @Test func statusMapping() {
        #expect(AeroDataBoxParser.status("Expected", scheduled: nil, revised: nil) == .onTime)
        #expect(AeroDataBoxParser.status("Delayed", scheduled: nil, revised: nil) == .delayed)
        #expect(AeroDataBoxParser.status("Canceled", scheduled: nil, revised: nil) == .cancelled)
        #expect(AeroDataBoxParser.status("CanceledUncertain", scheduled: nil, revised: nil) == .cancelled)
        #expect(AeroDataBoxParser.status("Boarding", scheduled: nil, revised: nil) == .boarding)
        #expect(AeroDataBoxParser.status("EnRoute", scheduled: nil, revised: nil) == .departed)
        #expect(AeroDataBoxParser.status("Unknown", scheduled: nil, revised: nil) == .scheduled)
        #expect(AeroDataBoxParser.status(nil, scheduled: nil, revised: nil) == nil)
    }
}

struct FlightPolicyTests {
    static let now = F.iso("2026-11-13T10:00:00+09:00")

    static func leg(departsIn hours: Double, status: FlightStatus = .scheduled, fetchedMinutesAgo: Double? = nil) -> FlightSegment {
        let departs = now.addingTimeInterval(hours * 3600)
        return FlightSegment(number: "LA 8084", from: "GRU", to: "DOH", departs: departs, status: status,
                             statusFetchedAt: fetchedMinutesAgo.map { now.addingTimeInterval(-$0 * 60) })
    }

    @Test func noQueryMoreThan24hBeforeDeparture() {
        #expect(FlightPolicy.shouldQuery(Self.leg(departsIn: 30), now: Self.now, hasSource: true, usedThisMonth: 0, blocked: false) == false)
    }

    @Test func queriesInsideTheWindow() {
        #expect(FlightPolicy.shouldQuery(Self.leg(departsIn: 10), now: Self.now, hasSource: true, usedThisMonth: 0, blocked: false))
    }

    @Test func cacheOf30MinutesHoldsTheQuery() {
        #expect(FlightPolicy.shouldQuery(Self.leg(departsIn: 10, fetchedMinutesAgo: 10), now: Self.now, hasSource: true, usedThisMonth: 0, blocked: false) == false)
        #expect(FlightPolicy.shouldQuery(Self.leg(departsIn: 10, fetchedMinutesAgo: 31), now: Self.now, hasSource: true, usedThisMonth: 0, blocked: false))
    }

    @Test func contadorAt380Blocks() {
        #expect(FlightPolicy.shouldQuery(Self.leg(departsIn: 10), now: Self.now, hasSource: true, usedThisMonth: 379, blocked: false))
        #expect(FlightPolicy.shouldQuery(Self.leg(departsIn: 10), now: Self.now, hasSource: true, usedThisMonth: 380, blocked: false) == false)
    }

    @Test func blockedMonthStopsEverything() {
        #expect(FlightPolicy.shouldQuery(Self.leg(departsIn: 10), now: Self.now, hasSource: true, usedThisMonth: 0, blocked: true) == false)
    }

    @Test func noKeyNoQuery() {
        #expect(FlightPolicy.shouldQuery(Self.leg(departsIn: 10), now: Self.now, hasSource: false, usedThisMonth: 0, blocked: false) == false)
    }

    @Test func noQueryAfterLanding() {
        #expect(FlightPolicy.shouldQuery(Self.leg(departsIn: 10, status: .landed), now: Self.now, hasSource: true, usedThisMonth: 0, blocked: false) == false)
        // Sem chegada no e-mail: estimativa de 16 h depois da partida.
        #expect(FlightPolicy.shouldQuery(Self.leg(departsIn: -20), now: Self.now, hasSource: true, usedThisMonth: 0, blocked: false) == false)
    }

    @Test func quotaCountsTwoPerCallAndBlocksOnlyThisMonth() {
        let defaults = F.defaults()
        let now = Self.now
        FlightQuota.record(now: now, defaults: defaults)
        FlightQuota.record(now: now, defaults: defaults)
        #expect(FlightQuota.used(now: now, defaults: defaults) == 4)
        FlightQuota.block(now: now, defaults: defaults)
        #expect(FlightQuota.isBlocked(now: now, defaults: defaults))
        // Mês seguinte: volta a contar do zero e não está bloqueado.
        let nextMonth = now.addingTimeInterval(40 * 86_400)
        #expect(FlightQuota.isBlocked(now: nextMonth, defaults: defaults) == false)
        #expect(FlightQuota.used(now: nextMonth, defaults: defaults) == 0)
    }
}

// MARK: - Checklist

@MainActor
struct ChecklistTests {
    @Test func modelsLoadFromTheBundle() {
        let japan = ChecklistTemplates.entries(template: "intl-japan")
        let domestic = ChecklistTemplates.entries(template: "domestic-br")
        #expect(japan.count >= 12)
        #expect(domestic.isEmpty == false)
        #expect(japan.contains { $0.id == "vjw" && $0.autoRule == "entryQR" })
    }

    @Test func gruToHndWithConnectionHasTwelveItems() {
        let items = ChecklistTemplates.items(template: "intl-japan", legs: F.gruToHnd())
        #expect(items.count == 12)
        #expect(items.filter { $0.phase == .h72 }.count == 4)
        #expect(items.filter { $0.phase == .arrival }.count == 3)
    }

    @Test func domesticTripHasNoJapanItems() {
        let legs = [FlightSegment(number: "LA 3553", from: "CNF", to: "GRU", departs: F.iso("2026-11-11T18:25:00-03:00"))]
        let items = ChecklistTemplates.items(template: "domestic-br", legs: legs)
        #expect(items.contains { $0.id == "vjw" } == false)
        #expect(items.contains { $0.id == "conexao" } == false)
        #expect(items.isEmpty == false)
    }

    @Test func checkinIsDueFortyEightHoursBeforeDeparture() throws {
        let items = ChecklistTemplates.items(template: "intl-japan", legs: F.gruToHnd())
        let checkin = try #require(items.first { $0.id == "checkin" })
        #expect(checkin.dueAt == F.gruToHnd()[0].departs.addingTimeInterval(-48 * 3600))
    }

    /// Visit Japan Web marca sozinho quando há WalletItem.entryQR (o item "auto" da Carteira).
    @Test func visitJapanWebMarksItselfWhenEntryQRIsInTheWallet() throws {
        let items = ChecklistTemplates.items(template: "intl-japan", legs: F.gruToHnd())
        let withoutQR = ChecklistRules.applyWallet(items, wallet: [])
        #expect(withoutQR.first { $0.id == "vjw" }?.done == false)

        let qr = WalletItem(kind: .entryQR, name: "Visit Japan Web", qrPayload: "VJW-1")
        let marked = ChecklistRules.applyWallet(items, wallet: [qr])
        #expect(marked.first { $0.id == "vjw" }?.done == true)
        // Só os automáticos mudam; o resto segue como estava.
        #expect(marked.filter(\.done).map(\.id) == ["vjw"])
    }

    @Test func eSIMInTheWalletMarksTheEsimItem() {
        let items = ChecklistTemplates.items(template: "intl-japan", legs: F.gruToHnd())
        let esim = WalletItem(kind: .esim, name: "eSIM Japão")
        #expect(ChecklistRules.applyWallet(items, wallet: [esim]).first { $0.id == "esim-salvo" }?.done == true)
    }

    @Test func autoNeverUnmarksWhatTheUserMarked() {
        var items = ChecklistTemplates.items(template: "intl-japan", legs: F.gruToHnd())
        items[0].done = true
        let after = ChecklistRules.applyWallet(items, wallet: [])
        #expect(after.first { $0.id == "vjw" }?.done == true)
    }
}

// MARK: - Importação e board

@MainActor
struct FlightImportTests {
    /// E-mail LATAM da fatia 3 (texto colado): PNR, duas pernas.
    static let latamText = """
    LATAM Airlines · confirmação da compra
    Código de reserva: XKQ7MP
    Passageiro: VINICIUS SOUZA
    Voo LA 8084 · sáb 14 nov 2026 · 23:55 · São Paulo (GRU) → Doha (DOH)
    Voo QR 0758 · dom 15 nov 2026 · 02:30 · Doha (DOH) → Tóquio (HND)
    Assento 12A · franquia 23 kg
    """

    @Test func latamEmailBecomesAFlightWithTwoLegs() throws {
        let extracted = TicketExtractor.extract(TicketReader.readText(Self.latamText), region: .bh)
        #expect(extracted.kind == .flight)
        var draft = TicketDraft(extracted, region: .bh, now: AppClock.now, sourceLabel: "e-mail")
        draft.kind = .flight
        let flight = try #require(FlightFromTicket.flight(from: draft, region: .bh, order: 0, attachmentName: nil, now: AppClock.now))
        #expect(flight.pnr == "XKQ7MP")
        #expect(flight.carrier == "LATAM")
        #expect(flight.legs.map(\.number) == ["LA 8084", "QR 0758"])
        #expect(flight.legs.map(\.from) == ["GRU", "DOH"])
        #expect(flight.legs.map(\.to) == ["DOH", "HND"])
        #expect(flight.template == "intl-japan")
        #expect(flight.checklist.count == 12)
        #expect(flight.routeLabel == "GRU → DOH → HND")
    }

    @Test func horarioLidoVaiPraHoraDoAeroportoDeOrigem() throws {
        // O leitor lê 23:55 no fuso da região (Brasília); o trecho de Doha sai às 02:30 de lá, não de Brasília.
        let extracted = TicketExtractor.extract(TicketReader.readText(Self.latamText), region: .jp)
        var draft = TicketDraft(extracted, region: .jp, now: AppClock.now, sourceLabel: "e-mail")
        draft.kind = .flight
        let segments = FlightFromTicket.segments(from: draft, region: .jp)
        let first = try #require(segments.first)
        #expect(FlightFormat.time(first.departs, zone: FlightFormat.zone("GRU", fallback: .current)) == "23:55")
    }

    @Test func saveWritesAFlightAndNothingElse() throws {
        let container = try F.container()
        let model = TicketImportModel()
        model.configure(context: container.mainContext, region: .bh, provider: F.NoPlaces())
        let extracted = TicketExtractor.extract(TicketReader.readText(Self.latamText), region: .bh)
        var draft = TicketDraft(extracted, region: .bh, now: AppClock.now, sourceLabel: "e-mail")
        draft.kind = .flight
        model.draft = draft
        #expect(model.canSave)
        try model.save()
        #expect(container.mainContext.flights().count == 1)
        #expect(container.mainContext.walletItems().isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Place>()) == 0)
    }
}

@MainActor
struct SeedFlightTests {
    static func seed() throws -> Board {
        try BoardCodec.decode(Data(contentsOf: Region.jp.seedURL(in: Bundle(for: F.Token.self))!))
    }

    @Test func legacyFlightEventsBecomeOneBookingWithThreeLegs() throws {
        let container = try F.container()
        let ctx = container.mainContext
        let board = try Self.seed()
        #expect(board.events?.filter { $0.kind == .flight }.count == 3)
        try BoardCodec(context: ctx, region: .jp).import(board: board)
        let flights = ctx.flights()
        #expect(flights.count == 1)
        let legs = try #require(flights.first).legs
        #expect(legs.map(\.number) == ["LA 3553", "LA 8180", "LA 7464"])
        #expect(legs.map(\.from) == ["CNF", "GRU", "JFK"])
        #expect(legs.map(\.to) == ["GRU", "JFK", "HND"])
        // Nenhum voo ficou como evento solto.
        #expect(try ctx.fetchCount(FetchDescriptor<TripEvent>()) == 0)
    }

    @Test func importingTheSeedTwiceDoesNotDuplicateFlights() throws {
        let container = try F.container()
        let ctx = container.mainContext
        let codec = BoardCodec(context: ctx, region: .jp)
        try codec.import(board: try Self.seed())
        try codec.import(board: try Self.seed())
        #expect(ctx.flights().count == 1)
    }

    @Test func exportCarriesFlightsAndRoundTripsWithoutDuplicates() throws {
        let container = try F.container()
        let ctx = container.mainContext
        let codec = BoardCodec(context: ctx, region: .jp)
        try codec.import(board: try Self.seed())
        let exported = try codec.export()
        #expect(exported.flights?.count == 1)
        #expect(exported.events?.contains { $0.kind == .flight } != true)
        let json = try BoardCodec.encode(exported)
        try codec.import(board: try BoardCodec.decode(json))
        #expect(ctx.flights().count == 1)
        #expect(ctx.flights().first?.legs.count == 3)
    }

    @Test func boardFlightKeepsItsChecklistStateOnRoundTrip() throws {
        let container = try F.container()
        let ctx = container.mainContext
        let codec = BoardCodec(context: ctx, region: .jp)
        let flight = Flight(pnr: "QX7R2A", template: "intl-japan", legs: F.gruToHnd(),
                            checklist: ChecklistTemplates.items(template: "intl-japan", legs: F.gruToHnd()))
        var items = flight.checklist
        items[0].done = true
        flight.checklist = items
        ctx.insert(flight)
        try ctx.save()
        let json = try BoardCodec.encode(try codec.export())
        for old in ctx.flights() { ctx.delete(old) }
        try ctx.save()
        try codec.import(board: try BoardCodec.decode(json))
        let back = try #require(ctx.flights().first)
        #expect(back.pnr == "QX7R2A")
        #expect(back.checklist.first?.done == true)
    }

    @Test func oldTripEventFlightsMigrateAndTheEventsGo() throws {
        let container = try F.container()
        let ctx = container.mainContext
        ctx.insert(TripEvent(at: F.iso("2026-11-11T18:25:00-03:00"), title: "LA3553 · BH → São Paulo", kind: .flight))
        ctx.insert(TripEvent(at: F.iso("2026-11-17T09:12:00+09:00"), title: "Shinkansen → Kyoto", kind: .train))
        try ctx.save()
        try BoardCodec(context: ctx, region: .jp).migrateFlightEvents()
        let flight = try #require(ctx.flights().first)
        #expect(flight.legs.first?.from == "CNF")
        #expect(flight.legs.first?.to == "GRU")
        // O trem continua como evento; o voo virou reserva.
        let events = try ctx.fetch(FetchDescriptor<TripEvent>())
        #expect(events.map(\.title) == ["Shinkansen → Kyoto"])
    }

    @Test func legacyTitleParsesCitiesAndCodes() {
        let leg = FlightRules.legacyLeg(title: "LA3553 · BH → São Paulo", at: Date(timeIntervalSince1970: 0), note: "ok")
        #expect(leg.number == "LA 3553")
        #expect(leg.from == "CNF")
        #expect(leg.to == "GRU")
        #expect(leg.note == "ok")
        let unknown = FlightRules.legacyLeg(title: "voo misterioso", at: Date(timeIntervalSince1970: 0), note: nil)
        #expect(unknown.number == "voo misterioso")
        #expect(unknown.from == "")
    }

    @Test func chainsGroupOnlyConnectingLegs() {
        let a = FlightSegment(number: "LA 1", from: "CNF", to: "GRU", departs: F.iso("2026-11-11T18:25:00-03:00"))
        let b = FlightSegment(number: "LA 2", from: "GRU", to: "JFK", departs: F.iso("2026-11-11T22:50:00-03:00"))
        let c = FlightSegment(number: "LA 9", from: "LIS", to: "MAD", departs: F.iso("2026-11-20T10:00:00+01:00"))
        let chains = FlightChains.bookings(from: [c, b, a])
        #expect(chains.map { $0.map(\.number) } == [["LA 1", "LA 2"], ["LA 9"]])
    }
}

// MARK: - Regras de voo

struct FlightRulesTests {
    @Test func templateFollowsTheRoute() {
        let domestic = [FlightSegment(number: "LA 3553", from: "CNF", to: "GRU", departs: Date())]
        #expect(FlightRules.templateKey(for: domestic) == "domestic-br")
        #expect(FlightRules.templateKey(for: F.gruToHnd()) == "intl-japan")
        #expect(FlightRules.templateLabel("intl-japan", legs: F.gruToHnd()) == "internacional + Japão")
        #expect(FlightRules.templateLabel("intl-japan", legs: [FlightSegment(number: "LA 1", from: "GRU", to: "DOH", departs: Date())]) == "internacional")
    }

    @Test func carrierFromNumber() {
        #expect(FlightRules.carrierCode(of: "LA 8084") == "LA")
        #expect(FlightRules.carrierName("LA") == "LATAM")
        #expect(FlightRules.compactNumber("LA 8084") == "LA8084")
    }

    @Test func leaveForAirportIsThreeHoursBeforeInternational() {
        let departs = F.iso("2026-11-14T23:55:00-03:00")
        // 3 h de antecedência + 60 min de deslocamento (estimativa).
        #expect(FlightRules.leaveForAirport(departs: departs, international: true) == departs.addingTimeInterval(-240 * 60))
        #expect(FlightRules.leaveForAirport(departs: departs, international: false) == departs.addingTimeInterval(-180 * 60))
    }

    @Test func dayFlightsMatchTheDepartureAirportDay() {
        let flight = Flight(pnr: "X", legs: F.gruToHnd(), checklist: [])
        // 14 nov em Tóquio: o trecho sai de GRU no dia 14 (local de GRU).
        let day = BoardDates(timeZone: Region.jp.timeZone).day(from: "2026-11-14")!
        let found = FlightRules.dayFlights([flight], on: day, region: .jp)
        #expect(found.map(\.number) == ["LA 8084"])
        let other = BoardDates(timeZone: Region.jp.timeZone).day(from: "2026-11-16")!
        #expect(FlightRules.dayFlights([flight], on: other, region: .jp).isEmpty)
    }

    @Test func flightIsOverAfterLanding() {
        let flight = Flight(pnr: "X", legs: F.gruToHnd(), checklist: [])
        #expect(flight.isOver(now: F.iso("2026-11-14T12:00:00-03:00")) == false)
        #expect(flight.isOver(now: F.iso("2026-11-16T12:00:00+09:00")) == true)
    }
}
