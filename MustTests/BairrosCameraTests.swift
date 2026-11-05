import CoreLocation
import Testing
@testable import Must

/// Câmera inicial da Bairros: sem bairro escolhido e sem você por perto, enquadra a cidade inteira (não só a
/// vizinhança do maior bairro), sem puxar a outra cidade da viagem.
@MainActor
struct BairrosCameraTests {
    private func place(_ id: String, area: String, lat: Double, lng: Double, city: String = "tokyo1") -> Place {
        let p = Place(id: id, name: id, cityId: city, lat: lat, lng: lng)
        p.area = area
        return p
    }

    private func board() -> [Place] {
        [
            place("g1", area: "Ginza", lat: 35.6717, lng: 139.7650), place("g2", area: "Ginza", lat: 35.6720, lng: 139.7660),
            place("g3", area: "Ginza", lat: 35.6712, lng: 139.7640),
            place("s1", area: "Shinjuku", lat: 35.6909, lng: 139.7003),
            place("a1", area: "Asakusa", lat: 35.7148, lng: 139.7967),
            place("k1", area: "Gion", lat: 35.0037, lng: 135.7788, city: "kyoto"),
        ]
    }

    private func points(_ command: MapCameraCommand) -> [MapCameraCommand.Coordinate] {
        if case .fit(let points, _, _, _) = command.target { return points }
        return []
    }

    @Test func withoutAnchorFitsTheWholeCity() {
        let model = BairrosModel(region: .jp)
        model.refresh(places: board(), now: AppClock.now, location: nil, trip: nil, settings: nil)
        let pts = points(model.initialCommand(areaId: nil, near: nil))
        #expect(pts.contains { abs($0.lng - 139.70) < 0.02 }) // Shinjuku
        #expect(pts.contains { abs($0.lng - 139.79) < 0.02 }) // Asakusa
        #expect(!pts.contains { $0.lat < 35.5 }) // Kyoto fica fora
    }

    @Test func nearYouKeepsTheNeighborhood() {
        let model = BairrosModel(region: .jp)
        model.refresh(places: board(), now: AppClock.now, location: nil, trip: nil, settings: nil)
        let here = CLLocation(latitude: 35.7148, longitude: 139.7967) // Asakusa
        let pts = points(model.initialCommand(areaId: nil, near: here))
        #expect(!pts.contains { abs($0.lng - 139.70) < 0.02 }) // Shinjuku (~9 km) não entra
    }
}
