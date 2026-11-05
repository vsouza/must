import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI

// Cartaz do dia (prompt 25 · B.1, `Compartilhar.png`): 9:16, cor do lugar, "Dia N · bairro", paradas com horário,
// mini-mapa do percurso, numeral gigante e o rodapé "must · guia de bolso". Os dados prontos (`DayPoster`) saem do
// `DayPlan` ou do link recebido (`SharedDay`); o desenho é `DayPosterView` e o `DayPosterRenderer` faz PNG e PDF.

/// O que o cartaz mostra. Tudo já em texto: o desenho não formata nada.
struct DayPoster: Hashable, Sendable {
    struct Stop: Hashable, Sendable {
        var time: String
        var label: String
        var price: String?
        var kind: StopKind
        var lat: Double?
        var lng: Double?
    }

    struct QR: Hashable, Sendable {
        var label: String
        var payload: String
    }

    /// "Sáb · 15 nov".
    var dayLine: String
    /// "Tóquio".
    var city: String
    /// "3" (dia da viagem; fora dela, o dia do mês).
    var numeral: String
    /// "Shinjuku".
    var area: String
    var stops: [Stop]
    /// Cor do lugar (0xRRGGBB): Japão vermelho, Brasil verde, Itália azzurro.
    var coverRGB: UInt32
    var qrs: [QR] = []

    /// Pontos do percurso que têm coordenada (o mini-mapa precisa de pelo menos dois).
    var route: [Stop] { stops.filter { $0.lat != nil && $0.lng != nil } }
    var hasMap: Bool { route.count >= 2 }
}

/// Opções da tela Mandar (os quatro círculos).
struct PosterOptions: Hashable, Sendable {
    var times = true
    var map = true
    var prices = false
    var qr = false
}

extension DayPoster {
    /// Do dia montado. `coordinates`: `placeId` → (lat, lng) do board; `tickets`: QR dos ingressos do dia.
    static func make(plan: DayPlan, region: Region, areaName: String?, cityName: String?,
                     coordinates: [String: (Double, Double)] = [:], qrs: [QR] = []) -> DayPoster {
        let stops = plan.stops.map { stop -> Stop in
            let coord: (Double, Double)? = if let lat = stop.lat, let lng = stop.lng { (lat, lng) }
                else { stop.placeId.flatMap { coordinates[$0] } }
            return Stop(time: region.timeString(stop.start), label: stop.label,
                        price: stop.cost.flatMap { $0 > 0 ? region.money($0) : nil }, kind: stop.kind,
                        lat: coord?.0, lng: coord?.1)
        }
        return DayPoster(dayLine: DayText.dayLine(plan.date, region: region),
                         city: cityName ?? region.displayName,
                         numeral: plan.dayNumber.map(String.init) ?? region.dayNumber(plan.date),
                         area: areaName ?? Self.shortTitle(plan.title),
                         stops: stops, coverRGB: TripTheme.forRegion(region).coverRGB, qrs: qrs)
    }

    /// Do link recebido (sem preço nem QR: o link não leva).
    static func make(shared: SharedDay) -> DayPoster? {
        guard let region = shared.region, let plan = shared.plan() else { return nil }
        return make(plan: plan, region: region, areaName: shared.a, cityName: shared.c)
    }

    /// "Shinjuku + Tsukiji" → "Shinjuku" (o cartaz tem duas linhas de título).
    static func shortTitle(_ title: String) -> String {
        let first = title.components(separatedBy: " + ").first ?? title
        return first.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Desenho

/// O cartaz em pontos (360×640); o renderer multiplica por 3 (1080×1920). Fontes em tamanho fixo: o cartaz não
/// acompanha o Dynamic Type de quem manda.
struct DayPosterView: View {
    var poster: DayPoster
    var options: PosterOptions

    static let size = CGSize(width: 360, height: 640)
    /// Paradas que cabem; o resto vira "+ N paradas".
    static let maxStops = 12

    private var ink: Color { .white }
    private var cover: Color { Color(hex: poster.coverRGB) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            cover
            Circle()
                .stroke(ink.opacity(0.5), lineWidth: 2)
                .frame(width: 408, height: 408)
                .offset(x: -120, y: -168)
            numeral
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    micro(poster.dayLine)
                    Spacer(minLength: 8)
                    micro(poster.city)
                }
                Text("Dia \(poster.numeral)\n\(poster.area)")
                    .font(Font(V8Fonts.bricolage(41, weight: 700, width: 92, opticalSize: 96)))
                    .tracking(-0.8)
                    .lineSpacing(-4)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 28)
                stops.padding(.top, 26)
                Spacer(minLength: 12)
                bottom
                micro("must · guia de bolso").padding(.top, 14)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
        .environment(\.colorScheme, .light)
    }

