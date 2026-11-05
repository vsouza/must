import SwiftUI
import UIKit

/// Formato do card: Stories 1080×1920 (padrão) ou Feed 1080×1080 (Instagram e Facebook).
enum CollectibleFormat: String, CaseIterable, Sendable, Identifiable {
    case stories, feed
    var id: String { rawValue }
    var size: CGSize { self == .stories ? CGSize(width: 1080, height: 1920) : CGSize(width: 1080, height: 1080) }
    var label: String { self == .stories ? "Stories" : "Feed" }
}

/// O card (`Colecionavel.png`), identidade v8 brutalista: cor sólida, arcos, numeral gigante = ordem, micro-rótulos nos
/// cantos, nome grande, selo com a sigla do bairro e faixa de tinta no pé. Desenhado em pontos = pixels (1080 de
/// largura) com fontes de tamanho fixo (não acompanham o Dynamic Type) pra `ImageRenderer` sair igual em todo aparelho.
/// Sem foto (leve, offline, sem licença). Nunca: coordenada, gasto, hotel, japonês.
struct CollectibleCardView: View {
    var item: Collectible
    var format: CollectibleFormat = .stories
    /// Cor da viagem (capa do país); sem viagem, laranja.
    var tint: Color
    /// Cantos arredondados só na tela; o PNG sai de ponta a ponta.
    var corner: CGFloat = 0

    private var stories: Bool { format == .stories }
    private var margin: CGFloat { 70 }

    private var background: Color {
        switch item.variant {
        case .trip: tint
        case .anchor: V8.ink
        case .outdoor: V8.paper
        }
    }
    private var ink: Color { item.variant == .outdoor ? V8.ink : V8.white }
    private var numeralColor: Color { item.variant == .trip ? V8.white : (item.variant == .anchor ? V8.orange : V8.orange) }
    private var ringColor: Color { item.variant == .outdoor ? V8.ink.opacity(0.45) : V8.white.opacity(0.5) }

