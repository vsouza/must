import CoreLocation
import SwiftData
import SwiftUI

/// Viagem › Presentes: uma lista fácil, no espírito de Lembretes, no visual do corte (papel, réguas de 2 pt). Agrupada por pessoa;
/// a caixa marca comprado (e abre o painel do valor pago); "perto" em laranja só no marcador; campo "Novo presente…" no fim
/// (aceita "nome pra Ana", "nome — Ana" e link colado). Deslizar: comprado / apagar (com desfazer). Toque na linha abre a ficha.
struct PresentesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: [SortDescriptor(\Gift.createdAt)]) private var allGifts: [Gift]
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]

    @State private var buying: Gift?
    @State private var editing: Gift?
    @State private var adding = false
    @State private var filter: GiftFilter = .pending
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @State private var tick = 0
    /// Apagado com desfazer: some da lista na hora e só sai do banco depois de alguns segundos.
    @State private var deleted: Gift?
    @State private var deleteTask: Task<Void, Never>?

    private var region: Region { store.region }
    private var money: GiftMoney { GiftMoney(region: region, userRate: settingsList.first?.fxRate) }
    private var now: Date { AppClock.now }
    /// Tudo o que existe (menos o que acabou de ser apagado).
    private var gifts: [Gift] { allGifts.filter { $0.id != deleted?.id } }

    private var nearby: [GiftNearby] {
        GiftLogic.nearby(gifts: gifts, places: places, here: services.location.current?.coordinate, now: now, timeZone: region.timeZone)
    }

    var body: some View {
        let near = Dictionary(nearby.map { ($0.giftId, $0) }, uniquingKeysWith: { a, _ in a })
        let groups = GiftLogic.groups(filter.apply(gifts), nearby: Set(near.keys))
        VStack(spacing: 0) {
            header
            if !gifts.isEmpty { filters }
            list(groups: groups, near: near)
            if let deleted { undoBar(deleted) }
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
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
        .onChange(of: buying?.id) { _, id in router.setQuero("presentes", open: id != nil) }
        .onDisappear { router.setQuero("presentes", open: false); commitDelete() }
        .sheet(isPresented: $adding) { PresenteNovoView() }
        .sheet(item: $editing) { gift in PresenteNovoView(editing: gift) }
        .onAppear {
            debugBuy()
            if gifts.isEmpty { fieldFocused = DebugFlags.string("debugScreen") == nil }
        }
    }

    // MARK: Topo (baixo: título + uma linha)

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            GiftSquareButton(systemName: "arrow.left", label: "Voltar", onInk: false) { dismiss() }
            VStack(alignment: .leading, spacing: 4) {
                Text("Presentes")
                    .font(V8Font.display(34)).tracking(-0.8)
                    .foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(V8Font.text(14)).foregroundStyle(V8.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GiftSquareButton(systemName: "plus", label: "Novo presente com detalhes", onInk: false) { adding = true }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
    }

    private var summary: String {
        if gifts.isEmpty { return "nada ainda" }
        let total = GiftLogic.plannedTotal(gifts)
        return "\(GiftLogic.pendingText(gifts)) · previsto \(money.text(total))\(money.brl(total).map { " \($0)" } ?? "")"
    }

    // MARK: Filtro

    private var filters: some View {
        let people = GiftLogic.people(gifts)
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("Faltam", .pending)
                chip("Todos", .all)
                if people.count > 1 { ForEach(people, id: \.self) { chip($0, .person($0)) } }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, _ value: GiftFilter) -> some View {
        let on = filter == value
        return Button { filter = value } label: {
            Text(title).font(V8Font.mono(11, weight: .semibold)).tracking(0.6).textCase(.uppercase).lineLimit(1)
                .foregroundStyle(on ? V8.white : V8.ink)
                .padding(.horizontal, 12).frame(minHeight: 36)
                .background(on ? V8.ink : Color.clear)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Lista

    private func list(groups: [GiftGroup], near: [String: GiftNearby]) -> some View {
        List {
            if gifts.isEmpty {
                note("Cole um link ou escreva o que alguém pediu. \u{201C}Kit Kat pra Ana\u{201D} já põe na lista da Ana.")
            } else if groups.isEmpty {
                note(filter == .pending ? "Tudo comprado." : "Nada aqui ainda.")
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.gifts) { gift in row(gift, near: near[gift.id]) }
                } header: {
                    groupHeader(group)
                }
            }
            addField(groups: groups)
            V8BarSpacer()
                .listRowBackground(V8.paper).listRowSeparator(.hidden).listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 1)
        .listSectionSpacing(0)
        .environment(\.defaultMinListHeaderHeight, 0)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(V8Font.text(16)).foregroundStyle(V8.mute)
            .fixedSize(horizontal: false, vertical: true)
            .listRowBackground(V8.paper).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 8, trailing: 20))
    }

    private func groupHeader(_ group: GiftGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            MonoLabel(group.person, size: 11, color: V8.ink).lineLimit(1)
            Spacer(minLength: 8)
            MonoLabel(money.text(group.subtotal), size: 11, color: V8.mute).lineLimit(1)
        }
        .textCase(nil)
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V8.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ gift: Gift, near: GiftNearby?) -> some View {
        let place = GiftLogic.store(of: gift, places: places)
        let dim = gift.isBought
        return HStack(alignment: .center, spacing: 4) {
            GiftCheckbox(done: gift.isBought, onInk: false) { toggle(gift) }
                .padding(.leading, -10)
            Button { router.push(.presente(id: gift.id), on: .viagem) } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GiftLogic.titleWithQty(gift))
                            .font(V8Font.text(16, weight: .semibold))
                            .strikethrough(dim)
                            .foregroundStyle(dim ? V8.mute : V8.ink)
                            .lineLimit(2)
                        if let line = meta(gift, storeName: place?.name) {
                            Text(line).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if near != nil, !dim {
                        Text("perto").font(V8Font.mono(10, weight: .semibold)).tracking(0.8).textCase(.uppercase)
                            .foregroundStyle(V8.ink).padding(.horizontal, 8).padding(.vertical, 5).background(V8.orange)
                            .fixedSize()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 4)
        .frame(minHeight: 52)
        .listRowBackground(V8.paper)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink.opacity(0.12)).frame(height: 1).padding(.leading, 20) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { remove(gift) } label: { Label("Apagar", systemImage: "trash") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { toggle(gift) } label: { Label(gift.isBought ? "Falta" : "Comprado", systemImage: "checkmark") }.tint(V8.ink)
        }
        .contextMenu {
            Button("Editar", systemImage: "pencil") { editing = gift }
            Button("Apagar", systemImage: "trash", role: .destructive) { remove(gift) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(near != nil && !dim ? "Loja perto e aberta" : "")
    }

    /// "Don Quijote · ¥3.600"; comprado: "comprado · ¥3.240". Sem nada, sem linha.
    private func meta(_ gift: Gift, storeName: String?) -> String? {
        let name = storeName ?? (gift.storeName.isEmpty ? nil : gift.storeName)
        if gift.isBought {
            return ["comprado", name, money.text(gift.paidPrice ?? gift.estimatedTotal)].compactMap { $0 }.joined(separator: " · ")
        }
        let parts: [String?] = [name ?? (gift.chain ? "qualquer loja" : nil),
                                gift.estimatedPrice > 0 ? money.text(gift.estimatedTotal) : nil,
                                name == nil ? gift.source.metaLabel : nil]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    // MARK: Adicionar rápido

    private func addField(groups: [GiftGroup]) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(V8.mute)
                .frame(width: 44, height: 44).padding(.leading, -10)
            TextField("Novo presente…", text: $draft)
                .font(V8Font.text(16))
                .foregroundStyle(V8.ink)
                .tint(V8.orange)
                .focused($fieldFocused)
                .submitLabel(.done)
                .onSubmit { addDraft() }
                .accessibilityLabel("Novo presente")
                .accessibilityHint("Escreva o nome, ou nome pra Ana, ou cole um link")
        }
        .padding(.horizontal, 20).frame(minHeight: 56)
        .listRowBackground(V8.paper).listRowSeparator(.hidden).listRowInsets(EdgeInsets())
        .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 2) }
    }

    private func addDraft() {
        guard let entry = GiftQuick.parse(draft) else { fieldFocused = false; return }
        let person: String
        if entry.personExplicit {
            person = GiftLogic.people(gifts).first { $0.localizedCaseInsensitiveCompare(entry.person) == .orderedSame } ?? entry.person
        } else if case .person(let name) = filter {
            person = name
        } else {
            person = GiftQuick.inheritedPerson(GiftLogic.groups(filter.apply(gifts)))
        }
        let gift = Gift(title: entry.title, person: person, source: entry.url == nil ? .name : .link,
                        order: (allGifts.map(\.order).max() ?? 0) + 1)
        if let url = entry.url { gift.sourceURL = LinkResolver.resolve(url).url?.absoluteString ?? url }
        context.insert(gift)
        try? context.save()
        draft = ""
        tick += 1
        if case .person(let name) = filter, name != gift.personName { filter = .all }
        fieldFocused = true
    }

    // MARK: Apagar com desfazer

    private func remove(_ gift: Gift) {
        commitDelete()
        withAnimation(.snappy(duration: 0.2)) { deleted = gift }
        tick += 1
        deleteTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { commitDelete() }
        }
    }

    private func commitDelete() {
        deleteTask?.cancel()
        deleteTask = nil
        guard let gift = deleted else { return }
        if gift.isBought { GiftLogic.undoBought(gift, context: context) }
        context.delete(gift)
        try? context.save()
        deleted = nil
    }

    private func undoBar(_ gift: Gift) -> some View {
        HStack {
            Text("Apagado: \(gift.title)").font(V8Font.text(14)).foregroundStyle(V8.white).lineLimit(1)
            Spacer(minLength: 8)
            Button {
                deleteTask?.cancel(); deleteTask = nil
                withAnimation(.snappy(duration: 0.2)) { deleted = nil }
            } label: {
                Text("desfazer").font(V8Font.mono(11, weight: .semibold)).tracking(0.8).textCase(.uppercase)
                    .foregroundStyle(V8.orange).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .background(V8.ink)
        .transition(.move(edge: .bottom))
    }

    // MARK: Comprado

    private func toggle(_ gift: Gift) {
        tick += 1
        if gift.isBought {
            GiftLogic.undoBought(gift, context: context)
            return
        }
        let store = GiftLogic.store(of: gift, places: places)?.place
        GiftLogic.markBought(gift, paid: gift.estimatedTotal, at: now, context: context, store: store)
        withAnimation(.snappy(duration: 0.25)) { buying = gift }
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
