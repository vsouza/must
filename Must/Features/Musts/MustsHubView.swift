import SwiftData
import SwiftUI

/// Hub "Musts": grid de listas, busca e "Fica pro fim".
struct MustsHubView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query(sort: \Place.name) private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var query = ""

    private var doneCount: Int { places.filter(\.isDone).count }
    private var saveForEnd: [Place] { places.filter { $0.saveForEnd && !$0.isDone } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar.padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Musts").mustTitle()
                    Text("o board, por vontade — não por bairro").mustSerif(18).foregroundStyle(Color.must.secondary)
                }
                .padding(.top, 20)

                searchField.padding(.top, 24)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    grid.padding(.top, 18)
                    if !saveForEnd.isEmpty { saveForEndCard.padding(.top, 16) }
                } else {
                    results.padding(.top, 18)
                }
                TabBarSpacer()
            }
            .padding(.horizontal, 22)
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .background {
            ZStack {
                Color.must.bg
                BlobBackground(style: .musts)
            }
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack {
            Color.clear.frame(width: 40, height: 40)
            Spacer()
            Micro("\(places.count) lugares · \(doneCount) feitos")
            Spacer()
            IconButton(.adicionar, style: .dark, label: "Adicionar por link") { router.sheet = .addLink(url: nil, listId: nil) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            MustIconView(.buscar, size: 16).foregroundStyle(Color.must.secondary)
            TextField("Buscar lugar, bairro, prato…", text: $query)
                .font(.must.archivo(14))
                .foregroundStyle(Color.must.ink)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { MustIconView(.fechar, size: 14).foregroundStyle(Color.must.secondary) }
                    .accessibilityLabel("Limpar busca")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Capsule().fill(Color(hex: 0xF1F2F4, opacity: 0.9)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.7)))
        .shadow(color: Color(hex: 0x121316, opacity: 0.06), radius: 12, x: 0, y: 8)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(lists) { list in
                Button { router.push(.list(id: list.id), on: .musts) } label: { ListTile(list: list) }
                    .buttonStyle(MustPressStyle())
            }
            Button { router.cover = .newList } label: {
                VStack(spacing: 8) {
                    MustIconView(.adicionar, size: 22)
                    Text("Nova lista").font(.must.archivo(14))
                }
                .foregroundStyle(Color.must.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 136)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(hex: 0xD5D8DD), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 22))
            }
            .buttonStyle(MustPressStyle())
        }
    }

    private var saveForEndCard: some View {
        Button { router.push(.saveForEnd, on: .musts) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.must.ink)
                    Text("済").font(.must.kanji(15)).foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fica pro fim · \(saveForEnd.count)").font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
                    Text(saveForEndLine).font(.must.meta).foregroundStyle(Color.must.secondary).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                MustIconView(.avancar, size: 14).foregroundStyle(Color.must.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(MustPressStyle())
    }

    private var saveForEndLine: String {
        let names = saveForEnd.prefix(3).map(\.name).joined(separator: ", ")
        let suffix = trips.first?.hasTrip == true ? "entram nos últimos dias" : "quando você pedir"
        return "\(names)\(saveForEnd.count > 3 ? "…" : "") \(suffix)"
    }

    private var results: some View {
        let found = places.filter { $0.matches(query) }
        return Group {
            if found.isEmpty {
                Text("Nada com “\(query)” no board.").mustMeta().padding(.vertical, 20)
            } else {
                PlaceListCard(places: found, region: store.region, trip: trips.first, location: services.location.current,
                              onOpen: { router.push(.place(id: $0.id), on: .musts) },
                              onEdit: { router.sheet = .editPlace(id: $0.id) })
            }
        }
    }
}

/// Tile de uma lista no hub (136 pt): foto tingida ou gradiente, ícone, kanji, contagem.
struct ListTile: View {
    var list: MustList
    var height: CGFloat = 136
    /// Prévia na Nova lista: força a contagem e o subtítulo.
    var previewCount: Int?
    var previewSubtitle: String?
    var photoURL: URL?

    private var color: MustColor { list.color }
    private var url: URL? { photoURL ?? list.photo?.url.flatMap(URL.init(string:)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TintedPhoto(url: url, color: color)
            VStack(alignment: .leading, spacing: 0) {
                MustIconView(list.icon, size: 18)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.55)))
                Spacer(minLength: 0)
                MonoNumber("\(previewCount ?? list.places.count)", size: 28)
                Text(list.displayName).font(.must.archivo(17, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(previewSubtitle ?? subtitle).font(.must.archivo(11.5)).opacity(0.8).lineLimit(1)
                    .padding(.trailing, url != nil ? 30 : 0)
            }
            .foregroundStyle(color.text)
            .padding(14)
        }
        .overlay(alignment: .topTrailing) {
            if let kanji = list.kanji, !kanji.isEmpty {
                Text(kanji).font(.must.kanji(28)).foregroundStyle(color.text).opacity(0.3)
                    .padding(.top, 10).padding(.trailing, 14)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if url != nil { Credit("CC", color: color.text).padding(.trailing, 8).padding(.bottom, 6) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let done = list.places.filter(\.isDone).count
        var parts = list.subs.compactMap { sub -> String? in
            let n = list.places.filter { $0.sub == sub }.count
            return n > 0 ? "\(sub) \(n)" : nil
        }
        parts.append(done == 1 ? "1 feito" : "\(done) feitos")
        return parts.joined(separator: " · ")
    }
}
