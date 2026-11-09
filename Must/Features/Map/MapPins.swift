import CoreLocation
import MapLibre
import SwiftUI
import UIKit

// MARK: - Modelo

/// Camadas do mapa = chips-legenda (Hoje · Amanhã · Sem plano · 済 Feitos · Metrô). `search` = resultados da busca do mapa
/// (prompt 27 §2.c): sempre ligada, fora da legenda.
enum MapLayer: String, CaseIterable, Identifiable, Sendable {
    case today, tomorrow, unplanned, done, metro, search

    var id: String { rawValue }

    /// O que vira chip na legenda (a busca não é camada que se desliga).
    static let legend: [MapLayer] = [.today, .tomorrow, .unplanned, .done, .metro]

    var label: String {
        switch self {
        case .today: "Hoje"
        case .tomorrow: "Amanhã"
        case .unplanned: "Sem plano"
        case .done: "Feitos"
        case .metro: "Metrô"
        case .search: "Busca"
        }
    }
}

/// Situação de horário de um must sem plano, como o pino mostra.
enum PinOpenState: Hashable, Sendable {
    case unknown
    case closed
    case open
    /// Fecha em ≤ 30 min; `remaining` = fração dos 30 min que sobra (0…1).
    case closingSoon(remaining: Double)
}

/// Um pino do mapa. Tamanho sempre em pontos (não escala com o zoom).
struct MapPin: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Carimbo com o kanji da lista.
        case unplanned(kanji: String, color: MustColor, open: PinOpenState)
        /// Parada de amanhã (tracejado azul).
        case tomorrow(number: Int)
        /// Parada de hoje; `label` só no próximo ("Inimá · 14 min a pé").
        case today(number: Int, status: TodayStatus, label: String?)
        /// Vários sem plano juntos (z ≤ 13).
        case cluster(count: Int)
        /// Rótulo preto ao lado de um pino (o "mais perto", prompt 11).
        case callout(text: String)
        /// Pílula preta centrada, em mono (meio da linha de distância: "2,1 km · 9 min de metrô").
        case badge(text: String)
        /// Pino preto numerado do preview do Adicionar por link; `label` (nome) só no selecionado.
        case preview(number: Int, label: String?)
        /// Resultado da busca do mapa ("Melhor agora"): número da ordem; o escolhido sai em laranja (`highlighted`).
        case result(number: Int)
        /// Explorar (prompt 31 · 8): pino quadrado de borda 2 pt com o número do índice; sem número = ponto de 8 pt.
        case block(number: Int?, tone: BlockTone, selected: Bool)
        /// Explorar V9 (prompt 32 §4): Must na cor da lista, feito cinza, parada numerada, evento e indicado; o selecionado
        /// sai no acento (`V9.accent`).
        case v9(style: V9Style, selected: Bool)
    }

    /// Pino do mapa V9. `rgb` = cor da lista (0xRRGGBB).
    enum V9Style: Equatable, Sendable {
        case must(letter: String, rgb: UInt32, state: PinOpenState)
        case done
        case stop(number: Int, next: Bool, done: Bool)
        case event
        case indicated
    }

    /// Cor por linha inteira do corte: laranja = seu Must aberto, papel = seu Must fechado/plano, tinta = fora do board.
    enum BlockTone: Equatable, Sendable { case own, paper, outside }

    enum TodayStatus: Equatable, Sendable { case future, next, done }

    var id: String
    var lat: Double
    var lng: Double
    var kind: Kind
    var placeId: String?
    var layer: MapLayer
    /// Selecionado (card aberto) ou o escolhido da busca: disco laranja de 44 pt com halo (`MapaPino.png`).
    var highlighted = false
    /// O que o VoiceOver lê (nome do lugar). Sem nome, o tipo do pino; nunca o id.
    var accessibilityName: String?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    init(id: String, coordinate: CLLocationCoordinate2D, kind: Kind, placeId: String?, layer: MapLayer, highlighted: Bool = false) {
        self.id = id
        lat = coordinate.latitude
        lng = coordinate.longitude
        self.kind = kind
        self.placeId = placeId
        self.layer = layer
        self.highlighted = highlighted
    }

    /// Ordem de empilhamento: hoje por cima de amanhã por cima de sem plano.
    var zOrder: CGFloat {
        if highlighted { return 8 }
        return switch kind {
        case .unplanned, .cluster: 1
        case .tomorrow: 2
        case .today(_, let status, _): status == .next ? 5 : 4
        case .callout, .badge: 6
        case .preview(_, let label): label == nil ? 4 : 7
        case .result: 5
        case .block(_, _, let selected): selected ? 7 : 3
        case .v9(let style, let selected):
            if selected { 8 } else {
                switch style {
                case .stop(_, let next, _): next ? 6 : 5
                case .event: 4
                case .must: 3
                case .indicated: 2
                case .done: 1
                }
            }
        }
    }
}

