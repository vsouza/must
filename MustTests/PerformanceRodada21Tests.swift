import CoreLocation
import Foundation
import Testing
@testable import Must

/// Rodada 21 · fatia 1 (performance): medições por prints (sem asserção de tempo, depende da máquina).
/// Os números vão pro QA.md, seção "Rodada 21 · fatia 1".
@MainActor
struct PerformanceRodada21Tests {
    private let here = CLLocation(latitude: 35.6812, longitude: 139.7671)
    private let now = fixtureAt("2026-11-15T19:00:00+09:00")

    private func jpPlaces() -> [Place] {
        (0..<103).map { i in
            let p = Place(id: "jp\(i)", name: "Lugar \(i)", cityId: i % 2 == 0 ? "fixtureTokyo" : "kyoto",
                          lat: 35.68 + Double(i % 7) * 0.002, lng: 139.76 + Double(i % 5) * 0.002)
            p.hours = i % 3 == 0 ? fixtureLateBarHours() : fixtureDinnerHours()
            return p
        }
    }

    /// Mesmo trabalho que a Início fazia por `body` (pinos do mapa): `openState` + um `MapPin` por lugar.
    private func buildPins(_ places: [Place], now: Date) -> [MapPin] {
        places.map { p in
            let open: PinOpenState
            switch p.openState(at: now, timeZone: fixtureTokyo) {
            case .open: open = .open
            case .closed: open = .closed
            case .unknown: open = .unknown
            }
            return MapPin(id: "must-\(p.id)", coordinate: p.coordinate, kind: .unplanned(kanji: "A", color: .eat, open: open),
                          placeId: p.id, layer: .unplanned)
        }
    }

    /// Início: o que o `body` antigo montava (HomeModel por body) × o HomeState (calculado no gatilho).
    @Test func medeInicioAntesEDepois() {
        let places = jpPlaces()
        let passes = 50
        let clock = ContinuousClock()
        var sink = 0

        let before = clock.measure {
            for _ in 0..<passes {
                let m = HomeModel(places: places, expenses: [], days: [], trip: nil, region: .jp, now: now, location: here)
                sink += m.openNearby.count + m.nearbyLine.count + m.tomorrowLine.count + Int(m.spentToday)
                sink += m.next == nil ? 0 : 1
            }
        }

        let state = HomeState()
        let refresh = clock.measure {
            state.refresh(HomeState.Inputs(region: .jp, now: now, trip: nil, places: places, expenses: [], days: [],
                                           location: here, tomorrowWeather: nil, nowTemp: nil))
        }
        let reads = clock.measure {
            for _ in 0..<passes {
                sink += state.openNearbyCount + state.dateLine.count + state.cityLine.count + state.pick.count
                    + state.tomorrow.count + (state.day == nil ? 0 : 1) + Int(state.spentToday)
            }
        }

        print("MEDIDA R21 · Início · antes (HomeModel montado por body, \(passes) bodies × 103 lugares): \(before)")
        print("MEDIDA R21 · Início · depois (HomeState.refresh no gatilho, 1×): \(refresh)")
        print("MEDIDA R21 · Início · depois (leitura do estado por body, \(passes)×): \(reads), recálculos \(state.refreshCount)")
        #expect(sink >= 0)
    }

    /// `PlaceHours.weekMinute` é chamado a cada `openState` e a cada linha de horário.
    @Test func medeWeekMinute() {
        let clock = ContinuousClock()
        let n = 20_000
        var sink = 0
        let t = clock.measure {
            for i in 0..<n {
                sink += PlaceHours.weekMinute(now.addingTimeInterval(Double(i) * 60), in: fixtureTokyo).minute
            }
        }
        print("MEDIDA R21 · PlaceHours.weekMinute · \(n) chamadas: \(t)")
        #expect(sink >= 0)
    }

    /// Pinos do mapa: a view montava a lista a cada `body` (`scene` e `nearby`: 2 montagens por body).
    @Test func medePinosAntes() {
        let places = jpPlaces()
        let passes = 50
        let clock = ContinuousClock()
        var sink = 0
        let t = clock.measure {
            for _ in 0..<passes {
                for _ in 0..<2 { sink += buildPins(places, now: now).count }
            }
        }
        print("MEDIDA R21 · Mapa pinos · antes (2 montagens por body, \(passes) bodies × 103 lugares): \(t)")
        #expect(sink > 0)
    }

    /// Depois: `PinsMemo` monta uma vez por chave; os 2 acessos por body são leituras.
    @Test func medePinosDepois() {
        let places = jpPlaces()
        let passes = 50
        let clock = ContinuousClock()
        let memo = PinsMemo()
        let key = PinsMemo.Key(revision: PlacesRevision.of(places), minute: Int(now.timeIntervalSinceReferenceDate / 60),
                               timeZone: fixtureTokyo.identifier, today: [], tomorrow: [], focusPlaceId: nil,
                               hasSelection: false, cityName: nil, here: "35.6812,139.7671", walkMaxKm: 1.5)
        var sink = 0
        let t = clock.measure {
            for _ in 0..<passes {
                for _ in 0..<2 { sink += memo.pins(for: key) { buildPins(places, now: now) }.count }
            }
        }
        print("MEDIDA R21 · Mapa pinos · depois (PinsMemo, \(passes) bodies × 2 leituras, chave igual): \(t), montagens \(memo.buildCount)")
        #expect(memo.buildCount == 1)
        #expect(sink > 0)
    }
}
