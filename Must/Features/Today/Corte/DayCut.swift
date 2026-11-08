import SwiftUI

// O corte nas telas do dia (prompt 30 · etapa 2): bloco da foto do bairro em cima, régua estática, papel embaixo com as
// paradas como índice (hora em número grande, réguas de 2 pt). Peças compartilhadas por Linha, Agora, Bom dia, Boa noite
// e Proposta. A foto é a que o app já tem no disco (`CapaState.diskPhoto`); nunca baixa nada por causa do corte.

/// Bloco da foto do dia: o bairro (`areaId`) com a foto já no disco, ou só a cor do lugar com a trama (estado normal).
struct DayBand<Content: View>: View {
    var areaId: String?
    var places: [Place]
    var height: CGFloat = 250
    @ViewBuilder var content: Content

    @Environment(RegionStore.self) private var store
    @State private var photo: URL?
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    var body: some View {
        CutBand(photo: photo) {
            content
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 16)
        }
        .frame(height: height * min(scale, 1.4))
        .task(id: "\(store.region.trip.id)|\(areaId ?? "")|\(places.count)") {
            photo = await Self.photo(region: store.region, areaId: areaId, places: places)
        }
    }

    /// Foto do bairro que já está no disco (Google de um Must dele › Commons já baixada). `nil` = só a cor.
    static func photo(region: Region, areaId: String?, places: [Place]) async -> URL? {
        guard let areaId, let (_, candidates) = CapaState.areaCandidates(region: region, areaId: areaId, places: places),
              let found = await CapaState.diskPhoto(region: region, areaId: areaId, candidates: candidates) else { return nil }
        return URL(string: found.largeURL ?? found.url)
    }
}

/// Cantos do bloco: ficha técnica à esquerda e à direita, na tinta do bloco.
struct DayBandCorners: View {
    var left: [String]
    var right: [String]
    @Environment(\.tripTheme) private var theme

    var body: some View {
        HStack(alignment: .top) {
            SpecStack(lines: left, color: theme.coverInk.opacity(0.9))
            Spacer(minLength: 12)
            SpecStack(lines: right, color: theme.coverInk.opacity(0.9), alignment: .trailing)
        }
    }
}

/// O numeral gigante do bloco (na tinta do bloco) com a legenda em mono embaixo.
struct DayBandNumeral: View {
    var value: String
    var caption: String
    var size: CGFloat = 96
    @Environment(\.tripTheme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            BigNumeral(value, size: size, color: theme.coverInk, alignment: .trailing)
                .fixedSize()
                .padding(.bottom, -size * 0.06)
            MonoLabel(caption, size: 9.5, color: theme.coverInk.opacity(0.9))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(caption)")
    }
}

/// Régua de 2 pt entre as linhas do índice.
struct IndexRule: View {
    var color: Color = V8.ink
    var body: some View { Rectangle().fill(color).frame(height: 2).accessibilityHidden(true) }
}

/// Uma faixa do índice do dia que não é parada (em cartaz, aviso, texto): bloco inteiro, régua embaixo.
struct DayStrip<Content: View>: View {
    enum Tone { case paper, ink, orange }
    var tone: Tone = .paper
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone == .ink ? V8.ink : tone == .orange ? V8.orange : Color.clear)
            .overlay(alignment: .bottom) { IndexRule() }
    }
}

extension DayPlan {
    /// O bairro pra foto do bloco: o do dia, ou o da primeira parada que tem um (a próxima, quando o dia já começou).
    func bandArea(from now: Date? = nil) -> String? {
        if let area { return area }
        let upcoming = now.map { n in stops.filter { $0.end >= n } } ?? stops
        return (upcoming + stops).compactMap(\.area).first
    }
}