// MARK: - Anotações

final class PinAnnotation: MLNPointAnnotation {
    var pin: MapPin

    init(_ pin: MapPin) {
        self.pin = pin
        super.init()
        coordinate = pin.coordinate
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }
}

final class YouAnnotation: MLNPointAnnotation {}

// MARK: - Cores e fontes (UIKit)

enum PinStyle {
    static let ink = UIColor(Color.must.ink)
    static let blue = UIColor(Color.must.blue)
    static let green = UIColor(Color.must.green)
    static let greenText = UIColor(Color.must.greenText)
    /// Laranja v8 (#FF4A1C): pino escolhido.
    static let orange = UIColor(V8.orange)
    static let stampBorder = UIColor(red: 0xC9 / 255, green: 0xCD / 255, blue: 0xD3 / 255, alpha: 1)
    static let clusterFill = UIColor(red: 0x9A / 255, green: 0xA0 / 255, blue: 0xA8 / 255, alpha: 1)

    static func mono(_ size: CGFloat, _ weight: UIFont.Weight = .semibold) -> UIFont {
        family(MustFontFamily.geistMono, size: size, weight: weight)
    }

    static func archivo(_ size: CGFloat, _ weight: UIFont.Weight = .semibold) -> UIFont {
        family(MustFontFamily.archivo, size: size, weight: weight)
    }

