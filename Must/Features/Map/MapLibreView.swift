import CoreLocation
import MapLibre
import SwiftUI
import UIKit

/// O que o mapa desenha por cima da base (camadas de runtime + pinos).
struct MapScene {
    var region: Region
    var layers: Set<MapLayer>
    var pins: [MapPin]
    var metro: TransitMap
    /// Rota de hoje: trechos feitos (linha) e por fazer (contas).
    var routeDone: [[CLLocationCoordinate2D]] = []
    var routeFuture: [[CLLocationCoordinate2D]] = []
    /// Rota de amanhã (tracejada fina).
    var routeTomorrow: [[CLLocationCoordinate2D]] = []
    /// Linha de distância você → mais perto (prompt 11); aparece só depois que a câmera para.
    var distanceLine: [CLLocationCoordinate2D]?
    var you: CLLocationCoordinate2D?
    /// Área citada (anel fechado, preenchida a 8% e tracejada): o preview do Adicionar por link.
    var area: [CLLocationCoordinate2D]? = nil
    /// Percurso do Guia do dia (prompt 18 · C.16): trecho de trem na cor da linha, ou a pé (pontilhado).
    var legs: [MapLegPath] = []
}

/// Um trecho do percurso: `color` nil = a pé (pontilhado cinza); senão a cor oficial da linha (`0xRRGGBB`).
struct MapLegPath: Sendable {
    var coordinates: [CLLocationCoordinate2D]
    var color: UInt32?
}

/// Pedido de câmera vindo da tela (cada `id` novo é aplicado uma vez).
struct MapCameraCommand: Equatable {
    enum Target: Equatable {
        /// Centro + largura visível em metros (escala de bairro ≈ 900 m).
        case center(lat: Double, lng: Double, widthMeters: Double)
        /// Enquadra os pontos com folga (topo pela busca/legenda, base pela sheet).
        case fit(points: [Coordinate], top: CGFloat, bottom: CGFloat, sides: CGFloat)
    }

    struct Coordinate: Equatable {
        var lat: Double
        var lng: Double
        init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lng = c.longitude }
        var value: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    }

    var id = UUID()
    var target: Target
    var animated = true
}

/// Estado da câmera devolvido pra tela.
struct MapCameraState: Equatable {
    var center: CLLocationCoordinate2D
    var zoom: Double
    var metersPerPoint: Double
    var widthMeters: Double

    static func == (a: Self, b: Self) -> Bool {
        a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude && a.zoom == b.zoom
    }
}