    var body: some View {
        let size = format.size
        ZStack(alignment: .topLeading) {
            background
            rings(size)
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 0)
                titleBlock
                numeral(size)
                band
            }
            seal.position(x: size.width - margin - sealSize / 2, y: margin + (stories ? 70 : 40) + sealSize / 2)
        }
        .frame(width: size.width, height: size.height)
        .overlay { if item.variant == .outdoor { Rectangle().strokeBorder(V8.ink, lineWidth: 6) } }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Colecionável \(item.order) de \(item.total): \(item.title)")
    }

    // MARK: Peças

    private var sealSize: CGFloat { stories ? 230 : 200 }

    private func rings(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            let d: CGFloat = stories ? 1000 : 900
            Circle().stroke(ringColor, lineWidth: 3).frame(width: d, height: d).offset(x: stories ? -330 : -260, y: stories ? -430 : -480)
            Circle().stroke(ringColor, lineWidth: 3).frame(width: d, height: d).offset(x: stories ? 180 : 420, y: stories ? 790 : 480)
            if stories { Circle().stroke(ringColor, lineWidth: 3).frame(width: d, height: d).offset(x: -420, y: 1250) }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func mono(_ size: CGFloat, weight: CGFloat = 600) -> Font { Font(V8Fonts.martian(size, weight: weight)) }

    private var header: some View {
        let place = [item.cityName, CollectibleText.latinOnly(item.area ?? "")].filter { !$0.isEmpty }.joined(separator: " · ")
        let date = "Feito · " + CollectibleText.dateLabel(item.doneAt, timeZoneId: item.timeZoneId)
        return VStack(alignment: .leading, spacing: 10) {
            Text(date.uppercased()).font(mono(30)).tracking(3).foregroundStyle(ink)
            Text(place.uppercased()).font(mono(30)).tracking(3).foregroundStyle(ink.opacity(0.72))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: format.size.width - margin * 2 - sealSize - 30, alignment: .leading)
        .padding(.top, margin + (stories ? 70 : 40))
        .padding(.horizontal, margin)
    }

    private var seal: some View {
        ZStack {
            Circle().strokeBorder(ink, lineWidth: 7)
            VStack(spacing: 6) {
                Text(item.stampCode).font(mono(stories ? 72 : 64, weight: 800)).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("FEITO").font(mono(22, weight: 700)).tracking(4).foregroundStyle(ink)
            }
            .padding(.horizontal, 24)
        }
        .frame(width: sealSize, height: sealSize)
    }

    private var titleBlock: some View {
        let name = CollectibleText.latinOnly(item.title)
        let nameSize: CGFloat = stories ? 200 : 170
        return VStack(alignment: .leading, spacing: stories ? 34 : 26) {
            Text(name)
                .font(Font(V8Fonts.bricolage(nameSize, weight: 800, width: 82, opticalSize: 96)))
                .tracking(-nameSize * 0.04)
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.35)
                .fixedSize(horizontal: false, vertical: true)
            if !item.subLine.isEmpty {
                Text(CollectibleText.latinOnly(item.subLine))
                    .font(.custom(V8Fonts.Family.schibsted, fixedSize: stories ? 64 : 54).weight(.bold))
                    .foregroundStyle(ink.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, margin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, stories ? 40 : 10)
    }

    private func numeral(_ size: CGSize) -> some View {
        let font: CGFloat = stories ? 800 : 470
        return Text(CollectibleText.number(item.order))
            .font(Font(V8Fonts.bricolage(font, weight: 800, width: 78, opticalSize: 96)))
            .tracking(-0.06 * font)
            .foregroundStyle(numeralColor)
            .lineLimit(1)
            .fixedSize()
            .frame(height: font * 0.78 * 0.9, alignment: .top)
            .frame(width: size.width, alignment: .leading)
            .offset(x: -font * 0.05)
            .clipped()
            .accessibilityHidden(true)
    }

    private var band: some View {
        HStack {
            Text("MUST · GUIA DE BOLSO").font(mono(38, weight: 700)).tracking(4).foregroundStyle(V8.white)
            Spacer(minLength: 12)
            (Text(CollectibleText.number(item.order)).foregroundStyle(V8.orange)
             + Text(" / \(CollectibleText.number(item.total))").foregroundStyle(V8.white))
                .font(mono(40, weight: 700))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, margin)
        .frame(height: stories ? 170 : 150)
        .frame(maxWidth: .infinity)
        .background(V8.ink)
    }
}

/// O card inteiro, encolhido pra caber numa largura (miniatura, momento): um desenho só, escalado.
struct ScaledCollectibleCard: View {
    var item: Collectible
    var format: CollectibleFormat = .stories
    var tint: Color
    var width: CGFloat
    var corner: CGFloat = 36

    var body: some View {
        let k = width / format.size.width
        CollectibleCardView(item: item, format: format, tint: tint, corner: corner / max(k, 0.01))
            .frame(width: format.size.width, height: format.size.height)
            .scaleEffect(k, anchor: .topLeading)
            .frame(width: width, height: format.size.height * k, alignment: .topLeading)
    }
}

/// PNG do card por `ImageRenderer` (1,0 de escala: pontos = pixels). `ImageRenderer` roda no main; chamar fora do
/// `body` (num `.task`/ação), nunca a cada redesenho.
@MainActor
enum CollectibleRenderer {
    static func image(_ item: Collectible, format: CollectibleFormat, tint: Color) -> UIImage? {
        let renderer = ImageRenderer(content: CollectibleCardView(item: item, format: format, tint: tint))
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(format.size)
        return renderer.uiImage
    }

    static func png(_ item: Collectible, format: CollectibleFormat, tint: Color) -> Data? {
        image(item, format: format, tint: tint)?.pngData()
    }

    /// `must-014-fuunji.png` (o nome aparece no WhatsApp) — o nome é latino, sem espaço.
    static func fileName(_ item: Collectible, format: CollectibleFormat) -> String {
        let slug = CollectibleText.latinOnly(item.title).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return "must-\(CollectibleText.number(item.order))-\(slug.isEmpty ? "feito" : slug)\(format == .feed ? "-feed" : "").png"
    }

    /// Grava no temporário e devolve a URL pro share sheet.
    static func write(_ item: Collectible, format: CollectibleFormat, tint: Color) -> URL? {
        guard let data = png(item, format: format, tint: tint) else { return nil }
        return DayPosterRenderer.write(data, name: fileName(item, format: format))
    }

    static func cleanup(_ url: URL?) { if let url { try? FileManager.default.removeItem(at: url) } }
}
