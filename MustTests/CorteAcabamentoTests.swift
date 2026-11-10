import CoreLocation
import Foundation
import Testing
@testable import Must

/// Acabamento do corte (prompt 30): linha "Em cartaz" no índice da capa e o arrasto compartilhado da régua.
@MainActor
struct CorteAcabamentoTests {
    private static let region = Region.bh
    private static let here = CLLocationCoordinate2D(latitude: -19.9335, longitude: -43.9385)
    private static var now: Date {
        region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 19, minute: 55)) ?? Date()
    }
    private static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        region.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }
    private static func show(_ id: String, hour: Int, minute: Int = 0, lat: Double? = -19.9335, lng: Double? = -43.9385) -> ShowEvent {
        ShowEvent(id: id, kind: .show, title: "Noite \(id)", venue: "Bar", lat: lat, lng: lng, startsAt: at(hour, minute), source: .bandsintown)
    }

    @Test func semEventoNaoTemLinha() {
        #expect(CorteShowLine.make(events: [], now: Self.now, region: Self.region, here: Self.here) == nil)
        let tomorrow = ShowEvent(id: "t", kind: .show, title: "Amanhã", startsAt: Self.at(20).addingTimeInterval(86_400), source: .feed)
        #expect(CorteShowLine.make(events: [tomorrow], now: Self.now, region: Self.region, here: Self.here) == nil)
    }

    @Test func linhaTemHoraNomeEContagem() throws {
        let line = try #require(CorteShowLine.make(events: [Self.show("b", hour: 22), Self.show("a", hour: 20)], now: Self.now,
                                                   region: Self.region, here: Self.here))
        #expect(line.title == "Noite a") // a mais próxima
        #expect(line.reason == "em cartaz · 2 hoje")
        #expect(line.big.contains("20"))
    }

    @Test func soContaNoNumeralSeEstaAcontecendoPerto() throws {
        // Começa em 5 min, no local: conta.
        let soon = try #require(CorteShowLine.make(events: [Self.show("a", hour: 20)], now: Self.now, region: Self.region, here: Self.here))
        #expect(soon.countsNearby)
        // Começa daqui a 3 h: não conta.
        let late = try #require(CorteShowLine.make(events: [Self.show("a", hour: 23)], now: Self.now, region: Self.region, here: Self.here))
        #expect(!late.countsNearby)
        // Começa em 5 min mas a quilômetros: não conta.
        let far = try #require(CorteShowLine.make(events: [Self.show("a", hour: 20, lat: -19.85, lng: -43.9)], now: Self.now,
                                                  region: Self.region, here: Self.here))
        #expect(!far.countsNearby)
        // Sem coordenada: não dá pra afirmar, não conta.
        let unknown = try #require(CorteShowLine.make(events: [Self.show("a", hour: 20, lat: nil, lng: nil)], now: Self.now,
                                                      region: Self.region, here: Self.here))
        #expect(!unknown.countsNearby)
    }

    @Test func exposicaoEmTemporadaDizHoje() throws {
        let expo = ShowEvent(id: "x", kind: .exhibition, title: "Expo", startsAt: Self.now.addingTimeInterval(-30 * 86_400),
                             runsUntil: Self.now.addingTimeInterval(60 * 86_400), source: .board)
        let line = try #require(CorteShowLine.make(events: [expo], now: Self.now, region: Self.region, here: Self.here))
        #expect(line.big == "hoje" && !line.countsNearby)
    }
}
