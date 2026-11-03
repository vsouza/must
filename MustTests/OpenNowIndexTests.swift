import CoreLocation
import Foundation
import Testing
@testable import Must

/// Prompt 18 · A.3: índice de abertos e distâncias que só recalcula nos gatilhos; medição antes/depois.


@MainActor
struct OpenNowIndexTests {
    private let here = CLLocation(latitude: 35.6812, longitude: 139.7671)

    private func places() -> [Place] {
        let a = Place(id: "a", name: "Jantar", cityId: "fixtureTokyo", lat: 35.6812, lng: 139.7671)
        a.hours = fixtureDinnerHours()
        let b = Place(id: "b", name: "Sem horário", cityId: "fixtureTokyo", lat: 35.6820, lng: 139.7680)
        return [a, b]
    }

    @Test func abertosEDistancias() {
        let index = OpenNowIndex()
        let snap = index.snapshot(for: places(), now: fixtureAt("2026-11-15T19:00:00+09:00"), timeZone: fixtureTokyo, location: here)
        #expect(snap.isOpen("a"))
        #expect(!snap.isOpen("b"))
        #expect((snap.distance("a") ?? -1) < 1)
        #expect((snap.distance("b") ?? 0) > 50)
    }

    @Test func recalculaSoNosGatilhos() {
        let index = OpenNowIndex()
        let list = places()
        let t0 = fixtureAt("2026-11-15T19:00:00+09:00")
        _ = index.snapshot(for: list, now: t0, timeZone: fixtureTokyo, location: here)
        #expect(index.recomputeCount == 1)

        // Mesmo minuto, mesma posição, mesmos lugares: nada a refazer.
        _ = index.snapshot(for: list, now: t0.addingTimeInterval(20), timeZone: fixtureTokyo, location: here)
        #expect(index.recomputeCount == 1)

        // Andou 10 m: ainda abaixo do limite de 50 m.
        let nearby = CLLocation(latitude: here.coordinate.latitude + 0.00009, longitude: here.coordinate.longitude)
        _ = index.snapshot(for: list, now: t0.addingTimeInterval(20), timeZone: fixtureTokyo, location: nearby)
        #expect(index.recomputeCount == 1)

        // Andou 300 m: recalcula.
        let far = CLLocation(latitude: here.coordinate.latitude + 0.0027, longitude: here.coordinate.longitude)
        _ = index.snapshot(for: list, now: t0.addingTimeInterval(20), timeZone: fixtureTokyo, location: far)
        #expect(index.recomputeCount == 2)

        // Virou o minuto: recalcula (o aberto pode ter fechado).
        _ = index.snapshot(for: list, now: t0.addingTimeInterval(61), timeZone: fixtureTokyo, location: far)
        #expect(index.recomputeCount == 3)

        // Um lugar foi marcado 済: o conjunto mudou.
        list[0].done = DoneMark(at: t0, spent: nil)
        _ = index.snapshot(for: list, now: t0.addingTimeInterval(61), timeZone: fixtureTokyo, location: far)
        #expect(index.recomputeCount == 4)
    }

    @Test func horarioNovoEntraNaRevisao() throws {
        let before = PlacesRevision.of(places())
        let list = places()
        list[0].hoursData = try JSONEncoder.board(timeZone: .gmt).encode(fixtureLateBarHours())
        #expect(PlacesRevision.of(list) != before)
    }
}

// MARK: - Medição (A.0, sem Instruments: prints)

/// Mede o custo de abrir "abertos agora" pros 103 lugares do seed JP, antes (decodificar o JSON a cada leitura, como
/// o getter antigo) e depois (cache). Os números vão pro QA.md; não há asserção de tempo (depende da máquina).
@MainActor
struct PerformanceMeasureTests {
    private func jpPlaces() throws -> [Place] {
        (0..<103).map { i in
            let p = Place(id: "jp\(i)", name: "Lugar \(i)", cityId: i % 2 == 0 ? "fixtureTokyo" : "kyoto", lat: 35.68, lng: 139.76)
            p.hours = i % 3 == 0 ? fixtureLateBarHours() : fixtureDinnerHours()
            return p
        }
    }

    @Test func aberturaComCacheVersusDecodificacaoAError() throws {
        let places = try jpPlaces()
        let now = fixtureAt("2026-11-15T19:00:00+09:00")
        let passes = 50
        let clock = ContinuousClock()

        // Antes: o getter decodificava o Data a cada leitura.
        var decodes = 0
        let before = clock.measure {
            for _ in 0..<passes {
                for place in places {
                    guard let data = place.hoursData else { continue }
                    decodes += 1
                    if let hours = try? JSONDecoder.board.decode(PlaceHours.self, from: data) {
                        _ = hours.isOpen(at: now, timeZone: fixtureTokyo)
                    }
                }
            }
        }

        // Depois: o `openState` usa o cache do lugar.
        let after = clock.measure {
            for _ in 0..<passes {
                for place in places { _ = place.openState(at: now, timeZone: fixtureTokyo) }
            }
        }

        // Depois, com o índice da tela: uma passada por recálculo, leituras seguintes são grátis.
        let index = OpenNowIndex()
        let indexed = clock.measure {
            for _ in 0..<passes {
                _ = index.snapshot(for: places, now: now, timeZone: fixtureTokyo, location: nil)
            }
        }

        print("MEDIDA · 103 lugares × \(passes) passadas · antes (decodifica a cada leitura): \(before), \(decodes) decodificações")
        print("MEDIDA · 103 lugares × \(passes) passadas · depois (cache por lugar): \(after), 0 decodificações na leitura")
        print("MEDIDA · 103 lugares × \(passes) passadas · depois (OpenNowIndex, recálculo só no gatilho): \(indexed), \(index.recomputeCount) recálculo(s)")
        #expect(index.recomputeCount == 1)
        #expect(places.allSatisfy { $0.hoursMemo.misses <= 1 })
    }
}
