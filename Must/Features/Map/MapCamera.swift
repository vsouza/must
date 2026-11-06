import CoreLocation
import Foundation
import Observation

/// Decisão de abertura do mapa (prompt 11): perto → escala de bairro; nada a 500 m → enquadra você + o mais perto.
enum MapFocus: Equatable {
    case neighborhood(center: MapCameraCommand.Coordinate)
    case nearest(Target)

    struct Target: Equatable {
        var placeId: String
        var coordinate: MapCameraCommand.Coordinate
        var meters: CLLocationDistance
        var isNextStop: Bool
    }

    var target: Target? { if case .nearest(let t) = self { t } else { nil } }
}

/// Um pino candidato a "mais perto".
struct MapCandidate: Equatable {
    var placeId: String
    var coordinate: CLLocationCoordinate2D
    var isNextStop: Bool

    static func == (a: Self, b: Self) -> Bool {
        a.placeId == b.placeId && a.isNextStop == b.isNextStop
            && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }
}

enum MapCameraPlanner {
    static let nearRadius: CLLocationDistance = 500
    /// A próxima parada de hoje ganha do pino mais perto se estiver a menos de 3× a distância dele.
    static let nextStopFactor = 3.0

    static func focus(here: CLLocation, candidates: [MapCandidate]) -> MapFocus {
        let measured = candidates.map { ($0, here.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))) }
        guard let nearest = measured.min(by: { $0.1 < $1.1 }) else {
            return .neighborhood(center: .init(here.coordinate))
        }
        if nearest.1 <= nearRadius { return .neighborhood(center: .init(here.coordinate)) }
        var pick = nearest
        if let next = measured.first(where: { $0.0.isNextStop }), next.1 < nearest.1 * nextStopFactor { pick = next }
        return .nearest(.init(placeId: pick.0.placeId, coordinate: .init(pick.0.coordinate), meters: pick.1, isNextStop: pick.0.isNextStop))
    }
}

/// Quem manda na câmera: reavalia ao abrir, ao andar > 100 m, ao ligar/desligar camada e ao marcar 済;
/// nunca mexe enquanto o usuário arrasta nem nos 20 s depois de um gesto.
@MainActor
@Observable
final class MapCameraController {
    static let moveThreshold: CLLocationDistance = 100
    static let gestureHold: TimeInterval = 20
    /// Folgas do enquadramento: busca + legenda + aviso em cima, sheet embaixo (o prompt pede 170/300 medidos no
    /// PNG; aqui o aviso e a sheet são um pouco mais altos, então a folga acompanha).
    static let fitTop: CGFloat = 290
    static let fitBottom: CGFloat = 340

    private(set) var focus: MapFocus?
    /// A linha de distância só aparece depois que a câmera para.
    private(set) var showsDistanceLine = false
    private(set) var command: MapCameraCommand?

    @ObservationIgnored private var lastLocation: CLLocation?
    @ObservationIgnored private var lastGesture: Date?
    @ObservationIgnored private var gestureActive = false
    @ObservationIgnored private var lineTask: Task<Void, Never>?

    var canMove: Bool {
        !gestureActive && (lastGesture.map { Date().timeIntervalSince($0) > Self.gestureHold } ?? true)
    }

    func userGestured() {
        gestureActive = true
        lastGesture = Date()
    }

    func cameraIdle() {
        if gestureActive { lastGesture = Date() }
        gestureActive = false
    }

    /// A linha aparece quando a animação de 600 ms termina.
    private func revealLine(after seconds: Double) {
        lineTask?.cancel()
        showsDistanceLine = false
        let target = focus?.target?.placeId
        lineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.focus?.target?.placeId == target, target != nil else { return }
            self.showsDistanceLine = true
        }
    }

    private func hideLine() {
        lineTask?.cancel()
        showsDistanceLine = false
    }

    /// `force`: abertura, voltar pro app, camada, 済 ou ⌖. Sem `force`, só se andou > 100 m.
    func evaluate(here: CLLocation?, candidates: [MapCandidate], fallback: CLLocationCoordinate2D, force: Bool, animated: Bool = true) {
        guard let here else {
            if focus == nil { neighborhood(fallback, animated: animated) }
            return
        }
        if !force, let lastLocation, here.distance(from: lastLocation) < Self.moveThreshold { return }
        guard canMove else { return }
        lastLocation = here
        let next = MapCameraPlanner.focus(here: here, candidates: candidates)
        guard next != focus || force else { return }
        focus = next
        switch next {
        case .neighborhood(let center):
            hideLine()
            command = MapCameraCommand(target: .center(lat: center.lat, lng: center.lng, widthMeters: MapView.neighborhoodWidth),
                                       animated: animated)
        case .nearest(let target):
            command = MapCameraCommand(target: .fit(points: [.init(here.coordinate), target.coordinate],
                                                    top: Self.fitTop, bottom: Self.fitBottom, sides: 56), animated: animated)
            revealLine(after: animated ? 0.65 : 0.15)
        }
    }

    /// ⌖: esquece o último gesto e volta ao automático.
    func resumeAuto(here: CLLocation?, candidates: [MapCandidate], fallback: CLLocationCoordinate2D) {
        lastGesture = nil
        gestureActive = false
        evaluate(here: here, candidates: candidates, fallback: fallback, force: true)
    }

    /// `300`: força a escala de bairro (e segura o automático como se fosse um gesto).
    func forceNeighborhood(_ center: CLLocationCoordinate2D) {
        neighborhood(center, animated: true)
        lastGesture = Date()
    }

    /// Centraliza num lugar (busca, prints) sem mudar o foco automático; segura o automático por 20 s.
    func show(_ coordinate: CLLocationCoordinate2D, widthMeters: Double = MapView.neighborhoodWidth, animated: Bool = true) {
        command = MapCameraCommand(target: .center(lat: coordinate.latitude, lng: coordinate.longitude, widthMeters: widthMeters),
                                   animated: animated)
        focus = .neighborhood(center: .init(coordinate))
        hideLine()
        lastGesture = Date()
    }

    /// Card do pino (prompt 27 §2.a): a câmera não pula — só desliza o pino pra cima do card, sem mudar o zoom nem o foco
    /// automático; segura o automático por 20 s (como um gesto).
    func reveal(_ coordinate: CLLocationCoordinate2D, top: CGFloat, bottom: CGFloat) {
        command = MapCameraCommand(target: .reveal(lat: coordinate.latitude, lng: coordinate.longitude, top: top, bottom: bottom))
        lastGesture = Date()
    }

    /// Resultados da busca: enquadra você + os 3 entre a busca (em cima) e o card (embaixo). Segura o automático.
    func fit(_ points: [CLLocationCoordinate2D], top: CGFloat, bottom: CGFloat) {
        guard !points.isEmpty else { return }
        command = MapCameraCommand(target: .fit(points: points.map { .init($0) }, top: top, bottom: bottom, sides: 48))
        hideLine()
        lastGesture = Date()
    }

    private func neighborhood(_ center: CLLocationCoordinate2D, animated: Bool) {
        focus = .neighborhood(center: .init(center))
        hideLine()
        command = MapCameraCommand(target: .center(lat: center.latitude, lng: center.longitude, widthMeters: MapView.neighborhoodWidth),
                                   animated: animated)
    }
}
