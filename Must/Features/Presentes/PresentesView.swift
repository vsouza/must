import CoreLocation
import SwiftData
import SwiftUI

/// Musts › Presentes (`design/v9/Presentes-Lista.png`): o numeral é quantos faltam; agrupado por pessoa (faixa de tinta com o
/// subtotal); linha laranja = dá pra comprar agora, perto. A caixa marca comprado e abre o painel do valor pago.
struct PresentesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    @Query(sort: [SortDescriptor(\Gift.createdAt)]) private var gifts: [Gift]
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]

    @State private var buying: Gift?
    @State private var editing: Gift?
    @State private var adding = false
    @State private var pendingDelete: Gift?

    private var region: Region { store.region }
    private var money: GiftMoney { GiftMoney(region: region, userRate: settingsList.first?.fxRate) }
    private var now: Date { AppClock.now }

    private var nearby: [GiftNearby] {
        GiftLogic.nearby(gifts: gifts, places: places, here: services.location.current?.coordinate, now: now, timeZone: region.timeZone)
    }

    var body: some View {
        let near = Dictionary(nearby.map { ($0.giftId, $0) }, uniquingKeysWith: { a, _ in a })
        let groups = GiftLogic.groups(gifts, nearby: Set(near.keys))
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    CutRule()
                    if gifts.isEmpty {
                        empty
                    } else {
                        summary
                        ForEach(groups) { group in
                            groupHeader(group)
                            ForEach(group.gifts) { gift in row(gift, near: near[gift.id]) }
                        }
                    }
                    V8BarSpacer()
                }
            }
            .scrollIndicators(.hidden)
            if let buying {
                GiftBoughtPanel(gift: buying, gifts: gifts, region: region, money: money,
                                storeName: GiftLogic.store(of: buying, places: places)?.name ?? buying.storeName,
                                onUndo: { GiftLogic.undoBought(buying, context: context); self.buying = nil },
                                onOk: { self.buying = nil })
                    .transition(.move(edge: .bottom))
            }
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .lightStatusBar()
        .onChange(of: buying?.id) { _, id in router.setQuero("presentes", open: id != nil) }
        .onDisappear { router.setQuero("presentes", open: false) }
        .sheet(isPresented: $adding) { PresenteNovoView() }
        .sheet(item: $editing) { gift in PresenteNovoView(editing: gift) }
        .confirmationDialog("Apagar este presente?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Apagar", role: .destructive) {
                if let gift = pendingDelete {
                    if gift.isBought { GiftLogic.undoBought(gift, context: context) }
                    context.delete(gift)
                    try? context.save()
                }
                pendingDelete = nil
            }
        }
        .onAppear { debugBuy() }
    }

    // MARK: Topo

    private var header: some View {
        CutBand(photo: nil) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    GiftSquareButton(systemName: "arrow.left", label: "Voltar") { dismiss() }
                    DayBandCorners(left: ["Musts · Presentes", "\(region.shortName) · \(GiftLogic.people(gifts).count) pessoas"], right: [])
                        .padding(.top, 4)
                    Spacer(minLength: 8)
                    GiftSquareButton(systemName: "sparkle", label: "Assistente") { router.sheet = .assistant }
                }
                Spacer(minLength: 8)
                Text("Presentes")
                    .font(V8Font.display(56))
                    .tracking(-1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .frame(minHeight: 190 * min(scale, 1.4))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Resumo

    private var summary: some View {
        let pending = GiftLogic.pendingCount(gifts)
        let bought = gifts.count - pending
        let total = GiftLogic.plannedTotal(gifts)
        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("\(gifts.count) \(gifts.count == 1 ? "item" : "itens") · \(GiftLogic.people(gifts).count) pessoas · \(bought) comprados",
                          size: 10, color: V8.mute)
                    .fixedSize(horizontal: false, vertical: true)
                Text("previsto \(money.text(total))\(money.brl(total).map { " · \($0)" } ?? "")")
                    .font(V8Font.text(16)).foregroundStyle(V8.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(pending)").font(V8Font.numeral(76)).tracking(-2).foregroundStyle(V8.orange).lineLimit(1)
                MonoLabel(pending == 1 ? "falta" : "faltam", size: 10, color: V8.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(pending) \(pending == 1 ? "falta" : "faltam")")
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }

    private func groupHeader(_ group: GiftGroup) -> some View {
        HStack {
            MonoLabel("\(group.person) · \(group.gifts.count)", size: 11, color: V8.white)
            Spacer(minLength: 8)
            MonoLabel(money.text(group.subtotal), size: 11, color: V8.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V8.ink)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Linha

    private func row(_ gift: Gift, near: GiftNearby?) -> some View {
        let store = GiftLogic.store(of: gift, places: places)
        let dim = gift.isBought
        let orange = near != nil && !dim
        return HStack(alignment: .center, spacing: 6) {
            GiftCheckbox(done: gift.isBought, onInk: false) { toggle(gift) }
                .padding(.leading, -6)
            Button { router.push(.presente(id: gift.id), on: .musts) } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(GiftLogic.titleWithQty(gift))
                            .font(V8Font.text(16, weight: .bold))
                            .strikethrough(dim)
                            .foregroundStyle(dim ? V8.ink.opacity(0.7) : V8.ink)
                            .lineLimit(2)
                        Text(meta(gift, storeName: store?.name))
                            .font(V8Font.text(13)).foregroundStyle(orange ? V8.ink.opacity(0.75) : V8.mute)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    trailing(gift, near: near, place: store?.place)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: 66)
        .background(orange ? V8.orange : V8.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
        .contextMenu {
            Button("Editar", systemImage: "pencil") { editing = gift }
            Button("Mudar pessoa", systemImage: "person") { editing = gift }
            Button("Apagar", systemImage: "trash", role: .destructive) { pendingDelete = gift }
        }
        .accessibilityElement(children: .contain)
    }

    private func meta(_ gift: Gift, storeName: String?) -> String {
        let name = storeName ?? (gift.storeName.isEmpty ? nil : gift.storeName)
        if gift.isBought {
            let paid = money.text(gift.paidPrice ?? gift.estimatedTotal)
            return ["comprado", name, paid].compactMap { $0 }.joined(separator: " · ")
        }
        let parts: [String?] = [name ?? (gift.chain ? "qualquer loja" : nil),
                                gift.estimatedPrice > 0 ? money.text(gift.estimatedTotal) : nil,
                                gift.source.metaLabel]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? "sem loja ainda" : text
    }

    @ViewBuilder private func trailing(_ gift: Gift, near: GiftNearby?, place: Place?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if gift.isBought {
                Text("feito").font(V8Font.mono(16, weight: .semibold)).foregroundStyle(V8.mute)
                if let at = gift.boughtAt {
                    MonoLabel("dia \(region.calendar.component(.day, from: at))", size: 9, color: V8.mute)
                }
            } else if let near {
                Text(Walk.distanceText(near.meters)).font(V8Font.mono(16, weight: .semibold)).foregroundStyle(V8.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                MonoLabel(openLabel(place), size: 9, color: V8.ink)
            } else if let area = place?.area, !area.isEmpty {
                Text(AreaCode.derive(area) ?? String(area.prefix(3)).uppercased())
                    .font(V8Font.mono(16, weight: .bold)).foregroundStyle(V8.ink)
            } else if gift.chain {
                MonoLabel("rede", size: 9, color: V8.mute)
            }
        }
        .fixedSize()
    }

    private func openLabel(_ place: Place?) -> String {
        guard let place else { return "perto" }
        if case .open(let until) = place.openState(at: now, timeZone: region.timeZone), let until {
            return "até \(ListGrouping.hourLabel(until))"
        }
        return "aberto"
    }

    // MARK: Ações

    private func toggle(_ gift: Gift) {
        if gift.isBought {
            GiftLogic.undoBought(gift, context: context)
            return
        }
        let store = GiftLogic.store(of: gift, places: places)?.place
        GiftLogic.markBought(gift, paid: gift.estimatedTotal, at: now, context: context, store: store)
        withAnimation(.snappy(duration: 0.25)) { buying = gift }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("0").font(V8Font.numeral(96)).foregroundStyle(V8.orange).accessibilityHidden(true)
            Text("Nenhum presente ainda").font(V8Font.display(30)).tracking(-0.8).foregroundStyle(V8.ink)
            Text("cole um link ou vídeo de algo que alguém pediu").font(V8Font.text(15)).foregroundStyle(V8.mute)
            Button { adding = true } label: {
                Text("+ PRESENTE").font(V8Font.mono(12, weight: .semibold)).tracking(1).foregroundStyle(V8.ink)
                    .padding(.horizontal, 16).padding(.vertical, 14).background(V8.orange).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func debugBuy() {
        #if DEBUG
        if DebugFlags.string("debugScreen") == "presente-comprado", buying == nil,
           let gift = gifts.first(where: { $0.id == PresenteDemo.kitKatId }) {
            if !gift.isBought { GiftLogic.markBought(gift, paid: 3_240, at: now, context: context, store: GiftLogic.store(of: gift, places: places)?.place) }
            buying = gift
        }
        #endif
    }
}
