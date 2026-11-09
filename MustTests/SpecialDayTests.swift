import Foundation
import Testing
@testable import Must

/// Problema 7 do relatório do viajante: chegada, troca de cidade e último dia mostram o essencial, sem inventar dado.
@MainActor
struct SpecialDayTests {
    private let region = Region.jp
    private var cal: Calendar { region.calendar }

    private func at(_ day: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    private var tokyo: City {
        City(id: "tokyo1", name: "Tóquio", from: at(11), to: at(15), tz: "Asia/Tokyo", currency: "JPY", lat: 35.68, lng: 139.76,
             lodging: CityLodging(name: "Hotel Gracery", address: "1-19-1 Kabukicho", neighborhood: "Shinjuku", checkIn: at(11, 15), checkOut: at(15, 11)))
    }
    private var kyoto: City {
        City(id: "kyoto", name: "Kyoto", from: at(15), to: at(20), tz: "Asia/Tokyo", currency: "JPY", lat: 35.01, lng: 135.76,
             lodging: CityLodging(name: "Machiya Gion", checkIn: at(15, 15), checkOut: at(20, 10)))
    }
    private var tokyo2: City {
        City(id: "tokyo2", name: "Tóquio", from: at(20), to: at(24), tz: "Asia/Tokyo", currency: "JPY", lat: 35.68, lng: 139.76)
    }
    private var inbound: FlightSegment {
        FlightSegment(number: "LA 8084", from: "GRU", to: "NRT", departs: at(10, 6), arrives: at(11, 15, 40), arrivalTerminal: "2")
    }
    private var outbound: FlightSegment {
        FlightSegment(number: "LA 8085", from: "HND", to: "GRU", departs: at(24, 18, 25), arrives: at(24, 23, 0))
    }

    private func inputs(_ extra: (inout SpecialDay.Inputs) -> Void = { _ in }) -> SpecialDay.Inputs {
        var i = SpecialDay.Inputs(cities: [tokyo, kyoto, tokyo2], legs: [inbound, outbound], tripEnd: at(24))
        extra(&i)
        return i
    }

    @Test func chegadaMostraPousoChecklistHotelEDescanso() throws {
        let list = [ChecklistItem(id: "esim-ativar", phase: .arrival, title: "Ativar o eSIM"),
                    ChecklistItem(id: "suica", phase: .arrival, title: "Recarregar a Suica", note: "saldo anotado", done: true)]
        let day = try #require(SpecialDay.detect(on: at(11, 17), now: at(11, 17), region: region, inputs: inputs { $0.arrivalChecklist = list }))
        #expect(day.kind == .arrival && day.title == "Chegada" && day.light)
        let titles = day.items.map(\.title)
        #expect(titles.first == "Pousou 15:40 · NRT T2")
        #expect(titles.contains("Ativar o eSIM"))
        #expect(titles.contains("Hotel Gracery · Shinjuku · check-in 15h"))
        #expect(day.items.first { $0.id == "hotel" }?.detail == "1-19-1 Kabukicho")
        #expect(titles.last == "Comer perto e descansar")
        #expect(day.items.first { $0.id == "chk-suica" }?.done == true)
    }

    @Test func chegadaSemDadoNaoInventa() throws {
        var bare = tokyo
        bare.lodging = nil
        let day = try #require(SpecialDay.detect(on: at(11, 9), now: at(11, 9), region: region,
                                                 inputs: SpecialDay.Inputs(cities: [bare, kyoto, tokyo2], legs: [inbound], tripEnd: at(24))))
        #expect(!day.items.contains { $0.id == "hotel" })
        #expect(!day.items.contains { $0.id.hasPrefix("trem") })
        #expect(day.items.first?.title == "Pouso 15:40 · NRT T2")
    }

    @Test func trocaDeCidadeTemMalaCheckoutTremECheckin() throws {
        let train = SpecialDay.Train(name: "Nozomi 25 · carro 7", at: at(15, 10, 33), detail: "12A-12B")
        let day = try #require(SpecialDay.detect(on: at(15, 8), now: at(15, 8), region: region, inputs: inputs { $0.trains = [train] }))
        #expect(day.kind == .transfer && day.title == "Troca de cidade")
        let titles = day.items.map(\.title)
        #expect(titles.contains("Mala pronta"))
        #expect(titles.contains("Check-out de Hotel Gracery até 11h"))
        #expect(titles.contains("Trem pra Kyoto · 10:33"))
        #expect(titles.contains("Machiya Gion · check-in 15h"))
        #expect(titles.last == "Depois do trem, o dia é só em Kyoto")
        #expect(day.cityName == "Kyoto")
    }

    @Test func reservaDeTremSoSeForTrem() {
        #expect(SpecialDay.trainBooking(name: "Nozomi 25", note: nil, at: at(15, 10)) != nil)
        #expect(SpecialDay.trainBooking(name: "Udatsu Sushi", note: "omakase", at: at(15, 19)) == nil)
        #expect(SpecialDay.trainBooking(name: "Udatsu Sushi", note: nil, at: nil) == nil)
    }

    @Test func ultimoDiaTemSaiaProAeroportoFicaProFimETaxFree() throws {
        let day = try #require(SpecialDay.detect(on: at(24, 8), now: at(24, 8), region: region,
                                                 inputs: inputs { $0.saveForEnd = ["Teamlab · arte", "Don Quijote"]; $0.taxFree = true }))
        #expect(day.kind == .lastDay && day.title == "Último dia")
        #expect(day.leaveAt != nil)
        let titles = day.items.map(\.title)
        #expect(titles.first?.hasPrefix("Saia pro aeroporto às") == true)
        #expect(titles.contains("Ficou pro fim (2)"))
        #expect(titles.contains("Tax-free: leve o passaporte"))
    }

    @Test func ultimoDiaSemFicaProFimNemTaxFreeNaoMostra() throws {
        let day = try #require(SpecialDay.detect(on: at(24, 8), now: at(24, 8), region: region, inputs: inputs()))
        #expect(!day.items.contains { $0.id == "fim" || $0.id == "taxfree" })
    }

    @Test func diaComumNaoEEspecial() {
        #expect(SpecialDay.detect(on: at(13, 9), now: at(13, 9), region: region, inputs: inputs()) == nil)
    }
}
