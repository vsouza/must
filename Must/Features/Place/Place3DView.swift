import MapKit
import SwiftUI

/// Lugar › 3D: MapKit com relevo realista (satélite ou mapa), volta de 360° em torno do lugar e Look Around ("Rua")
/// quando a Apple tem cobertura. Grátis, sem chave; precisa de internet (o mapa offline do app é o MapLibre).
struct Place3DView: View {
    let name: String
    let coordinate: CLLocationCoordinate2D
    /// Pra onde a câmera aponta (foto: `PhotoSpot.facing`); sem isso, olha pro norte.
    var heading: Double?

    enum Mode: Hashable { case imagery, standard, street }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .imagery
    @State private var position: MapCameraPosition
    @State private var orbit = 0
    @State private var scene: MKLookAroundScene?
    @State private var checkedScene = false
    /// Sem rede (ou Wi-Fi sem internet: a Look Around não responde em 6 s): aviso discreto sobre o mapa.
    @State private var needsInternet = false

    init(name: String, coordinate: CLLocationCoordinate2D, heading: Double? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.heading = heading
        _position = State(initialValue: .camera(Self.camera(coordinate, heading: heading)))
    }

    static func camera(_ c: CLLocationCoordinate2D, heading: Double?) -> MapCamera {
        MapCamera(centerCoordinate: c, distance: 1100, heading: heading ?? 0, pitch: 60)
    }

    var body: some View {
        ZStack {
            Color.must.bg.ignoresSafeArea()
            if mode == .street, let scene {
                LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: false)
                    .ignoresSafeArea()
            } else {
                map.ignoresSafeArea()
            }
            VStack {
                topBar
                if needsInternet { offlineNote.padding(.top, 10) }
                Spacer()
                controls
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .task { await loadScene() }
    }

    /// Look Around pela rede. Offline: aviso na hora. Sem resposta em 6 s (Wi-Fi sem internet): mesmo aviso.
    private func loadScene() async {
        guard Connectivity.current != .offline else {
            needsInternet = true
            checkedScene = true
            return
        }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, !checkedScene else { return }
            needsInternet = true
        }
        do {
            scene = try await MKLookAroundSceneRequest(coordinate: coordinate).scene
            needsInternet = false
        } catch {
            // Erro de rede (não "sem cobertura", que volta nil): o aviso fica.
            needsInternet = true
        }
        watchdog.cancel()
        checkedScene = true
    }

    private var offlineNote: some View {
        HStack(spacing: 10) {
            Text("sem conexão · o 3D precisa de internet").mustMeta().foregroundStyle(Color.must.ink)
            Spacer(minLength: 0)
            Button { needsInternet = false } label: {
                Text("Fechar").font(.must.archivo(13, .semibold)).foregroundStyle(Color.must.ink)
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Fechar aviso")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(cornerRadius: 18)
        .accessibilityElement(children: .contain)
    }

    private var map: some View {
        Map(position: $position, interactionModes: .all) {
            Marker(name, coordinate: coordinate).tint(Color.must.ink)
        }
        .mapStyle(mode == .standard
                  ? .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
                  : .imagery(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .mapCameraKeyframeAnimator(trigger: orbit) { camera in
            KeyframeTrack(\MapCamera.heading) {
                LinearKeyframe(camera.heading + 360, duration: 24)
            }
            KeyframeTrack(\MapCamera.centerCoordinate) {
                LinearKeyframe(coordinate, duration: 24)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            IconButton(.fechar, style: .glass, label: "Fechar") { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.must.archivo(17, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1)
                Micro(mode == .street ? "Look Around · Apple" : "3D · Apple Maps · online")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glass(cornerRadius: 26)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if mode == .street, checkedScene, scene == nil {
                Text("sem Look Around aqui").font(.must.meta).foregroundStyle(Color.must.secondary)
            }
            HStack(spacing: 8) {
                option("Satélite", .imagery)
                option("Mapa", .standard)
                if scene != nil { option("Rua", .street) }
                Spacer(minLength: 0)
                if mode != .street {
                    Button {
                        position = .camera(Self.camera(coordinate, heading: heading))
                        orbit += 1
                    } label: { Pill("Girar", style: .green, icon: .trocar) }
                    .buttonStyle(MustPressStyle())
                    .accessibilityLabel("Dar a volta no lugar")
                }
            }
            .padding(10)
            .glass(cornerRadius: 28)
        }
    }

    private func option(_ title: String, _ value: Mode) -> some View {
        Button {
            withAnimation(.snappy) { mode = value }
        } label: { Pill(title, isOn: mode == value) }
        .buttonStyle(MustPressStyle())
    }
}