    static func kanji(_ size: CGFloat) -> UIFont {
        UIFont(name: MustFontFamily.zenKakuBold, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    private static func family(_ name: String, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: name,
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    static func applyShadow(_ layer: CALayer) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 2
    }
}

// MARK: - View do pino

/// Pino desenhado em CALayer + UILabel (Geist Mono e Zen Kaku). O frame é só o círculo;
/// a pílula do próximo e o anel do aberto ficam fora dos limites.
final class PinView: MLNAnnotationView {
    private let disc = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let arc = CAShapeLayer()
    private let label = UILabel()
    private let pill = UILabel()
    private let pillBackground = UIView()
    private(set) var pin: MapPin?
    private var pulsing = false

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        scalesWithViewingDistance = false
        clipsToBounds = false
        layer.addSublayer(ring)
        layer.addSublayer(disc)
        layer.addSublayer(arc)
        label.textAlignment = .center
        addSubview(label)
        pillBackground.backgroundColor = PinStyle.ink
        pillBackground.isUserInteractionEnabled = false
        addSubview(pillBackground)
        pill.textColor = .white
        pill.font = PinStyle.archivo(11)
        pillBackground.addSubview(pill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopPulse()
        pin = nil
    }

    func configure(_ pin: MapPin) {
        guard pin != self.pin else { return }
        self.pin = pin
        reset()
        layer.zPosition = pin.zOrder
        switch pin.kind {
        case .unplanned(let kanji, let color, let open):
            configureStamp(kanji: kanji, color: color, open: open)
        case .tomorrow(let number):
            setSize(24)
            fill(.white, stroke: PinStyle.blue, width: 1.5, dash: [3, 2])
            text("\(number)", font: PinStyle.mono(10), color: PinStyle.blue)
        case .today(let number, let status, let caption):
            switch status {
            case .done:
                setSize(28)
                fill(PinStyle.green, stroke: nil)
                text("✓", font: PinStyle.mono(13, .bold), color: PinStyle.greenText)
            case .next:
                setSize(34)
                fill(PinStyle.ink, stroke: nil)
                text("\(number)", font: PinStyle.mono(14), color: .white)
                if let caption { showPill(caption, gap: 6) }
            case .future:
                setSize(28)
                fill(.white, stroke: PinStyle.ink, width: 1.6)
                text("\(number)", font: PinStyle.mono(13), color: PinStyle.ink)
            }
        case .cluster(let count):
            setSize(28)
            fill(PinStyle.clusterFill, stroke: .white, width: 1.5)
            text("\(count)", font: PinStyle.mono(11), color: .white)
        case .callout(let caption):
            setSize(2)
            disc.isHidden = true
            label.isHidden = true
            showPill(caption, gap: 22)
        case .badge(let caption):
            setSize(2)
            disc.isHidden = true
            label.isHidden = true
            showPill(caption, gap: 0, font: PinStyle.mono(12), centered: true)
        case .preview(let number, let caption):
            setSize(caption == nil ? 28 : 34)
            fill(PinStyle.ink, stroke: nil)
            text("\(number)", font: PinStyle.mono(caption == nil ? 12 : 14), color: .white)
            if let caption { showPill(caption, gap: 6) }
        case .result(let number):
            setSize(30)
            fill(PinStyle.ink, stroke: .white, width: 1.5)
            text("\(number)", font: PinStyle.mono(13), color: .white)
        case .block(let number, let tone, let selected):
            configureBlock(number: number, tone: tone, selected: selected)
        case .v9(let style, let selected):
            configureV9(style, selected: selected)
        }
        if pin.highlighted { highlight() }
        accessibilityLabel = pin.accessibilityName ?? "Lugar no mapa"
    }

    /// Pino V9: disco na cor da lista com a letra em branco; feito = cinza com ✓; parada = número; evento = quadrado arredondado
    /// com estrela; indicado = disco branco pequeno. Selecionado = 36 pt no acento com halo.
    private func configureV9(_ style: MapPin.V9Style, selected: Bool) {
        let white = UIColor.white
        let ink = UIColor(v9Hex: 0x1C1C1E)
        let gray = UIColor(v9Hex: 0x8E8E93)
        let glyph: String
        let glyphColor: UIColor
        switch style {
        case .must(let letter, let rgb, let state):
            glyph = letter
            glyphColor = white
            guard !selected else { break }
            let color = UIColor(v9Hex: rgb)
            switch state {
            case .open:
                setSize(26)
                fill(color, stroke: white, width: 2)
                let r: CGFloat = 18
                ring.path = UIBezierPath(ovalIn: CGRect(x: bounds.midX - r, y: bounds.midY - r, width: r * 2, height: r * 2)).cgPath
                ring.fillColor = UIColor.clear.cgColor
                ring.strokeColor = color.withAlphaComponent(0.55).cgColor
                ring.lineWidth = 2
                ring.isHidden = false
            case .closingSoon(let remaining):
                setSize(26)
                fill(color, stroke: white, width: 2)
                let r: CGFloat = 17
                let start = -CGFloat.pi / 2
                arc.path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: r, startAngle: start,
                                        endAngle: start + 2 * .pi * CGFloat(max(0.02, min(1, remaining))), clockwise: true).cgPath
                arc.fillColor = UIColor.clear.cgColor
                arc.strokeColor = color.cgColor
                arc.lineWidth = 2
                arc.lineCap = .round
                arc.isHidden = false
            case .closed:
                setSize(22)
                fill(color.withAlphaComponent(0.45), stroke: white, width: 1.5)
            case .unknown:
                setSize(24)
                fill(color, stroke: white, width: 2)
            }
            text(letter, font: .systemFont(ofSize: bounds.width < 24 ? 10 : 12, weight: .bold), color: white)
            return
        case .done:
            glyph = "✓"
            glyphColor = white
            if !selected {
                setSize(20)
                fill(gray, stroke: white, width: 1.5)
                text(glyph, font: .systemFont(ofSize: 11, weight: .bold), color: white)
                return
            }
        case .stop(let number, let next, let done):
            glyph = done ? "✓" : "\(number)"
            glyphColor = white
            if !selected {
                setSize(next ? 30 : 26)
                if done { fill(gray, stroke: white, width: 2) }
                else if next { fill(ink, stroke: white, width: 2.5) }
                else { fill(white, stroke: ink, width: 2) }
                text(glyph, font: .monospacedDigitSystemFont(ofSize: next ? 14 : 12, weight: .bold), color: done || next ? white : ink)
                return
            }
        case .event:
            glyph = "★"
            glyphColor = white
            if !selected {
                setSize(26)
                disc.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: 7).cgPath
                disc.fillColor = ink.cgColor
                disc.strokeColor = white.cgColor
                disc.lineWidth = 2
                PinStyle.applyShadow(disc)
                disc.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 7).cgPath
                text(glyph, font: .systemFont(ofSize: 13, weight: .bold), color: white)
                return
            }
        case .indicated:
            glyph = "•"
            glyphColor = white
            if !selected {
                setSize(18)
                fill(white, stroke: gray, width: 2)
                text("•", font: .systemFont(ofSize: 14, weight: .bold), color: gray)
                return
            }
        }
        // Selecionado: 36 pt no acento (o laranja calmo do V9 no claro: o mapa é claro nos dois modos), halo de 25 %.
        let accent = UIColor(v9Hex: 0xD9572B)
        setSize(36)
        fill(accent, stroke: white, width: 2.5)
        text(glyph, font: .systemFont(ofSize: 15, weight: .bold), color: glyphColor)
        let r: CGFloat = 26
        ring.path = UIBezierPath(ovalIn: CGRect(x: bounds.midX - r, y: bounds.midY - r, width: r * 2, height: r * 2)).cgPath
        ring.fillColor = accent.withAlphaComponent(0.2).cgColor
        ring.strokeColor = accent.withAlphaComponent(0.35).cgColor
        ring.lineWidth = 1
        ring.isHidden = false
    }

    /// Pino quadrado do Explorar: borda de 2 pt; selecionado = 34 pt com dois arcos de 1 pt.
    private func configureBlock(number: Int?, tone: MapPin.BlockTone, selected: Bool) {
        let fillColor: UIColor, textColor: UIColor, border: UIColor
        switch tone {
        case .own: fillColor = PinStyle.orange; textColor = PinStyle.ink; border = PinStyle.ink
        case .paper: fillColor = UIColor(V8.paper); textColor = PinStyle.ink; border = PinStyle.ink
        case .outside: fillColor = PinStyle.ink; textColor = .white; border = PinStyle.ink
        }
        disc.shadowOpacity = 0
        guard let number else {
            setSize(10)
            disc.path = UIBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)).cgPath
            disc.fillColor = fillColor.cgColor
            disc.strokeColor = tone == .own ? border.cgColor : (tone == .paper ? border.cgColor : UIColor.white.cgColor)
            disc.lineWidth = 2
            label.isHidden = true
            return
        }
        setSize(selected ? 34 : 26)
        disc.path = UIBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)).cgPath
        disc.fillColor = fillColor.cgColor
        disc.strokeColor = (tone == .outside ? UIColor.white : border).cgColor
        disc.lineWidth = 2
        text("\(number)", font: PinStyle.mono(selected ? 15 : 12, .bold), color: textColor)
        if selected {
            for (i, r) in [CGFloat(26), 34].enumerated() {
                let path = UIBezierPath(ovalIn: CGRect(x: bounds.midX - r, y: bounds.midY - r, width: r * 2, height: r * 2))
                if i == 0 {
                    ring.path = path.cgPath
                    ring.fillColor = UIColor.clear.cgColor
                    ring.strokeColor = border.withAlphaComponent(0.6).cgColor
                    ring.lineWidth = 1
                    ring.isHidden = false
                } else {
                    arc.path = path.cgPath
                    arc.fillColor = UIColor.clear.cgColor
                    arc.strokeColor = border.withAlphaComponent(0.35).cgColor
                    arc.lineWidth = 1
                    arc.isHidden = false
                }
            }
        }
    }

    /// Escolhido: disco laranja 44 pt com contorno tinta e halo laranja a 25 % (o texto do pino fica, em tinta).
    private func highlight() {
        guard !disc.isHidden else { return }
        let caption = label.text
        setSize(44)
        fill(PinStyle.orange, stroke: PinStyle.ink, width: 1.5)
        text(caption ?? "", font: PinStyle.mono(17, .bold), color: PinStyle.ink)
        let r: CGFloat = 31
        ring.path = UIBezierPath(ovalIn: CGRect(x: bounds.midX - r, y: bounds.midY - r, width: r * 2, height: r * 2)).cgPath
        ring.fillColor = PinStyle.orange.withAlphaComponent(0.22).cgColor
        ring.strokeColor = PinStyle.orange.withAlphaComponent(0.35).cgColor
        ring.lineWidth = 1
        ring.isHidden = false
        stopPulse()
        if !pillBackground.isHidden, let caption = pill.text { showPill(caption, gap: 8) }
    }

    private func configureStamp(kanji: String, color: MustColor, open: PinOpenState) {
        let strong = UIColor(color.strong)
        switch open {
        case .open:
            setSize(26)
            fill(strong, stroke: .white, width: 1.5)
            // v8: `strong` é tinta; a letra vai em papel por cima (tinta sobre tinta sumia).
            text(kanji, font: PinStyle.kanji(12), color: UIColor(V8.paper))
            let r: CGFloat = 18
            ring.path = UIBezierPath(ovalIn: CGRect(x: bounds.midX - r, y: bounds.midY - r, width: r * 2, height: r * 2)).cgPath
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = strong.withAlphaComponent(0.5).cgColor
            ring.lineWidth = 1.5
            ring.isHidden = false
            startPulse()
        case .closingSoon(let remaining):
            setSize(26)
            fill(strong.withAlphaComponent(0.35), stroke: .white, width: 1.5)
            text(kanji, font: PinStyle.kanji(12), color: UIColor(color.text).withAlphaComponent(0.7))
            let r: CGFloat = 16
            let start = -CGFloat.pi / 2
            arc.path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: r, startAngle: start,
                                    endAngle: start + 2 * .pi * CGFloat(max(0.02, min(1, remaining))), clockwise: true).cgPath
            arc.fillColor = UIColor.clear.cgColor
            arc.strokeColor = strong.cgColor
            arc.lineWidth = 2
            arc.lineCap = .round
            arc.isHidden = false
        case .closed, .unknown:
            setSize(22)
            fill(.white, stroke: PinStyle.stampBorder, width: 1.2)
            text(kanji, font: PinStyle.kanji(11), color: strong)
        }
    }

    // MARK: Peças

    private func reset() {
        ring.isHidden = true
        ring.fillColor = UIColor.clear.cgColor
        arc.isHidden = true
        disc.isHidden = false
        disc.lineDashPattern = nil
        pillBackground.isHidden = true
        label.isHidden = false
        alpha = 1
    }

    private func setSize(_ size: CGFloat) {
        frame = CGRect(x: frame.minX, y: frame.minY, width: size, height: size)
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        label.frame = bounds
    }

    private func fill(_ color: UIColor, stroke: UIColor?, width: CGFloat = 0, dash: [NSNumber]? = nil) {
        let inset = width / 2
        disc.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
        disc.fillColor = color.cgColor
        disc.strokeColor = stroke?.cgColor
        disc.lineWidth = width
        disc.lineDashPattern = dash
        PinStyle.applyShadow(disc)
        disc.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    private func text(_ string: String, font: UIFont, color: UIColor) {
        label.text = string
        label.font = font
        label.textColor = color
    }

    private func showPill(_ caption: String, gap: CGFloat, font: UIFont = PinStyle.archivo(11), centered: Bool = false) {
        pill.font = font
        pill.text = caption
        pill.sizeToFit()
        let height: CGFloat = centered ? 30 : 26
        let width = pill.bounds.width + 22
        let x = centered ? bounds.midX - width / 2 : bounds.maxX + gap
        pillBackground.frame = CGRect(x: x, y: bounds.midY - height / 2, width: width, height: height)
        pillBackground.layer.cornerRadius = height / 2
        PinStyle.applyShadow(pillBackground.layer)
        pill.frame = CGRect(x: 11, y: 0, width: pill.bounds.width, height: height)
        pillBackground.isHidden = false
    }

    // MARK: Pulso (só com o mapa parado)

    func setPulsePaused(_ paused: Bool) {
        if paused { stopPulse() } else if pin?.highlighted != true, case .unplanned(_, _, .open) = pin?.kind { startPulse() }
    }

    private func startPulse() {
        guard !pulsing, !UIAccessibility.isReduceMotionEnabled else { return }
        pulsing = true
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.85
        scale.toValue = 1.25
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 2
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "pulse")
    }

    private func stopPulse() {
        pulsing = false
        ring.removeAnimation(forKey: "pulse")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -10, dy: -10).contains(point)
    }
}

