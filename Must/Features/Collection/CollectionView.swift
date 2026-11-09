import SwiftData
import SwiftUI

/// Coleção (V9, `List` nativa): um card por "feito". Agrupar por cidade/lista, Organizar (fixar até 3 na
/// Vitrine, esconder), seções com contagem ("Tóquio 14 de 52"), grade de 3 colunas e espaços tracejados "a fazer".
/// Tudo derivado de `Place.done`; nada vai pra rede.
struct CollectionView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(\.modelContext) private var context

    @Query private var places: [Place]

    @State private var group: CollectionPrefs.Group = .city
    @State private var organizing = false
    @State private var pinned: [String] = []
    @State private var hidden: [String] = []
    @State private var detail: Collectible?
    @State private var loaded = false

    private var region: Region { store.region }
    private var prefs: CollectionPrefs { CollectionPrefs(regionId: region.rawValue) }
    private var tint: Color { CollectibleTint.color(region) }

    var body: some View {
        let slots = Self.slots(places, region: region)
        let hiddenSet = Set(hidden)
        let sections = CollectionGrouping.sections(slots, by: group, hidden: hiddenSet, timeZone: region.timeZone)
        let showcase = CollectionGrouping.showcase(slots, pinned: pinned, hidden: hiddenSet)
        let done = slots.compactMap(\.collectible)
        let rare = done.filter(\.isRare).count

        List {
            Section {
                Text("\(done.count) feitos de \(slots.count) · \(rare) raros · \(region.countryName)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Agrupar por", selection: Binding(get: { group }, set: { group = $0; prefs.group = $0 })) {
                    ForEach(CollectionPrefs.Group.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if done.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nada na coleção ainda.").font(.headline)
                        Text("Cada lugar que você marca como feito vira um card, com número, bairro e data. Os com ingresso ou reserva são os raros.")
                            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                if !showcase.isEmpty || organizing { vitrine(showcase) }
                ForEach(sections) { section in sectionView(section) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Coleção")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(organizing ? "Pronto" : "Organizar") { withAnimation(.snappy) { organizing.toggle() } }
            }
        }
        .v9Screen(grouped: true)
        .sheet(item: $detail) { item in CollectibleDetailView(item: item, tint: tint) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            group = prefs.group; pinned = prefs.pinned; hidden = prefs.hidden
        }
        #if DEBUG
        .task { CollectionDemo.ensure(context: context, region: region) }
        #endif
    }

    // MARK: Vitrine e seções

    private func vitrine(_ items: [Collectible]) -> some View {
        Section {
            if items.isEmpty {
                Text("Toque num card em Organizar pra fixar até 3 aqui.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(items) { item in
                            card(item, width: 150, height: 150, compactNumeral: false)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: V9.gutter, bottom: 8, trailing: V9.gutter))
            }
        } header: {
            sectionHeader("Vitrine", right: "\(items.count) fixados")
        }
    }

    private func sectionView(_ section: CollectionSection) -> some View {
        Section {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(section.done) { item in card(item, width: 106, height: 138, compactNumeral: true) }
                    ForEach(section.todo) { slot in todoCard(slot) }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: V9.gutter, bottom: 8, trailing: V9.gutter))
        } header: {
            sectionHeader(section.title, right: section.total.map { "\(section.done.count) de \($0)" } ?? "\(section.done.count)")
        }
    }

    private func sectionHeader(_ title: String, right: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(.primary).textCase(nil).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(right).font(.footnote.monospacedDigit()).textCase(nil)
        }
    }

    private func card(_ item: Collectible, width: CGFloat, height: CGFloat, compactNumeral: Bool) -> some View {
        let isPinned = pinned.contains(item.id)
        return Button {
            if organizing { togglePin(item.id) } else { detail = item }
        } label: {
            MiniCollectibleCard(item: item, tint: tint, width: width, height: height)
                .overlay(alignment: .topLeading) {
                    if organizing { organizeBadge(item, pinned: isPinned) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title), nº \(item.order)\(item.isRare ? ", raro" : "")")
        .accessibilityHint(organizing ? "Fixar na vitrine" : "Abrir o card")
    }

    private func organizeBadge(_ item: Collectible, pinned isPinned: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isPinned ? "pin.fill" : "pin").font(.footnote.weight(.bold))
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
                .foregroundStyle(isPinned ? V9.accent : Color.primary)
            Button { toggleHidden(item.id) } label: {
                Image(systemName: "eye.slash").font(.footnote.weight(.bold))
                    .frame(width: 32, height: 32).background(.regularMaterial, in: Circle()).foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Esconder")
        }
        .padding(6)
    }

    private func todoCard(_ slot: CollectionSlot) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: 106, height: 138)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("A fazer").font(.caption).foregroundStyle(.secondary)
                    Text(CollectibleText.latinOnly(slot.name)).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(10)
            }
            .accessibilityElement(children: .combine)
    }

    // MARK: Ações e dados

    private func togglePin(_ id: String) {
        prefs.togglePin(id)
        pinned = prefs.pinned
    }

    private func toggleHidden(_ id: String) {
        prefs.toggleHidden(id)
        pinned = prefs.pinned
        hidden = prefs.hidden
    }

    @MainActor
    static func slots(_ places: [Place], region: Region) -> [CollectionSlot] {
        places.map { p in
            CollectionSlot(placeId: p.id, name: p.name, cityId: p.cityId, cityName: CollectibleText.cityName(cityId: p.cityId),
                           listId: p.list?.id ?? "", listName: p.list?.displayName ?? "Sem lista",
                           collectible: Collectible.make(from: p, in: places, region: region))
        }
    }
}

