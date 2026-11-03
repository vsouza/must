import XCTest
@testable import Must

/// Painel do Lugar (prompt 18 · D.20): um painel por lugar, escolhido por função pura.
final class PlacePanelTests: XCTestCase {
    func testReservationWinsOverKindData() {
        let c = PlacePanelChoice.choose(kind: .art, hasReservation: true, hasTicket: true, hasKindData: true)
        XCTAssertEqual(c, .reservation)
    }

    func testTicketAnchorWinsOverKindPanel() {
        let c = PlacePanelChoice.choose(kind: .experience, hasReservation: false, hasTicket: true, hasKindData: true)
        XCTAssertEqual(c, .ticket)
    }

    func testKindPanelWhenNoAnchor() {
        XCTAssertEqual(PlacePanelChoice.choose(kind: .photo, hasReservation: false, hasTicket: false, hasKindData: true), .kind)
        XCTAssertEqual(PlacePanelChoice.choose(kind: .sport, hasReservation: false, hasTicket: false, hasKindData: true), .kind)
    }

    func testKindWithoutDataFallsBackToPlain() {
        XCTAssertEqual(PlacePanelChoice.choose(kind: .art, hasReservation: false, hasTicket: false, hasKindData: false), .plain)
    }

    func testPlainPlaceAlwaysPlain() {
        XCTAssertEqual(PlacePanelChoice.choose(kind: .place, hasReservation: false, hasTicket: false, hasKindData: false), .plain)
        XCTAssertEqual(PlacePanelChoice.choose(kind: .place, hasReservation: false, hasTicket: false, hasKindData: true), .plain)
    }

    func testOrderHintPicksSentenceAboutOrdering() {
        let notes = "Chef fala inglês. Pedir o uni extra. Levar dinheiro — cartão só acima de ¥10k."
        XCTAssertEqual(PlacePanelChoice.orderHint(notes: notes), "Pedir o uni extra")
    }

    func testOrderHintNilWithoutOrdering() {
        XCTAssertNil(PlacePanelChoice.orderHint(notes: "Fila longa no almoço."))
        XCTAssertNil(PlacePanelChoice.orderHint(notes: ""))
    }
}
