import SwiftData
import SwiftUI

/// Experiências (design: Experiencias.png). Só colando link ou à mão (decisão de 02/11/2026).
struct ExperiencesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store

    @Query private var places: [Place]

    @State private var query = ""
    @State private var chip: ExperienceListModel.Chip = .any
    @State private var linking = false

    private var region: Region { store.region }

    var body: some View {
        let rows = ExperienceListModel.rows(places: places, query: query, chip: chip, region: region, now: AppClock.now)
        List {
            Section {
                Picker("Filtro", selection: $chip) {
                    ForEach(ExperienceListModel.Chip.allCases) { option in Text(option.rawValue).tag(option) }
                }
                .pickerStyle(.menu)
                Button { linking = true } label: {
                    Label("Colar o link de uma experiência", systemImage: "link")
                }
            } footer: {
                Text("Achou no Airbnb, Klook ou GetYourGuide? Eu leio título, preço, duração e ponto de encontro. Com hora marcada, vira âncora do dia.")
            }
            if rows.isEmpty {
                Section { emptyState }
            } else {
                Section("\(rows.count) \(rows.count == 1 ? "salva" : "salvas")") {
                    ForEach(rows) { row in
                        ExperienceRowCard(row: row, region: region,
                                          onOpen: { router.push(.place(id: row.place.id), on: .musts) })
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "Buscar experiência, fornecedor…")
        .navigationTitle("Experiências")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Ingressos e reservas (Reservas mostra os ingressos).
                Button("Ingressos", systemImage: "ticket") { router.push(.reservations, on: .musts) }
            }
        }
        .v9Screen(grouped: true)
        .scrollDismissesKeyboard(.immediately)
        .onAppear {
            #if DEBUG
            if DebugFlags.string("debugScreen") == "experiencia-link" { linking = true }
            #endif
        }
        .sheet(isPresented: $linking) { ExperienceLinkSheet() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(query.isEmpty ? "Nenhuma experiência salva ainda." : "Nenhuma experiência com “\(query)”.").font(.headline)
            Text("Cola o link de um tour ou de uma aula acima. Ela entra na Must do, com data e horário se a página trouxer.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
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
        HStack(alignment: .top, spacing: 12) {
            TintedPhoto(url: info?.imageURL, color: .night)
                .frame(width: V9.thumb, height: V9.thumb)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.place.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text(metaLine).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    Text(priceText).font(.subheadline.weight(.semibold)).monospacedDigit()
                    if let session = row.session {
                        J9Tag(text: "\(region.shortDayTime(session.at))\(session.bought ? " · ingresso" : " · livre")", filled: true)
                    }
                }
                if let conflict = row.conflicts.first {
                    Text(conflict).font(.footnote).foregroundStyle(.red)
                }
                if let url = info?.url {
                    Button("Ver no \(ExperienceSupplier.badge(info?.supplier ?? .other, url: url))") { openURL(url) }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
