import CoreLocation
import SwiftData
import SwiftUI

/// Detalhe do presente (`design/v9/Presentes-Item.png`): bloco com o nome, ficha em linhas (pra quem, quanto, onde, veio de,
/// tax-free, nota) e a barra Ir · Comprado.
struct PresenteItemView: View {
    var giftId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

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
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .lightStatusBar()
        .onChange(of: buying) { _, on in router.setQuero("presente-item", open: on) }
        .onDisappear { router.setQuero("presente-item", open: false) }
        .sheet(isPresented: $editing) { if let gift { PresenteNovoView(editing: gift) } }
    }

    private func content(_ gift: Gift) -> some View {
        let store = GiftLogic.store(of: gift, places: places)
        let mine = gifts.filter { $0.personName == gift.personName }
        let position = (mine.firstIndex { $0.id == gift.id } ?? 0) + 1
        let others = mine.filter { $0.id != gift.id }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    band(gift, storeName: store?.name, position: position, count: mine.count)
                    CutRule()
                    line("Pra quem", title: gift.personName == GiftLogic.noPerson ? "Ninguém ainda" : gift.personName,
                         sub: others.isEmpty ? nil : "mais \(others.count) \(others.count == 1 ? "item" : "itens") pra \(gift.personName == GiftLogic.noPerson ? "essa pessoa" : gift.personName): "
                            + others.prefix(2).map { "\($0.title.lowercased())\($0.isBought ? " (comprado)" : "")" }.joined(separator: ", "))
                    line("Quanto", title: quanto(gift), sub: money.brl(gift.estimatedTotal).map { "\($0) · câmbio de Ajustes" })
                    whereLine(gift, store: store)
                    if let origin = originLine(gift) { origin }
                    if let taxFree = GiftLogic.taxFree(for: gift, among: gifts, on: AppClock.now, calendar: region.calendar,
                                                      currency: region.currency, extra: gift.estimatedTotal), !gift.isBought {
                        taxFreeLine(taxFree)
                    }
                    if !gift.note.isEmpty { line("Nota", title: gift.note, sub: nil) }
                    Color.clear.frame(height: 150)
                }
            }
            .scrollIndicators(.hidden)
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

    // MARK: Bloco

    private func band(_ gift: Gift, storeName: String?, position: Int, count: Int) -> some View {
        CutBand(photo: nil) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    GiftSquareButton(systemName: "arrow.left", label: "Voltar") { dismiss() }
                    DayBandCorners(left: ["Presente\(gift.personName == GiftLogic.noPerson ? "" : " · pra \(gift.personName)")",
                                          "\(position) de \(count)\(gift.personName == GiftLogic.noPerson ? "" : " da \(gift.personName)")"], right: [])
                        .padding(.top, 4)
                    Spacer(minLength: 8)
                    GiftSquareButton(systemName: "pencil", label: "Editar") { editing = true }
                }
                Spacer(minLength: 16)
                if let storeName, !storeName.isEmpty {
                    MonoLabel("na loja · \(storeName)", size: 10, color: .white.opacity(0.9)).lineLimit(1)
                        .padding(.bottom, 6)
                }
                Text(gift.title)
                    .font(V8Font.display(46))
                    .tracking(-1.4)
                    .strikethrough(gift.isBought)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .frame(minHeight: 260 * min(scale, 1.4))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Ficha

    private func line(_ label: String, title: String, sub: String?, tone: Color = V8.paper, ink: Color = V8.ink) -> some View {
        HStack(alignment: .top, spacing: 14) {
            MonoLabel(label, size: 10, color: ink == V8.ink && tone == V8.paper ? V8.mute : ink).frame(width: 82, alignment: .leading).padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(V8Font.text(18, weight: .bold)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                if let sub { Text(sub).font(V8Font.text(14)).foregroundStyle(ink == V8.ink && tone == V8.paper ? V8.mute : ink.opacity(0.75)).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(tone)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
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
                HStack(alignment: .top, spacing: 14) {
                    MonoLabel("Onde", size: 10, color: V8.ink).frame(width: 82, alignment: .leading).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.name).font(V8Font.text(18, weight: .bold)).foregroundStyle(V8.ink)
                        Text(near.map { "\(Walk.distanceText($0.meters)) · \($0.minutes) min a pé · \($0.isOpen ? "aberto" : "fechado")" } ?? "fora do alcance a pé agora")
                            .font(V8Font.text(14)).foregroundStyle(V8.ink.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if store.id != nil { MonoLabel("ver →", size: 10, color: V8.ink) }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(near != nil ? V8.orange : V8.paper)
                .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            line("Onde", title: gift.chain && !gift.storeName.isEmpty ? "Qualquer \(gift.storeName)" : "Sem loja ainda",
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
                HStack(alignment: .top, spacing: 14) {
                    MonoLabel("Veio de", size: 10, color: V8.mute).frame(width: 82, alignment: .leading).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(V8Font.text(18, weight: .bold)).foregroundStyle(V8.ink)
                        if !sub.isEmpty { Text(sub).font(V8Font.text(14)).foregroundStyle(V8.mute) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if gift.sourceURL != nil { Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(V8.ink).padding(.top, 8) }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(gift.sourceURL == nil)
        )
    }

    private func taxFreeLine(_ taxFree: GiftLogic.TaxFree) -> some View {
        HStack(alignment: .top, spacing: 14) {
            MonoLabel("Tax-free", size: 10, color: V8.mute).frame(width: 82, alignment: .leading).padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(taxFree.reached ? "Já vale nessa loja" : "Faltam \(money.text(taxFree.missing)) nessa loja")
                    .font(V8Font.text(18, weight: .bold)).foregroundStyle(V8.ink)
                Text("\(money.text(taxFree.minimum)) por loja no dia, com passaporte").font(V8Font.text(14)).foregroundStyle(V8.mute)
                ZStack(alignment: .leading) {
                    Rectangle().stroke(V8.ink, lineWidth: 2)
                    GeometryReader { geo in Rectangle().fill(V8.ink).frame(width: geo.size.width * taxFree.fraction).padding(3) }
                }
                .frame(height: 16).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Ações

    private func actions(_ gift: Gift, store: (name: String, id: String?, coordinate: CLLocationCoordinate2D, place: Place?)?) -> some View {
        HStack(spacing: 0) {
            if let store, !gift.isBought {
                let minutes = nearbyRow(gift)?.minutes
                Button { MapsLinks.openApple(to: store.coordinate, name: store.name) } label: {
                    Text("Ir\(minutes.map { " · \($0) min" } ?? "") ↗").font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink)
                        .frame(maxWidth: .infinity, minHeight: 58).background(V8.orange).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { toggleBought(gift) } label: {
                Text(gift.isBought ? "Desfazer" : "✓ Comprado").font(V8Font.text(17, weight: .bold)).foregroundStyle(gift.isBought ? V8.ink : V8.white)
                    .frame(maxWidth: .infinity, minHeight: 58).background(gift.isBought ? V8.paper : V8.ink).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 2) }
        .padding(.bottom, 0)
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
