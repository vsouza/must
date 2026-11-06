import SwiftData
import SwiftUI

/// Coleção (`Colecao.png`): um card por "feito". Título + numeral, Cidade · Lista · Data, Organizar (fixar até 3 na
/// Vitrine, esconder), seções com contagem ("Tóquio 14 de 52"), grade de 3 colunas e espaços tracejados "a fazer".
/// Tudo derivado de `Place.done`; nada vai pra rede.
struct CollectionView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(done: done.count, total: slots.count, rare: rare).padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("Coleção")
                        .font(V8Font.display(52)).tracking(-1.6).foregroundStyle(V8.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    BigNumeral("\(done.count)", size: 74, color: V8.orange)
                }
                .padding(.top, 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Coleção: \(done.count) feitos")
                controls.padding(.top, 20)
                if done.isEmpty {
                    empty.padding(.top, 30)
                } else {
                    if !showcase.isEmpty || organizing { vitrine(showcase).padding(.top, 28) }
                    ForEach(sections) { section in
                        sectionView(section).padding(.top, 26)
                    }
                }
                V8BarSpacer()
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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

    // MARK: Topo

    private func header(done: Int, total: Int, rare: Int) -> some View {
        HStack(alignment: .top) {
            V8SpecStack(lines: ["Coleção · \(region.countryName)", "\(done) feitos de \(total)"])
            Spacer(minLength: 12)
            V8SpecStack(lines: [CollectibleText.dateLabel(AppClock.now, timeZoneId: region.timeZone.identifier, withYear: true)
                .split(separator: " ").dropFirst().joined(separator: " "), "\(rare) raros"], alignment: .trailing)
        }
        .padding(.trailing, 0)
        .overlay(alignment: .topTrailing) { EmptyView() }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(CollectionPrefs.Group.allCases, id: \.self) { g in
                    Button {
                        group = g
                        prefs.group = g
                    } label: {
                        Text(g.label)
                            .font(V8Font.text(15, weight: .bold))
                            .foregroundStyle(group == g ? V8.white : V8.ink)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(group == g ? V8.ink : .clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(group == g ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Capsule().fill(V8.white))
            .overlay(Capsule().strokeBorder(V8.rule, lineWidth: 1))
            Spacer(minLength: 0)
            Button { withAnimation(.snappy) { organizing.toggle() } } label: {
                Text(organizing ? "Pronto" : "Organizar")
                    .font(V8Font.text(15, weight: .bold))
                    .foregroundStyle(organizing ? V8.white : V8.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(organizing ? V8.ink : .clear))
                    .overlay(Capsule().strokeBorder(V8.ink, lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nada na coleção ainda.").font(V8Font.display(26)).foregroundStyle(V8.ink)
            Text("Cada lugar que você marca como feito vira um card, com número, bairro e data. Os com ingresso ou reserva são os raros.")
                .font(V8Font.text(15)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Vitrine e seções

    private func vitrine(_ items: [Collectible]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Vitrine", right: "\(items.count) fixados")
            if items.isEmpty {
                Text("Toque num card em Organizar pra fixar até 3 aqui.").font(V8Font.text(14)).foregroundStyle(V8.mute)
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(items) { item in
                        card(item, width: 150, height: 150, compactNumeral: false)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func sectionView(_ section: CollectionSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(section.title, right: section.total.map { "\(section.done.count) de \($0)" } ?? "\(section.done.count)")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(section.done) { item in card(item, width: 106, height: 138, compactNumeral: true) }
                    ForEach(section.todo) { slot in todoCard(slot) }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func sectionHeader(_ title: String, right: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(V8Font.display(26)).foregroundStyle(V8.ink).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            SpecLabel(right, color: V8.mute)
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
        .buttonStyle(MustPressStyle())
        .accessibilityLabel("\(item.title), nº \(item.order)\(item.isRare ? ", raro" : "")")
        .accessibilityHint(organizing ? "Fixar na vitrine" : "Abrir o card")
    }

    private func organizeBadge(_ item: Collectible, pinned isPinned: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isPinned ? "pin.fill" : "pin").font(.system(size: 13, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(isPinned ? V8.orange : V8.white)).foregroundStyle(V8.ink)
            Button { toggleHidden(item.id) } label: {
                Image(systemName: "eye.slash").font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28).background(Circle().fill(V8.white)).foregroundStyle(V8.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Esconder")
        }
        .padding(8)
    }

    private func todoCard(_ slot: CollectionSlot) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(V8.mute.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: 106, height: 138)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    SpecLabel("A fazer", color: V8.mute)
                    Text(CollectibleText.latinOnly(slot.name)).font(V8Font.text(14, weight: .semibold)).foregroundStyle(V8.mute).lineLimit(2)
                }
                .padding(12)
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
            Circle().stroke(fg.opacity(0.4), lineWidth: 1).frame(width: width * 0.9, height: width * 0.9)
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
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { if item.variant == .outdoor { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(V8.ink, lineWidth: 1.5) } }
    }
}
