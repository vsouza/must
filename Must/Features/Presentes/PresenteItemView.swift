import CoreLocation
import SwiftData
import SwiftUI

/// Detalhe do presente (V9, `List` nativa): ficha em linhas (pra quem, quanto, onde, veio de,
/// tax-free, nota) e a barra Ir · Comprado.
struct PresenteItemView: View {
    var giftId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.openURL) private var openURL

    @Query private var gifts: [Gift]
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]

    @State private var buying = false
    @State private var editing = false

    private var region: Region { store.region }
    private var money: GiftMoney { GiftMoney(region: region, userRate: settingsList.first?.fxRate) }
    private var gift: Gift? { gifts.first { $0.id == giftId } }

    var body: some View {
        Group {
            if let gift { content(gift) } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .v9Screen(grouped: true)
        .onChange(of: buying) { _, on in router.setQuero("presente-item", open: on) }
        .onDisappear { router.setQuero("presente-item", open: false) }
        .sheet(isPresented: $editing) { if let gift { PresenteNovoView(editing: gift) } }
    }

    private func content(_ gift: Gift) -> some View {
        let store = GiftLogic.store(of: gift, places: places)
        let mine = gifts.filter { $0.personName == gift.personName }
        let others = mine.filter { $0.id != gift.id }
        let who = gift.personName == GiftLogic.noPerson ? "essa pessoa" : gift.personName
        return List {
            Section {
                row("Pra quem", title: gift.personName == GiftLogic.noPerson ? "Ninguém ainda" : gift.personName,
                    sub: others.isEmpty ? nil : "mais \(others.count) \(others.count == 1 ? "item" : "itens") pra \(who): "
                        + others.prefix(2).map { "\($0.title.lowercased())\($0.isBought ? " (comprado)" : "")" }.joined(separator: ", "))
                row("Quanto", title: quanto(gift), sub: money.brl(gift.estimatedTotal).map { "\($0) · câmbio de Ajustes" })
                whereLine(gift, store: store)
                if let origin = originLine(gift) { origin }
                if let taxFree = GiftLogic.taxFree(for: gift, among: gifts, on: AppClock.now, calendar: region.calendar,
                                                  currency: region.currency, extra: gift.estimatedTotal), !gift.isBought {
                    taxFreeLine(taxFree)
                }
                if !gift.note.isEmpty { row("Nota", title: gift.note, sub: nil) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(gift.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar") { editing = true }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if buying {
                GiftBoughtPanel(gift: gift, gifts: gifts, region: region, money: money, storeName: store?.name ?? gift.storeName,
                                onUndo: { GiftLogic.undoBought(gift, context: context); buying = false },
                                onOk: { buying = false })
                    .transition(.move(edge: .bottom))
            } else {
                actions(gift, store: store)
            }
        }
        .onAppear {
            #if DEBUG
            if DebugFlags.string("debugScreen") == "presente-item-comprado" { toggleBought(gift) }
            #endif
        }
    }

    // MARK: Ficha

    private func row(_ label: String, title: String, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Text(title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let sub { Text(sub).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func quanto(_ gift: Gift) -> String {
        if gift.quantity > 1 { return "\(money.text(gift.estimatedPrice)) × \(gift.quantity) = \(money.text(gift.estimatedTotal))" }
        return gift.estimatedPrice > 0 ? money.text(gift.estimatedPrice) : "sem preço"
    }

    @ViewBuilder private func whereLine(_ gift: Gift, store: (name: String, id: String?, coordinate: CLLocationCoordinate2D, place: Place?)?) -> some View {
        if let store {
            let near = nearbyRow(gift)
            Button {
                if let id = store.id { router.push(.place(id: id), on: .musts) }
            } label: {
                HStack {
                    row("Onde", title: store.name,
                        sub: near.map { "\(Walk.distanceText($0.meters)) · \($0.minutes) min a pé · \($0.isOpen ? "aberto" : "fechado")" } ?? "fora do alcance a pé agora")
                    if store.id != nil { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            row("Onde", title: gift.chain && !gift.storeName.isEmpty ? "Qualquer \(gift.storeName)" : "Sem loja ainda",
                sub: gift.chain ? "avisa perto de qualquer loja da rede" : "escolha uma loja ao editar")
        }
    }

    private func nearbyRow(_ gift: Gift) -> GiftNearby? {
        GiftLogic.nearby(gifts: [gift], places: places, here: services.location.current?.coordinate, now: AppClock.now,
                         timeZone: region.timeZone).first
    }

    private func originLine(_ gift: Gift) -> AnyView? {
        guard gift.source != .name || gift.sourceURL != nil else { return nil }
        let title: String
        switch gift.source {
        case .video: title = "Vídeo\(gift.sourceLabel.isEmpty ? "" : " · \(gift.sourceLabel)")"
        case .link: title = gift.sourceLabel.isEmpty ? "Link" : "Link · \(gift.sourceLabel)"
        case .place: title = "Loja do board"
        case .photo: title = "Foto"
        case .name: title = "Nome"
        }
        let sub = [gift.videoClip.map { "trecho \($0)" }, gift.sourceURL != nil ? "abre no navegador" : nil].compactMap { $0 }.joined(separator: " · ")
        return AnyView(
            Button {
                if let url = gift.sourceURL.flatMap(URL.init(string:)) { openURL(url) }
            } label: {
                HStack {
                    row("Veio de", title: title, sub: sub.isEmpty ? nil : sub)
                    if gift.sourceURL != nil { Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(gift.sourceURL == nil)
        )
    }

    private func taxFreeLine(_ taxFree: GiftLogic.TaxFree) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tax-free").font(.footnote).foregroundStyle(.secondary)
            Text(taxFree.reached ? "Já vale nessa loja" : "Faltam \(money.text(taxFree.missing)) nessa loja")
                .font(.body.weight(.semibold))
            Text("\(money.text(taxFree.minimum)) por loja no dia, com passaporte").font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: min(1, max(0, taxFree.fraction))).tint(V9.accent).padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Ações

    private func actions(_ gift: Gift, store: (name: String, id: String?, coordinate: CLLocationCoordinate2D, place: Place?)?) -> some View {
        HStack(spacing: 12) {
            if let store, !gift.isBought {
                let minutes = nearbyRow(gift)?.minutes
                Button { MapsLinks.openApple(to: store.coordinate, name: store.name) } label: {
                    Text("Ir\(minutes.map { " · \($0) min" } ?? "")").frame(maxWidth: .infinity)
                }
                .v9Primary()
            }
            Button { toggleBought(gift) } label: {
                Text(gift.isBought ? "Desfazer" : "Marcar comprado").frame(maxWidth: .infinity)
            }
            .modifier(BoughtButtonStyle(prominent: gift.isBought || store == nil))
        }
        .padding(.horizontal, V9.gutter).padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func toggleBought(_ gift: Gift) {
        if gift.isBought {
            GiftLogic.undoBought(gift, context: context)
            return
        }
        let place = GiftLogic.store(of: gift, places: places)?.place
        GiftLogic.markBought(gift, paid: gift.estimatedTotal, at: AppClock.now, context: context, store: place)
        withAnimation(.snappy(duration: 0.25)) { buying = true }
    }
}

private struct BoughtButtonStyle: ViewModifier {
    var prominent: Bool
    func body(content: Content) -> some View {
        if prominent { content.v9Primary() } else { content.v9Secondary() }
    }
}
