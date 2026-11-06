import CoreLocation
import SwiftUI

/// Card do pino (prompt 27 §2.a, `MapaPino.png`): foto do disco com crédito (placeholder de cor enquanto não tem), nome
/// grande, "aberto até", meta (Must, tipo, nota se já estiver no aparelho), ficha de 3 campos (fila, preço, distância e
/// tempo, do `PlaceFicha`), até 2 amigos que foram, e **Ir agora · N min** / **Feito** / expandir. Arrastar pra baixo fecha,
/// pra cima abre o Lugar inteiro.
struct MapPlaceCard: View {
    var place: Place
    var region: Region
    var now: Date
    var here: CLLocation?
    var walkMaxKm: Double
    /// Minutos até lá (a pé ou metrô, o mesmo do "Ir").
    var goMinutes: Int?
    var nearby: [NearbyPlace] = []
    var onClose: () -> Void
    var onOpen: () -> Void
    var onGo: () -> Void
    var onDone: () -> Void

    @Environment(\.friends) private var friends
    @Environment(Services.self) private var services: Services?
    @State private var photoURL: URL?
    @State private var rating: KnownRating?
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(V8.ink.opacity(0.18)).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 2)
                .accessibilityHidden(true)
            photo
            Text(MapCardFacts.meta(place, rating: rating, locale: region.locale).uppercased())
                .font(V8Font.mono(11))
                .tracking(1.1)
                .foregroundStyle(V8.mute)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            fields
            friendsRow
            actions
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(V8.paper))
        .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(V8.ink.opacity(0.06)))
        .shadow(color: V8.ink.opacity(0.18), radius: 24, y: 10)
        .offset(y: max(0, drag))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation.height }
                .onEnded { value in
                    let dy = value.translation.height
                    withAnimation(.spring(duration: 0.3)) { drag = 0 }
                    if dy > 90 { onClose() } else if dy < -70 { onOpen() }
                }
        )
        .task(id: place.id) { await load() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Abrir o lugar", onOpen)
        .accessibilityAction(.escape, onClose)
    }

    // MARK: Peças

    private var photo: some View {
        V8Photo(url: photoURL, placeholder: V8.photo)
            .frame(maxWidth: .infinity)
            .frame(height: 158)
            .overlay(alignment: .bottom) {
                // Escurece só onde tem texto.
                LinearGradient(colors: [V8.ink.opacity(0), V8.ink.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 96)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 10) {
                    Text(place.name)
                        .font(V8Font.display(34))
                        .tracking(-1)
                        .foregroundStyle(V8.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .shadow(color: V8.ink.opacity(0.35), radius: 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let tag = PlaceFicha.openTag(place, region: region, now: now) {
                        V8Tag(text: tag, style: tag.hasPrefix("aberto") ? .orange : .ink)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .overlay(alignment: .topTrailing) {
                if photoURL != nil, let credit = MapCardPhoto.credit(place.photoRefs.first) {
                    V8Tag(text: credit, style: .glass).padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
    }

    private var fields: some View {
        let cells = MapCardFacts.cells(place, region: region, now: now, here: here, walkMaxKm: walkMaxKm)
        return HStack(alignment: .top, spacing: 12) {
            ForEach(cells, id: \.self) { cell in
                VStack(alignment: .leading, spacing: 4) {
                    Text(cell.label.uppercased())
                        .font(V8Font.mono(10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(V8.mute)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(cell.value)
                        .font(V8Font.text(16, weight: .bold))
                        .foregroundStyle(V8.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var friendsRow: some View {
        let visits = Array(friends.visits(placeId: place.id).prefix(2))
        if let line = MapCardFacts.friendsLine(visits) {
            HStack(spacing: 10) {
                HStack(spacing: -8) {
                    ForEach(Array(visits.enumerated()), id: \.element.id) { i, v in
                        Text(String(v.initials.prefix(1)))
                            .font(V8Font.text(13, weight: .bold))
                            .foregroundStyle(i == 0 ? V8.white : V8.ink)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(i == 0 ? V8.ink : V8.orange))
                            .overlay(Circle().strokeBorder(V8.paper, lineWidth: 2))
                    }
                }
                Text(line)
                    .font(V8Font.text(14))
                    .foregroundStyle(V8.mute)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if friends.isSample {
                    Text("EXEMPLO").font(V8Font.mono(9, weight: .semibold)).tracking(0.9).foregroundStyle(V8.mute).fixedSize()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            // Letra grande: "Ir · 21 min" sem ícone antes de cortar o texto.
            ViewThatFits(in: .horizontal) {
                V8Button(goMinutes.map { "Ir agora · \($0) min" } ?? "Ir agora", .orange, icon: .rota, action: onGo)
                V8Button(goMinutes.map { "Ir · \($0) min" } ?? "Ir", .orange, action: onGo)
            }
            .layoutPriority(1)
            Button(action: onDone) {
                Text(place.isDone ? "Feito ✓" : "Feito")
                    .font(V8Font.text(16, weight: .bold))
                    .foregroundStyle(V8.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 22)
                    .frame(minHeight: 56)
                    .background(Capsule().fill(V8.ink))
                    .contentShape(Capsule())
            }
            .buttonStyle(MustPressStyle())
            .disabled(place.isDone)
            Button(action: onOpen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(V8.ink)
                    .frame(width: 56, height: 56)
                    .overlay(Circle().strokeBorder(V8.ink, lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Abrir o lugar")
        }
    }

    // MARK: Disco primeiro

    private func load() async {
        let refs = place.photoRefs
        let network = services?.connectivity.prefetchNetwork ?? PrefetchPolicy.Network(status: .offline, wifi: false, expensive: true)
        switch MapCardPhoto.source(refs: refs, network: network) {
        case .disk(let url): photoURL = url
        case .none: photoURL = nil
        case .fetch(let placeholder):
            photoURL = placeholder
            if let services, let placeId = place.placeId,
               let photo = try? await services.photoResolver.photo(placeId: placeId, refs: refs, index: 0, purpose: .gallery, persist: nil),
               let url = URL(string: photo.url) {
                photoURL = url
            }
        }
        rating = await MapRatings.known(placeId: place.id, name: place.name, region: region, googlePlaceId: place.placeId, nearby: nearby)
    }
}
