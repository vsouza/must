import CoreLocation
import SwiftUI

/// Card do pino (prompt 27 §2.a, `MapaPino.png`): foto do disco com crédito (placeholder de cor enquanto não tem), nome
/// grande, "aberto até", meta (Must, tipo, nota se já estiver no aparelho), ficha de 3 campos (fila, preço, distância e
/// tempo, do `PlaceFicha`), até 2 amigos que foram, e **Ir agora · N min** / **Feito** / abrir o Lugar. V9: material do
/// sistema, texto do sistema; fechar e abrir são botões visíveis.
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
    @State private var carousel: PhotoCarousel?
    @State private var rating: KnownRating?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            photo
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(.title2.weight(.bold)).lineLimit(2).accessibilityAddTraits(.isHeader)
                if let tag = PlaceFicha.openTag(place, region: region, now: now) {
                    Text(tag).font(.subheadline.weight(.semibold))
                        .foregroundStyle(tag.hasPrefix("aberto") ? V9.accent : Color.secondary)
                }
                Text(MapCardFacts.meta(place, rating: rating, locale: region.locale))
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            fields
            friendsRow
            actions
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .task(id: place.id) { await load() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Abrir o lugar", onOpen)
        .accessibilityAction(.escape, onClose)
    }

    // MARK: Peças

    private var photo: some View {
        V8Photo(url: photoURL, placeholder: Color(.secondarySystemFill))
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .overlay(alignment: .bottomTrailing) {
                if photoURL != nil, let credit = MapCardPhoto.credit(place.photoRefs.first) {
                    Text(credit).font(.caption2).foregroundStyle(.white).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                // Toque na foto: todas as fotos do lugar em carrossel (sem foto, abre o Lugar como antes).
                if let pages = PhotoCarousel.place(placeId: place.placeId, refs: place.photoRefs, resolver: services?.photoResolver) {
                    carousel = pages
                } else {
                    onOpen()
                }
            }
            .photoCarousel($carousel)
    }

    private var fields: some View {
        let cells = MapCardFacts.cells(place, region: region, now: now, here: here, walkMaxKm: walkMaxKm)
        return HStack(alignment: .top, spacing: 12) {
            ForEach(cells, id: \.self) { cell in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.label).font(.caption).foregroundStyle(Color.secondary).lineLimit(1)
                    Text(cell.value).font(.body.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(2).monospacedDigit()
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
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(i == 0 ? Color(.systemBackground) : Color.primary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(i == 0 ? Color.primary : Color(.tertiarySystemFill)))
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                    }
                }
                Text(line).font(.subheadline).foregroundStyle(Color.secondary).lineLimit(2)
                if friends.isSample {
                    Text("exemplo").font(.caption2).foregroundStyle(Color.secondary).fixedSize()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            // Letra grande: "Ir · 21 min" sem ícone antes de cortar o texto.
            ViewThatFits(in: .horizontal) {
                Button(action: onGo) {
                    Label(goMinutes.map { "Ir agora · \($0) min" } ?? "Ir agora", systemImage: "figure.walk").lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .v9Primary()
                Button(action: onGo) { Text(goMinutes.map { "Ir · \($0) min" } ?? "Ir").lineLimit(1).frame(maxWidth: .infinity) }
                    .v9Primary()
            }
            .layoutPriority(1)
            Button(action: onDone) { Text(place.isDone ? "Feito ✓" : "Feito").lineLimit(1).fixedSize() }
                .v9Secondary()
                .disabled(place.isDone)
            Button(action: onOpen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").frame(minWidth: 22, minHeight: 22)
            }
            .v9Secondary()
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