// MARK: - Você

/// Halo radial 68 pt (35% → 0), cone de direção 22% e ponto azul 15 pt com borda branca 2,5.
final class YouView: MLNAnnotationView {
    private let halo = CAGradientLayer()
    private let cone = CAShapeLayer()
    private let dot = CAShapeLayer()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        scalesWithViewingDistance = false
        frame = CGRect(x: 0, y: 0, width: 68, height: 68)
        isUserInteractionEnabled = false
        layer.zPosition = 3

        halo.type = .radial
        halo.colors = [PinStyle.orange.withAlphaComponent(0.35).cgColor, PinStyle.orange.withAlphaComponent(0).cgColor]
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        halo.frame = bounds
        layer.addSublayer(halo)

        let c = CGPoint(x: 34, y: 34)
        let path = UIBezierPath()
        path.move(to: c)
        path.addArc(withCenter: c, radius: 34, startAngle: -.pi / 2 - 0.42, endAngle: -.pi / 2 + 0.42, clockwise: true)
        path.close()
        cone.path = path.cgPath
        cone.fillColor = PinStyle.orange.withAlphaComponent(0.22).cgColor
        cone.frame = bounds
        cone.isHidden = true
        layer.addSublayer(cone)

        dot.path = UIBezierPath(ovalIn: CGRect(x: 34 - 7.5, y: 34 - 7.5, width: 15, height: 15)).cgPath
        dot.fillColor = PinStyle.orange.cgColor
        dot.strokeColor = PinStyle.ink.cgColor
        dot.lineWidth = 2.5
        PinStyle.applyShadow(dot)
        layer.addSublayer(dot)
        accessibilityLabel = "Você"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    private var system = false

    /// V9: o ponto azul do sistema (azul com borda branca e halo azul), no lugar do laranja do v8.
    func setSystemStyle(_ on: Bool) {
        guard on != system else { return }
        system = on
        let main = on ? UIColor.systemBlue : PinStyle.orange
        halo.colors = [main.withAlphaComponent(on ? 0.22 : 0.35).cgColor, main.withAlphaComponent(0).cgColor]
        cone.fillColor = main.withAlphaComponent(0.22).cgColor
        dot.fillColor = main.cgColor
        dot.strokeColor = on ? UIColor.white.cgColor : PinStyle.ink.cgColor
        dot.lineWidth = on ? 3 : 2.5
    }

    /// Direção em graus em relação à tela (já descontada a rotação do mapa).
    func setHeading(_ degrees: Double?) {
        guard let degrees else { cone.isHidden = true; return }
        cone.isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cone.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(degrees * .pi / 180)))
        CATransaction.commit()
    }
}
