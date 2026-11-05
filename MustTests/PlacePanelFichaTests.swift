import CoreLocation
import Foundation
import Testing
@testable import Must

/// Ficha do Lugar v8 (prompt 23 §2 · 09, prompt 24 §3): nome local só quando é outra escrita, coperto em Roma,
/// âncora de museu com o turno.
@MainActor
struct PlacePanelFichaTests {
    func place(_ id: String, name: String, local: String? = nil, notes: String = "", price: Double? = nil, queue: Int? = nil) -> Place {
        let p = Place(id: id, name: name, cityId: "tokyo1", lat: 35.6873, lng: 139.6994)
        p.nameLocal = local
        p.notes = notes
        p.price = price
        p.queueMinutes = queue
        return p
    }

    @Test func localNameOnlyWhenItIsAnotherScript() {
        let fuunji = place("j05", name: "Fuunji", local: "風雲児", notes: "Tsukemen.")
        #expect(PlaceFicha.localLine(fuunji) == "風雲児 · mostre ao atendente · tsukemen")
        let enzo = place("r02", name: "Da Enzo al 29", local: "Da Enzo al 29", notes: "Não aceita reserva de noite. Cacio e pepe.")
        #expect(PlaceFicha.localLine(enzo) == "cacio e pepe")
    }

    @Test func fichaHasSixCellsAtMostAndCopertoInRome() {
        let enzo = place("r02", name: "Da Enzo al 29", notes: "Pedir a carbonara. Só cash.", price: 30, queue: 40)
        let here = CLLocation(latitude: 35.69, longitude: 139.70)
        let jp = PlaceFicha.cells(enzo, region: .jp, now: Date(), here: here, walkMaxKm: 1.5, queueFirst: false)
        #expect(jp.count <= 6)
        #expect(jp.contains { $0.label == "pagamento" && $0.value == "só cash" })
        #expect(jp.contains { $0.label == "pedir" && $0.value == "carbonara" })
        let semFoto = PlaceFicha.cells(enzo, region: .jp, now: Date(), here: nil, walkMaxKm: 1.5, queueFirst: true)
        #expect(semFoto.first == PlaceFicha.Cell(label: "fila agora", value: "~40 min"))
        #expect(semFoto.contains { $0.label == "distância" && $0.value == "sem GPS" })
        #expect(PlaceFicha.queueTag(enzo, region: .it) == "sem reserva · fila ~40 min")
        #expect(PlaceFicha.queueTag(enzo, region: .jp) == "fila ~40 min")
    }

    @Test func anchorFromReservationWithTurn() {
        let borghese = place("r46", name: "Galleria Borghese", notes: "Bernini e Caravaggio. Só 2 horas, sem exceção.")
        let at = Date(timeIntervalSince1970: 1_808_000_000)
        borghese.reservation = Reservation(at: at, party: 2, note: "reserva obrigatória · turno de 2 h")
        let anchor = PlaceFicha.anchor(borghese, now: at.addingTimeInterval(-86_400), calendar: Region.it.calendar)
        #expect(anchor?.kind == .reservation)
        #expect(anchor?.minutes == 120)
        #expect(anchor?.people == 2)
        #expect(PlaceFicha.anchor(borghese, now: at.addingTimeInterval(3 * 86_400), calendar: Region.it.calendar) == nil)
        #expect(PlaceFicha.durationText(150) == "2 h 30")
        #expect(PlaceFicha.turnMinutes("Só 2 horas") == 120)
    }
}
