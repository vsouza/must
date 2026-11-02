import SwiftData
import SwiftUI

/// Experiências (design: Experiencias.png). Só colando link ou à mão (decisão de 02/11/2026).
struct ExperiencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store

    @Query private var places: [Place]

    @State private var query = ""
    @State private var chip: ExperienceListModel.Chip = .any
    @State private var linking = false

    private var region: Region { store.region }

    var body: some View {
        let rows = ExperienceListModel.rows(places: places, query: query, chip: chip, region: region, now: AppClock.now)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar.padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Experiências").mustTitle()
                    Text("aulas, tours, ingressos — com hora marcada, viram âncora").mustSerif(18).foregroundStyle(Color.must.secondary)
                }
                .padding(.top, 22)

                SearchPill(text: $query, placeholder: "Buscar experiência, fornecedor…").padding(.top, 20)
                chips.padding(.top, 14)
                linkCard.padding(.top, 18)

                if rows.isEmpty {
                    emptyState.padding(.top, 26)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(rows) { row in
                            ExperienceRowCard(row: row, region: region,
                                              onOpen: { router.push(.place(id: row.place.id), on: .musts) })
                        }
                    }
                    .padding(.top, 18)
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
        .sheet(isPresented: $linking) { ExperienceLinkSheet() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            IconButton(.voltar, label: "Voltar") { dismiss() }
            Spacer()
            Micro("Must do · \(region.displayName)")
            Spacer()
            // Ingressos e reservas (Reservas mostra os ingressos).
            IconButton(.reservaAncora, style: .dark, label: "Ingressos") { router.push(.reservations, on: .musts) }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ExperienceListModel.Chip.allCases) { option in
                    Button { chip = option } label: { Pill(option.rawValue, isOn: chip == option) }
                        .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var linkCard: some View {
        Button { linking = true } label: {
            HStack(spacing: 14) {
                MustIconView(.colarLink, size: 18)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.must.blue))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Achou no Airbnb, Klook ou GetYourGuide? Cola o link")
                        .font(.must.archivo(15, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .multilineTextAlignment(.leading)
                    Text("eu leio título, preço, duração e ponto de encontro").font(.must.meta).foregroundStyle(Color.must.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(MustPressStyle())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(query.isEmpty ? "Nenhuma experiência salva ainda." : "Nenhuma experiência com “\(query)”.")
                .font(.must.archivo(15, .semibold))
                .foregroundStyle(Color.must.ink)
            Text("Cola o link de um tour ou de uma aula acima. Ela entra na Must do, com data e horário se a página trouxer.")
                .font(.must.meta).foregroundStyle(Color.must.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
                        .font(.must.mono(12, .semibold))
                        .foregroundStyle(Color.must.blueText)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.must.blue.opacity(0.14)))
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
        .frame(height: 176, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.must.line))
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