/// Miniatura do card (grade e vitrine): o mesmo desenho do card grande, em SwiftUI direto, leve.
struct MiniCollectibleCard: View {
    var item: Collectible
    var tint: Color
    var width: CGFloat
    var height: CGFloat

    private var bg: Color { item.variant == .trip ? tint : (item.variant == .anchor ? V8.ink : V8.paper) }
    private var fg: Color { item.variant == .outdoor ? V8.ink : V8.white }
    private var numeralColor: Color { item.variant == .trip ? V8.white : (item.variant == .anchor && width < 130 ? V8.white : V8.orange) }

    var body: some View {
        let big = width >= 130
        ZStack(alignment: .topLeading) {
            bg
            Rectangle().stroke(fg.opacity(0.4), lineWidth: 1).frame(width: width * 0.9, height: width * 0.9)
                .offset(x: -width * 0.35, y: height * 0.38)
            Text(CollectibleText.number(item.order).suffix(2))
                .font(V8Font.numeral(big ? 80 : 64)).tracking(big ? -4.8 : -3.8)
                .foregroundStyle(numeralColor)
                .fixedSize()
                .frame(height: (big ? 80 : 64) * 0.78, alignment: .top)
                .frame(width: width - 8, alignment: .trailing)
                .padding(.top, big ? 14 : 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Spacer(minLength: 0)
                Text(CollectibleText.latinOnly(item.title))
                    .font(Font(V8Fonts.bricolage(big ? 22 : 17, weight: 800, width: 82, opticalSize: 40)))
                    .foregroundStyle(fg).lineLimit(1).minimumScaleFactor(0.6)
                Text([item.area.map(CollectibleText.latinOnly), big ? CollectibleText.dateLabel(item.doneAt, timeZoneId: item.timeZoneId, withYear: false) : nil]
                    .compactMap { $0 }.joined(separator: " · ").uppercased())
                    .font(V8Font.mono(8.5)).tracking(0.8).foregroundStyle(fg.opacity(0.75)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
            .frame(width: width, height: height, alignment: .bottomLeading)
        }
        .frame(width: width, height: height)
        .clipShape(Rectangle())
        .overlay { if item.variant == .outdoor { Rectangle().strokeBorder(V8.ink, lineWidth: 1.5) } }
    }
}