/// MapLibre Native com o style "papel em relevo" (PMTiles baixado ou lido do R2) e as camadas do Must por cima.
struct MapLibreView: UIViewRepresentable {
    var scene: MapScene
    var command: MapCameraCommand?
    var onCamera: (MapCameraState) -> Void = { _ in }
    /// O usuário começou a mexer no mapa (arrastar, pinçar, toque duplo).
    var onGesture: () -> Void = {}
    /// A câmera parou (depois de gesto ou animação).
    var onIdle: () -> Void = {}
    var onSelect: (MapPin) -> Void = { _ in }
    /// Gestos de arrastar e pinçar. Desligado no preview (só pinos).
    var interactive = true
    /// Direção do aparelho pro cone do "você". Vem de `CompassBridge`, não do `scene`: girar a bússola não redesenha o mapa.
    var headingSink: YouHeadingSink?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero)
        // Antes do delegate: ligar o delegate já dispara regionDidChange, que chama loadStyle.
        context.coordinator.map = map
        map.delegate = context.coordinator
        context.coordinator.attachHeading(headingSink)
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.compassView.isHidden = true
        map.showsScale = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.minimumZoomLevel = 9
        map.maximumZoomLevel = 18.5
        map.backgroundColor = UIColor(red: 0xE9 / 255, green: 0xEB / 255, blue: 0xEF / 255, alpha: 1)
        context.coordinator.loadStyle(near: scene.you ?? scene.region.defaultCenter)
        context.coordinator.observePacks()
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        if c.styleRegion != scene.region { c.loadStyle(near: scene.you ?? scene.region.defaultCenter) }
        c.apply(scene)
        if let command, command.id != c.lastCommand { c.lastCommand = command.id; c.run(command) }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreView
        /// Forte: o delegate do MLNMapView é fraco, então não há ciclo.
        var map: MLNMapView?
        var lastCommand: UUID?
        /// Último heading da bússola (graus), já vindo do `YouHeadingSink`.
        private(set) var youHeading: Double?
        private(set) var styleRegion: Region?
        private var tiles: MapTiles = .none
        private var styleReady = false
        private var annotations: [String: PinAnnotation] = [:]
        private var you: YouAnnotation?
        private var signatures: [String: Int] = [:]
        private var clusterBucket: Int?
        private var moving = false

        init(_ parent: MapLibreView) { self.parent = parent }

        /// Liga a bússola: a cada mudança só o cone do "você" gira (não passa pelo `body` do mapa).
        func attachHeading(_ sink: YouHeadingSink?) {
            sink?.onChange = { [weak self] value in
                guard let self else { return }
                youHeading = value
                refreshYouHeading()
            }
        }

        private func refreshYouHeading() {
            guard let map, let you, let view = map.view(for: you) as? YouView else { return }
            view.setHeading(youHeading.map { $0 - map.direction })
        }

        /// Cidade baixada ou apagada: troca a fonte (R2 ↔ arquivo) sem esperar a câmera mexer.
        /// Observer por seletor: o NotificationCenter solta sozinho quando o coordinator morre.
        func observePacks() {
            NotificationCenter.default.addObserver(self, selector: #selector(packsChanged), name: .mapPacksChanged, object: nil)
        }

        @objc private func packsChanged() {
            guard let map else { return }
            loadStyle(near: map.centerCoordinate)
        }

        // MARK: Style

        func loadStyle(near center: CLLocationCoordinate2D) {
            guard let map else { return }
            let region = parent.scene.region
            let picked = MapTiles.pick(region: region, near: center)
            guard styleRegion != region || picked != tiles else { return }
            styleRegion = region
            tiles = picked
            styleReady = false
            signatures = [:]
            if case .none = picked { Log.data.error("mapa: sem mapa baixado, sem MAP_TILES_URL e sem PROTOMAPS_KEY — só fundo") }
            map.styleURL = MapStyleLoader.styleURL(region: region, tiles: picked)
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            nonisolated(unsafe) let style = style
            MainActor.assumeIsolated {
                addRuntimeLayers(style)
                styleReady = true
                apply(parent.scene)
            }
        }

        nonisolated func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: any Error) {
            let message = error.localizedDescription
            MainActor.assumeIsolated { Log.data.error("mapa: falhou ao carregar — \(message, privacy: .public)") }
        }

        private static let blue = UIColor(Color.must.blue)
        private static let ink = UIColor(Color.must.ink)

        /// Ordem: metrô → estações → amanhã → hoje feito → hoje futuro (contas) → distância.
        private func addRuntimeLayers(_ style: MLNStyle) {
            func source(_ id: String) -> MLNShapeSource {
                let s = MLNShapeSource(identifier: id, shape: nil)
                style.addSource(s)
                return s
            }
            let round = NSExpression(forConstantValue: "round")

            let metro = MLNLineStyleLayer(identifier: "rt-metro", source: source("rt-metro"))
            metro.lineColor = NSExpression(mglJSONObject: ["to-color", ["get", "color"]])
            metro.lineWidth = NSExpression(forConstantValue: 2.5)
            metro.lineCap = round
            metro.lineJoin = round
            style.addLayer(metro)

            let stations = MLNSymbolStyleLayer(identifier: "rt-stations", source: source("rt-stations"))
            stations.minimumZoomLevel = 12.5
            stations.iconImageName = NSExpression(forConstantValue: "station")
            stations.iconAllowsOverlap = NSExpression(forConstantValue: true)
            stations.text = NSExpression(mglJSONObject: ["step", ["zoom"], "", 14.5, ["upcase", ["get", "name"]]])
            let font = parent.scene.region == .jp ? MapStyleLoader.japaneseFont : "Archivo SemiBold"
            stations.textFontNames = NSExpression(forConstantValue: [font])
            stations.textFontSize = NSExpression(forConstantValue: 9)
            stations.textLetterSpacing = NSExpression(forConstantValue: parent.scene.region == .jp ? 0.04 : 0.16)
            stations.textColor = NSExpression(forConstantValue: Self.ink)
            stations.textHaloColor = NSExpression(forConstantValue: UIColor(red: 0xE9 / 255, green: 0xEB / 255, blue: 0xEF / 255, alpha: 1))
            stations.textHaloWidth = NSExpression(forConstantValue: 1.2)
            stations.textAnchor = NSExpression(forConstantValue: "left")
            stations.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 1.1, dy: 0)))
            stations.textOptional = NSExpression(forConstantValue: true)
            style.addLayer(stations)

            // Área citada (preview do Adicionar por link): preenchimento a 8% e contorno tracejado verde.
            let areaSource = source("rt-area")
            let areaFill = MLNFillStyleLayer(identifier: "rt-area-fill", source: areaSource)
            areaFill.fillColor = NSExpression(forConstantValue: PinStyle.green)
            areaFill.fillOpacity = NSExpression(forConstantValue: 0.08)
            style.addLayer(areaFill)
            let areaLine = MLNLineStyleLayer(identifier: "rt-area-line", source: areaSource)
            areaLine.lineColor = NSExpression(forConstantValue: PinStyle.green)
            areaLine.lineOpacity = NSExpression(forConstantValue: 0.35)
            areaLine.lineWidth = NSExpression(forConstantValue: 1.5)
            areaLine.lineDashPattern = NSExpression(forConstantValue: [3, 4])
            style.addLayer(areaLine)

            let tomorrow = MLNLineStyleLayer(identifier: "rt-tomorrow", source: source("rt-tomorrow"))
            tomorrow.lineColor = NSExpression(forConstantValue: Self.blue)
            tomorrow.lineOpacity = NSExpression(forConstantValue: 0.8)
            tomorrow.lineWidth = NSExpression(forConstantValue: 1.5)
            tomorrow.lineDashPattern = NSExpression(forConstantValue: [1, 6])
            tomorrow.lineCap = round
            style.addLayer(tomorrow)

            let done = MLNLineStyleLayer(identifier: "rt-done", source: source("rt-done"))
            done.lineColor = NSExpression(forConstantValue: Self.blue)
            done.lineWidth = NSExpression(forConstantValue: 3.5)
            done.lineCap = round
            done.lineJoin = round
            style.addLayer(done)

            // Contas: traço de comprimento 0 com ponta redonda = círculo do diâmetro da linha (6 pt),
            // um a cada ~14 pt. Fica no espaço da tela, então não precisa reamostrar com o zoom.
            let future = MLNLineStyleLayer(identifier: "rt-future", source: source("rt-future"))
            future.lineColor = NSExpression(forConstantValue: Self.blue)
            future.lineWidth = NSExpression(forConstantValue: 6)
            future.lineDashPattern = NSExpression(forConstantValue: [0, 2.35])
            future.lineCap = round
            future.lineJoin = round
            style.addLayer(future)

            let distance = MLNLineStyleLayer(identifier: "rt-distance", source: source("rt-distance"))
            distance.lineColor = NSExpression(forConstantValue: Self.ink)
            distance.lineWidth = NSExpression(forConstantValue: 1.6)
            distance.lineDashPattern = NSExpression(forConstantValue: [2.5, 3.75])
            style.addLayer(distance)

            // Percurso do Guia (C.16): trem na cor da linha (cor por feature) e a pé pontilhado.
            let legs = MLNLineStyleLayer(identifier: "rt-legs", source: source("rt-legs"))
            legs.lineColor = NSExpression(mglJSONObject: ["to-color", ["get", "color"]])
            legs.lineWidth = NSExpression(forConstantValue: 4)
            legs.lineCap = round
            legs.lineJoin = round
            style.addLayer(legs)
            let walkLegs = MLNLineStyleLayer(identifier: "rt-legs-walk", source: source("rt-legs-walk"))
            walkLegs.lineColor = NSExpression(forConstantValue: UIColor(red: 0x7A / 255, green: 0x7F / 255, blue: 0x87 / 255, alpha: 1))
            walkLegs.lineWidth = NSExpression(forConstantValue: 3)
            walkLegs.lineDashPattern = NSExpression(forConstantValue: [0.2, 2.4])
            walkLegs.lineCap = round
            style.addLayer(walkLegs)
        }

        // MARK: Cena

        func apply(_ scene: MapScene) {
            guard let map else { return }
            if styleReady, let style = map.style { applyLayers(scene, style: style) }
            applyPins(scene, map: map)
            applyYou(scene, map: map)
        }

        private func signature(_ paths: [[CLLocationCoordinate2D]]) -> Int {
            var h = Hasher()
            for path in paths {
                h.combine(path.count)
                for c in path { h.combine(c.latitude); h.combine(c.longitude) }
            }
            return h.finalize()
        }

        private func setShape(_ id: String, _ paths: [[CLLocationCoordinate2D]], style: MLNStyle, attributes: [[String: Any]]? = nil) {
            var h = Hasher()
            h.combine(signature(paths))
            h.combine(attributes?.count ?? 0)
            let sig = h.finalize()
            guard signatures[id] != sig, let source = style.source(withIdentifier: id) as? MLNShapeSource else { return }
            signatures[id] = sig
            let features: [MLNPolylineFeature] = paths.enumerated().compactMap { i, path in
                guard path.count > 1 else { return nil }
                var coords = path
                let f = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
                if let attributes { f.attributes = attributes[i] }
                return f
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }

        private func applyLayers(_ scene: MapScene, style: MLNStyle) {
            let lines = scene.metro.lines.flatMap { line in line.paths.map { (line, $0) } }
            setShape("rt-metro", lines.map(\.1), style: style,
                     attributes: lines.map { ["color": UIColor($0.0.color).hexString, "id": $0.0.id] })
            if signatures["rt-stations"] != scene.metro.stations.count, let source = style.source(withIdentifier: "rt-stations") as? MLNShapeSource {
                signatures["rt-stations"] = scene.metro.stations.count
                source.shape = MLNShapeCollectionFeature(shapes: scene.metro.stations.map { s in
                    let f = MLNPointFeature()
                    f.coordinate = s.coordinate
                    f.attributes = ["name": s.name]
                    return f
                })
            }
            setShape("rt-tomorrow", scene.routeTomorrow, style: style)
            setShape("rt-done", scene.routeDone, style: style)
            setShape("rt-future", scene.routeFuture, style: style)
            setShape("rt-distance", scene.distanceLine.map { [$0] } ?? [], style: style)
            let transit = scene.legs.filter { $0.color != nil }
            setShape("rt-legs", transit.map(\.coordinates), style: style,
                     attributes: transit.map { ["color": String(format: "#%06X", $0.color ?? 0)] })
            setShape("rt-legs-walk", scene.legs.filter { $0.color == nil }.map(\.coordinates), style: style)
            applyArea(scene.area, style: style)

            let visible: [String: Bool] = [
                "rt-metro": scene.layers.contains(.metro), "rt-stations": scene.layers.contains(.metro),
                "rt-tomorrow": scene.layers.contains(.tomorrow),
                "rt-done": scene.layers.contains(.today), "rt-future": scene.layers.contains(.today),
                "rt-distance": true,
                "rt-area-fill": scene.area != nil, "rt-area-line": scene.area != nil,
            ]
            for (id, on) in visible {
                if let layer = style.layer(withIdentifier: id), layer.isVisible != on { layer.isVisible = on }
            }
        }

        private func applyArea(_ ring: [CLLocationCoordinate2D]?, style: MLNStyle) {
            guard let source = style.source(withIdentifier: "rt-area") as? MLNShapeSource else { return }
            var h = Hasher()
            for c in ring ?? [] { h.combine(c.latitude); h.combine(c.longitude) }
            let sig = h.finalize()
            guard signatures["rt-area"] != sig else { return }
            signatures["rt-area"] = sig
            guard var coords = ring, coords.count > 2 else { source.shape = nil; return }
            source.shape = MLNPolygonFeature(coordinates: &coords, count: UInt(coords.count))
        }

        /// Sem plano em z ≤ 13 vira cluster por grade de ~48 pt.
        private func visiblePins(_ scene: MapScene, map: MLNMapView) -> [MapPin] {
            let pins = scene.pins.filter { scene.layers.contains($0.layer) }
            guard map.zoomLevel <= 13 else { return pins }
            let unplanned = pins.filter { if case .unplanned = $0.kind { true } else { false } }
            guard unplanned.count > 1 else { return pins }
            let mpp = map.metersPerPoint(atLatitude: map.centerCoordinate.latitude)
            let cellDegrees = 48 * mpp / 111_000
            var cells: [String: [MapPin]] = [:]
            for pin in unplanned {
                let key = "\(Int(floor(pin.lat / cellDegrees)))|\(Int(floor(pin.lng / cellDegrees)))"
                cells[key, default: []].append(pin)
            }
            let grouped = cells.values.map { group -> MapPin in
                guard group.count > 1 else { return group[0] }
                let lat = group.map(\.lat).reduce(0, +) / Double(group.count)
                let lng = group.map(\.lng).reduce(0, +) / Double(group.count)
                let id = "cluster-" + group.map(\.id).sorted().joined(separator: ",")
                return MapPin(id: id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                              kind: .cluster(count: group.count), placeId: nil, layer: .unplanned)
            }
            return pins.filter { if case .unplanned = $0.kind { false } else { true } } + grouped
        }

        private func applyPins(_ scene: MapScene, map: MLNMapView) {
            let pins = visiblePins(scene, map: map)
            let ids = Set(pins.map(\.id))
            let gone = annotations.filter { !ids.contains($0.key) }
            if !gone.isEmpty {
                map.removeAnnotations(Array(gone.values))
                for key in gone.keys { annotations[key] = nil }
            }
            var added: [PinAnnotation] = []
            for pin in pins {
                if let existing = annotations[pin.id] {
                    guard existing.pin != pin else { continue }
                    existing.pin = pin
                    existing.coordinate = pin.coordinate
                    (map.view(for: existing) as? PinView)?.configure(pin)
                } else {
                    let a = PinAnnotation(pin)
                    annotations[pin.id] = a
                    added.append(a)
                }
            }
            if !added.isEmpty { map.addAnnotations(added) }
        }

        private func applyYou(_ scene: MapScene, map: MLNMapView) {
            guard let here = scene.you else {
                if let you { map.removeAnnotation(you); self.you = nil }
                return
            }
            if let you {
                if you.coordinate.latitude != here.latitude || you.coordinate.longitude != here.longitude { you.coordinate = here }
            } else {
                let a = YouAnnotation()
                a.coordinate = here
                you = a
                map.addAnnotation(a)
            }
            if let you, let view = map.view(for: you) as? YouView {
                view.setHeading(youHeading.map { $0 - map.direction })
            }
        }

        // MARK: Câmera

        func run(_ command: MapCameraCommand) {
            guard let map else { return }
            // Na abertura o MapLibre ainda não tem tamanho: espera o primeiro layout.
            guard map.bounds.width > 0, map.bounds.height > 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self, self.lastCommand == command.id else { return }
                    self.run(command)
                }
                return
            }
            let duration: TimeInterval = command.animated ? 0.6 : 0
            switch command.target {
            case .center(let lat, let lng, let width):
                let mpp = width / Double(map.bounds.width)
                let zoom = log2(40_075_016.686 * cos(lat * .pi / 180) / (512 * mpp))
                move(map, to: CLLocationCoordinate2D(latitude: lat, longitude: lng), zoom: zoom, duration: duration)
            case .fit(let points, let top, let bottom, let sides):
                guard points.count > 1 else { return }
                let (center, zoom) = Self.fit(points.map(\.value), size: map.bounds.size, top: top, bottom: bottom, sides: sides)
                move(map, to: center, zoom: min(zoom, 16.5), duration: duration)
            }
        }

        private func move(_ map: MLNMapView, to center: CLLocationCoordinate2D, zoom: Double, duration: TimeInterval) {
            if duration == 0 {
                map.setCenter(center, zoomLevel: zoom, animated: false)
            } else {
                let altitude = MLNAltitudeForZoomLevel(zoom, 0, center.latitude, map.bounds.size)
                let camera = MLNMapCamera(lookingAtCenter: center, altitude: altitude, pitch: 0, heading: 0)
                map.setCamera(camera, withDuration: duration, animationTimingFunction: CAMediaTimingFunction(name: .easeOut))
            }
        }

        /// Centro e zoom (Web Mercator, mundo de 512 pt no z0) que enquadram os pontos dentro da área livre.
        nonisolated static func fit(_ coords: [CLLocationCoordinate2D], size: CGSize, top: CGFloat, bottom: CGFloat, sides: CGFloat)
            -> (CLLocationCoordinate2D, Double) {
            func world(_ c: CLLocationCoordinate2D) -> CGPoint {
                let x = (c.longitude + 180) / 360 * 512
                let s = sin(c.latitude * .pi / 180)
                let y = (0.5 - log((1 + s) / (1 - s)) / (4 * .pi)) * 512
                return CGPoint(x: x, y: y)
            }
            let pts = coords.map(world)
            let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
            let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
            let availW = max(40, size.width - 2 * sides), availH = max(40, size.height - top - bottom)
            let scale = min(availW / max(maxX - minX, 1e-9), availH / max(maxY - minY, 1e-9))
            let zoom = log2(scale)
            // O conteúdo fica no meio da área livre; o centro da tela desce/sobe a diferença.
            let shift = (size.height / 2 - (top + availH / 2)) / scale
            let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2 + shift
            let lng = cx / 512 * 360 - 180
            let n = Double.pi - 2 * .pi * cy / 512
            let lat = 180 / .pi * atan(0.5 * (exp(n) - exp(-n)))
            return (CLLocationCoordinate2D(latitude: lat, longitude: lng), zoom)
        }

        nonisolated func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let gesture = !reason.intersection([.gesturePan, .gesturePinch, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom,
                                                 .gestureRotate, .gestureTilt]).isEmpty
            MainActor.assumeIsolated {
                moving = true
                setPulse(paused: true, map: mapView)
                if gesture { parent.onGesture() }
            }
        }

        nonisolated func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            MainActor.assumeIsolated { report(mapView) }
        }

        nonisolated func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            MainActor.assumeIsolated {
                moving = false
                report(mapView)
                let bucket = mapView.zoomLevel <= 13 ? Int(mapView.zoomLevel * 2) : 99
                if bucket != clusterBucket { clusterBucket = bucket; applyPins(parent.scene, map: mapView) }
                // Troca o arquivo de tiles quando a câmera passa pra outra área (BH × Inhotim, Tóquio × Kansai × Fuji).
                loadStyle(near: mapView.centerCoordinate)
                setPulse(paused: false, map: mapView)
                parent.onIdle()
            }
        }

        private func report(_ map: MLNMapView) {
            let mpp = map.metersPerPoint(atLatitude: map.centerCoordinate.latitude)
            parent.onCamera(MapCameraState(center: map.centerCoordinate, zoom: map.zoomLevel, metersPerPoint: mpp,
                                           widthMeters: mpp * Double(map.bounds.width)))
        }

        private func setPulse(paused: Bool, map: MLNMapView) {
            for annotation in map.visibleAnnotations ?? [] {
                (map.view(for: annotation) as? PinView)?.setPulsePaused(paused)
            }
        }

        // MARK: Views das anotações

        nonisolated func mapView(_ mapView: MLNMapView, viewFor annotation: any MLNAnnotation) -> MLNAnnotationView? {
            nonisolated(unsafe) let annotation = annotation
            return MainActor.assumeIsolated {
                if annotation is YouAnnotation {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: "you") as? YouView ?? YouView(reuseIdentifier: "you")
                    view.setHeading(youHeading.map { $0 - mapView.direction })
                    return view
                }
                guard let pin = (annotation as? PinAnnotation)?.pin else { return nil }
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? PinView ?? PinView(reuseIdentifier: "pin")
                view.configure(pin)
                if moving { view.setPulsePaused(true) }
                return view
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: any MLNAnnotation) -> Bool { false }

        nonisolated func mapView(_ mapView: MLNMapView, didSelect annotation: any MLNAnnotation) {
            nonisolated(unsafe) let annotation = annotation
            MainActor.assumeIsolated {
                mapView.deselectAnnotation(annotation, animated: false)
                guard let pin = (annotation as? PinAnnotation)?.pin else { return }
                if case .cluster = pin.kind {
                    mapView.setCenter(pin.coordinate, zoomLevel: min(mapView.zoomLevel + 2, 15), animated: true)
                } else {
                    parent.onSelect(pin)
                }
            }
        }
    }
}

private extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
