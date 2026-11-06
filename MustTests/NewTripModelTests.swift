import XCTest
@testable import Must

@MainActor
final class NewTripModelTests: XCTestCase {
    private func model() -> NewTripModel {
        NewTripModel(now: { NewTripModel.day(2026, 11, 6) })
    }

    func testNightsSumTripDays() {
        let m = model()
        m.tapDay(NewTripModel.day(2027, 3, 12))
        m.tapDay(NewTripModel.day(2027, 3, 20))
        m.addCity(name: "Lisboa"); m.addCity(name: "Porto")
        XCTAssertEqual(m.draft.tripNights, 8)
        XCTAssertEqual(m.tripDays, 9)
        XCTAssertEqual(m.draft.totalNights, 8)
        XCTAssertTrue(m.nightsCheck.matches)
        m.addCity(name: "Sintra")
        XCTAssertEqual(m.draft.totalNights, 8, "redistribui quando o usuário não mexeu")
        m.setNights(5, cityId: m.draft.cities[0].id)
        XCTAssertFalse(m.nightsCheck.matches)
    }

    func testCityRangesFollowNights() {
        let m = model()
        m.tapDay(NewTripModel.day(2027, 3, 12)); m.tapDay(NewTripModel.day(2027, 3, 20))
        m.addCity(name: "Lisboa"); m.addCity(name: "Porto")
        m.setNights(5, cityId: m.draft.cities[0].id); m.setNights(3, cityId: m.draft.cities[1].id)
        XCTAssertEqual(m.cityRange(at: 1)?.from, NewTripModel.day(2027, 3, 17))
        XCTAssertEqual(m.cityRange(at: 1)?.to, NewTripModel.day(2027, 3, 20))
    }

    func testDatesAreOptional() {
        let m = model()
        m.choose(country: NewTripCatalog.country(code: "PT")!)
        m.addCity(name: "Lisboa")
        XCTAssertNil(m.daysUntilStart)
        XCTAssertNil(m.tripDays)
        XCTAssertNil(m.totalBudget)
        XCTAssertTrue(m.nightsCheck.matches)
        XCTAssertEqual(m.draft.countryCode, "PT")
        XCTAssertEqual(m.draft.colorHex, "#0A5C48")
    }

    func testSkippingStepsKeepsDraftValid() {
        let m = model()
        m.chooseManual(name: "Algum lugar")
        for _ in 0..<7 { m.next() }
        XCTAssertEqual(m.step, 8)
        m.next(); XCTAssertEqual(m.step, 9)
        XCTAssertTrue(m.draft.cities.isEmpty && m.draft.flights.isEmpty && m.draft.places.isEmpty)
        XCTAssertEqual(m.placesBreakdown, "")
        XCTAssertFalse(m.contextLine.isEmpty)
    }

    func testRangeTapRules() {
        let m = model()
        m.tapDay(NewTripModel.day(2027, 3, 12)); m.tapDay(NewTripModel.day(2027, 3, 20))
        m.tapDay(NewTripModel.day(2027, 3, 25))
        XCTAssertEqual(m.draft.start, NewTripModel.day(2027, 3, 25)); XCTAssertNil(m.draft.end)
        m.tapDay(NewTripModel.day(2027, 3, 10))
        XCTAssertEqual(m.draft.start, NewTripModel.day(2027, 3, 10))
    }

    func testPortugalExampleDraft() {
        let m = NewTripModel(draft: NewTripModel.sampleDraft, step: 7, now: { NewTripModel.day(2026, 11, 6) })
        XCTAssertEqual(m.draft.cities.map(\.name), ["Lisboa", "Porto"])
        XCTAssertEqual(m.draft.totalNights, 8)
        XCTAssertEqual(m.draft.flights.count, 2)
        XCTAssertEqual(m.draft.places.count, 12)
        XCTAssertEqual(m.placesBreakdown, "9 em Lisboa · 3 no Porto")
        XCTAssertEqual(m.totalBudget, 1080)
        XCTAssertEqual(m.totalInReais ?? 0, 1080 * 6.12, accuracy: 0.01)
        XCTAssertEqual(m.daysUntilStart, 127)
        XCTAssertEqual(m.tilesCommand(for: m.draft.cities[1]), "scripts/tiles.sh \"\" pt-porto")
    }

    func testCreateFailureKeepsDraft() async {
        let m = NewTripModel(draft: NewTripModel.sampleDraft, step: 9)
        await m.create(with: NoTripCreator())
        if case .failed = m.createState {} else { XCTFail("deveria falhar com NoTripCreator") }
        XCTAssertEqual(m.draft.cities.count, 2)
    }

    func testFlightAndLodgingReaders() {
        let legs = NewTripReaders.flightLegs(from: "TP 82 · GRU → LIS · 11 mar 22:05 → 12 mar 11:20", defaultYear: 2027,
                                             fallbackZone: .gmt)
        XCTAssertEqual(legs.count, 1)
        XCTAssertEqual(legs[0].number, "TP 82")
        XCTAssertEqual(legs[0].from, "GRU")
        XCTAssertNotNil(legs[0].departure); XCTAssertNotNil(legs[0].arrival)
        let stay = NewTripReaders.lodging(from: "Hotel: Casa no Chiado\nEndereço: R. Garrett 41\nCheck-in: 12 mar 2027 15:00\nCheck-out: 17 mar 2027 11:00",
                                          zone: TimeZone(identifier: "Europe/Lisbon")!)
        XCTAssertEqual(stay.name, "Casa no Chiado")
        XCTAssertEqual(stay.address, "R. Garrett 41")
        XCTAssertNotNil(stay.checkIn); XCTAssertNotNil(stay.checkOut)
    }
}
