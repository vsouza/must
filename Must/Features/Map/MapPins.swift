import CoreLocation
import MapLibre
import SwiftUI
import UIKit

// MARK: - Modelo

/// Camadas do mapa = chips-legenda (Hoje · Amanhã · Sem plano · 済 Feitos · Metrô).
enum MapLayer: String, CaseIterable, Identifiable, Sendable {
    case today, tomorrow, unplanned, done, metro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Hoje"
        case .tomorrow: "Amanhã"
        case .unplanned: "Sem plano"
        case .done: "Feitos"
        case .metro: "Metrô"
        }
    }
}

/// Situação de horário de um must sem plano, como o pino mostra.
enum PinOpenState: Equatable, Sendable {
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
    }

    enum TodayStatus: Equatable, Sendable { case future, next, done }

    var id: String
    var lat: Double
    var lng: Double
    var kind: Kind
    var placeId: String?
    var layer: MapLayer

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    init(id: String, coordinate: CLLocationCoordinate2D, kind: Kind, placeId: String?, layer: MapLayer) {
        self.id = id
        lat = coordinate.latitude
        lng = coordinate.longitude
        self.kind = kind
        self.placeId = placeId
        self.layer = layer
    }

    /// Ordem de empilhamento: hoje por cima de amanhã por cima de sem plano.
    var zOrder: CGFloat {
        switch kind {
        case .unplanned, .cluster: 1
        case .tomorrow: 2
        case .today(_, let status, _): status == .next ? 5 : 4
        case .callout: 6
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
                text("済", font: PinStyle.kanji(13), color: PinStyle.greenText)
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
            showPill(caption, gap: 22)
        }
        accessibilityLabel = pin.placeId
    }

    private func configureStamp(kanji: String, color: MustColor, open: PinOpenState) {
        let strong = UIColor(color.strong)
        switch open {
        case .open:
            setSize(26)
            fill(strong, stroke: .white, width: 1.5)
            text(kanji, font: PinStyle.kanji(12), color: UIColor(color.text))
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

    private func showPill(_ caption: String, gap: CGFloat) {
        pill.text = caption
        pill.sizeToFit()
        let height: CGFloat = 26
        let width = pill.bounds.width + 22
        pillBackground.frame = CGRect(x: bounds.maxX + gap, y: bounds.midY - height / 2, width: width, height: height)
        pillBackground.layer.cornerRadius = height / 2
        PinStyle.applyShadow(pillBackground.layer)
        pill.frame = CGRect(x: 11, y: 0, width: pill.bounds.width, height: height)
        pillBackground.isHidden = false
    }

    // MARK: Pulso (só com o mapa parado)

    func setPulsePaused(_ paused: Bool) {
        if paused { stopPulse() } else if case .unplanned(_, _, .open) = pin?.kind { startPulse() }
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
        halo.colors = [PinStyle.blue.withAlphaComponent(0.35).cgColor, PinStyle.blue.withAlphaComponent(0).cgColor]
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
        cone.fillColor = PinStyle.blue.withAlphaComponent(0.22).cgColor
        cone.frame = bounds
        cone.isHidden = true
        layer.addSublayer(cone)

        dot.path = UIBezierPath(ovalIn: CGRect(x: 34 - 7.5, y: 34 - 7.5, width: 15, height: 15)).cgPath
        dot.fillColor = PinStyle.blue.cgColor
        dot.strokeColor = UIColor.white.cgColor
        dot.lineWidth = 2.5
        PinStyle.applyShadow(dot)
        layer.addSublayer(dot)
        accessibilityLabel = "Você"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

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
