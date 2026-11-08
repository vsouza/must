import SwiftData
import SwiftUI

/// Experiências (design: Experiencias.png). Só colando link ou à mão (decisão de 02/11/2026).
struct ExperiencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(\.tripTheme) private var theme

    @Query private var places: [Place]

    @State private var query = ""
    @State private var chip: ExperienceListModel.Chip = .any
    @State private var linking = false

    private var region: Region { store.region }

    var body: some View {
        let rows = ExperienceListModel.rows(places: places, query: query, chip: chip, region: region, now: AppClock.now)
        CutPage(title: "Experiências", corner: ["Must do · \(region.displayName)", "\(rows.count) salvas"],
                subtitle: "Aulas, tours, ingressos. Com hora marcada, viram âncora.", height: 220, onBack: { dismiss() },
                trailing: {
            // Ingressos e reservas (Reservas mostra os ingressos).
            CutCornerButton(systemName: "ticket", label: "Ingressos", tint: theme.coverInk) { router.push(.reservations, on: .musts) }
        }) {
            CutSearchField(text: $query, placeholder: "Buscar experiência, fornecedor…") { EmptyView() }
                .padding(.horizontal, 20)
            chips.padding(.vertical, 14)
            IndexRule()
            linkCard

            if rows.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        ExperienceRowCard(row: row, region: region,
                                          onOpen: { router.push(.place(id: row.place.id), on: .musts) })
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .sheet(isPresented: $linking) { ExperienceLinkSheet() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ExperienceListModel.Chip.allCases) { option in
                    Button { chip = option } label: { Pill(option.rawValue, isOn: chip == option) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var linkCard: some View {
        Button { linking = true } label: {
            CutRow(title: "Achou no Airbnb, Klook ou GetYourGuide? Cola o link",
                   detail: "eu leio título, preço, duração e ponto de encontro", tone: .orange) {
                MustIconView(.colarLink, size: 20).foregroundStyle(V8.ink)
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(query.isEmpty ? "Nenhuma experiência salva ainda." : "Nenhuma experiência com “\(query)”.")
                .font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink)
            Text("Cola o link de um tour ou de uma aula acima. Ela entra na Must do, com data e horário se a página trouxer.")
                .font(V8Font.text(14)).foregroundStyle(V8.mute)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Uma experiência salva: miniatura tingida na cor da lista, fornecedor, meta, preço, sessão e conflito.
struct ExperienceRowCard: View {
    @Environment(\.openURL) private var openURL

    var row: ExperienceListModel.Row
    var region: Region
    var onOpen: () -> Void

    private var info: ExperienceInfo? { row.place.extra?.experience }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TintedPhoto(url: info?.imageURL, color: .night)
                Tag(ExperienceSupplier.badge(info?.supplier ?? .other, url: info?.url), style: .dark)
                    .padding(8)
            }
            .frame(width: 118)
            .frame(maxHeight: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.place.name).font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text(metaLine).font(.must.meta).foregroundStyle(Color.must.secondary).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    Text(priceText).font(.must.mono(15, .semibold)).foregroundStyle(Color.must.ink)
                    if let session = row.session {
                        Pill("\(region.shortDayTime(session.at))\(session.bought ? " · ingresso" : " · livre")", style: .green)
                    }
                }
                if let conflict = row.conflicts.first {
                    Text(conflict)
                        .font(V8Font.mono(11, weight: .semibold))
                        .foregroundStyle(V8.paper)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Rectangle().fill(V8.ink))
                }
                if let url = info?.url {
                    Button { openURL(url) } label: {
                        Text("Ver no \(ExperienceSupplier.badge(info?.supplier ?? .other, url: url))")
                            .font(.must.archivo(13, .semibold)).foregroundStyle(Color.must.link)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 176, alignment: .leading)
        .clipShape(Rectangle())
        .overlay(alignment: .bottom) { IndexRule() }
    }

    /// "3h · grupo até 8 · em inglês · ★ 4,9 · 1.240"
    private var metaLine: String {
        var parts: [String] = []
        if let minutes = info?.durationMinutes { parts.append(KindLines.duration(minutes)) }
        if let group = info?.groupMax { parts.append("grupo até \(group)") }
        if let language = info?.languages.first { parts.append("em \(language)") }
        if let rating = info?.rating {
            parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1)).locale(region.locale)))"
                         + (info?.reviewCount.map { " · \($0.formatted(.number.locale(region.locale)))" } ?? ""))
        }
        if info?.url == nil { parts.append("colado por link") }
        return parts.joined(separator: " · ")
    }

    private var priceText: String {
        guard let price = info?.priceFrom else { return "—" }
        if let code = info?.currency, code != region.currency {
            return price.formatted(.currency(code: code).locale(region.locale).precision(.fractionLength(0)))
        }
        return region.money(price)
    }
}