    private func micro(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Font(V8Fonts.martian(12, weight: 500)))
            .tracking(1)
            .lineLimit(1)
    }

    private var numeral: some View {
        let size: CGFloat = poster.numeral.count > 1 ? 230 : 288
        return Text(poster.numeral)
            .font(Font(V8Fonts.bricolage(size, weight: 800, width: 78, opticalSize: 96)))
            .tracking(-0.06 * size)
            .foregroundStyle(ink.opacity(0.95))
            .fixedSize()
            .frame(width: Self.size.width, height: Self.size.height, alignment: .bottomTrailing)
            .offset(x: 14, y: size * 0.24)
    }

    private var shown: [DayPoster.Stop] { Array(poster.stops.prefix(poster.stops.count > Self.maxStops ? Self.maxStops - 1 : Self.maxStops)) }

    private var stops: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, stop in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if options.times {
                        Text(stop.time).font(Font(V8Fonts.martian(15.5, weight: 600)))
                    } else {
                        Circle().fill(ink).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    }
                    Text(stop.label)
                        .font(.custom(V8Fonts.Family.schibsted, fixedSize: 15.5).weight(stop.kind == .anchor ? .semibold : .regular))
                        .lineLimit(1)
                    if options.prices, let price = stop.price {
                        Text(price).font(Font(V8Fonts.martian(12, weight: 500))).opacity(0.8).lineLimit(1).fixedSize()
                    }
                }
            }
            if poster.stops.count > shown.count {
                Text("+ \(poster.stops.count - shown.count) paradas")
                    .font(.custom(V8Fonts.Family.schibsted, fixedSize: 14))
                    .opacity(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Canto de baixo à esquerda (o numeral fica à direita): mini-mapa e/ou QR dos ingressos.
    @ViewBuilder private var bottom: some View {
        let qrs = options.qr ? Array(poster.qrs.prefix(2)) : []
        HStack(alignment: .bottom, spacing: 10) {
            if options.map, poster.hasMap {
                PosterRouteSketch(stops: poster.route, ink: ink)
                    .frame(width: qrs.isEmpty ? 176 : 112, height: qrs.isEmpty ? 132 : 112)
            }
            ForEach(Array(qrs.enumerated()), id: \.offset) { _, qr in
                VStack(alignment: .leading, spacing: 4) {
                    PosterQR(payload: qr.payload).frame(width: 74, height: 74)
                    Text(qr.label).font(Font(V8Fonts.martian(8, weight: 500))).lineLimit(1).frame(width: 74, alignment: .leading)
                }
            }
        }
    }
}

/// Percurso desenhado (como a faixa do Guia): linha branca entre as paradas, pontos maiores nas âncoras.
/// TODO(p25:2): trocar por snapshot do MapLibre offline (pacote PMTiles da cidade) quando o `MapLibreView` tiver
/// renderização fora da tela; até lá, o esquema projetado (sem tiles, sem rede).
struct PosterRouteSketch: View {
    var stops: [DayPoster.Stop]
    var ink: Color

    var body: some View {
        Canvas { context, size in
            let points = Self.project(stops, in: CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12))
            let frame = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14)
            context.stroke(frame, with: .color(ink.opacity(0.35)), lineWidth: 1)
            var line = Path()
            if let first = points.first { line.move(to: first) }
            for p in points.dropFirst() { line.addLine(to: p) }
            context.stroke(line, with: .color(ink.opacity(0.9)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            for (i, p) in points.enumerated() {
                let r: CGFloat = stops[i].kind == .anchor ? 5 : (stops[i].kind == .micro ? 2.5 : 3.5)
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(ink))
            }
        }
    }

    /// Equiretangular com o cosseno da latitude (uma cidade cabe sem distorção visível), centrado e proporcional.
    static func project(_ stops: [DayPoster.Stop], in rect: CGRect) -> [CGPoint] {
        let coords = stops.compactMap { s -> (Double, Double)? in
            guard let lat = s.lat, let lng = s.lng else { return nil }
            return (lat, lng)
        }
        guard let first = coords.first else { return [] }
        let k = cos(first.0 * .pi / 180)
        let xs = coords.map { $0.1 * k }, ys = coords.map { $0.0 }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let spanX = max(maxX - minX, 1e-5), spanY = max(maxY - minY, 1e-5)
        let scale = min(rect.width / spanX, rect.height / spanY)
        let w = spanX * scale, h = spanY * scale
        let ox = rect.minX + (rect.width - w) / 2, oy = rect.minY + (rect.height - h) / 2
        return zip(xs, ys).map { x, y in
            CGPoint(x: ox + (x - minX) * scale, y: oy + (maxY - y) * scale)
        }
    }
}

/// QR de um ingresso, gerado no aparelho (Core Image), em fundo branco.
struct PosterQR: View {
    var payload: String

    var body: some View {
        if let image = Self.image(payload) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white))
        }
    }

    static func image(_ payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
