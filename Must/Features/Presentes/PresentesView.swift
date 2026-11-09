import CoreLocation
import SwiftData
import SwiftUI

/// Viagem › Presentes: uma lista fácil, no espírito de Lembretes (V9, `List` nativa). Agrupada por pessoa;
/// a caixa marca comprado (e abre o painel do valor pago); "perto" em laranja só no marcador; campo "Novo presente…" no fim
/// (aceita "nome pra Ana", "nome — Ana" e link colado). Deslizar: comprado / apagar (com desfazer). Toque na linha abre a ficha.
struct PresentesView: View {
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
    /// O que acabou de entrar pelo campo: o grupo da pessoa pode estar fora da tela, então a linha do campo confirma.
    @State private var justAdded: (title: String, person: String)?

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
        list(groups: groups, near: near)
            .navigationTitle("Presentes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Novo presente com detalhes")
                }
            }
            .v9Screen(grouped: true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let deleted { undoBar(deleted) }
                    if let buying {
                        GiftBoughtPanel(gift: buying, gifts: gifts, region: region, money: money,
                                        storeName: GiftLogic.store(of: buying, places: places)?.name ?? buying.storeName,
                                        onUndo: { GiftLogic.undoBought(buying, context: context); self.buying = nil },
                                        onOk: { self.buying = nil })
                            .transition(.move(edge: .bottom))
                    }
                }
            }
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

    private var summary: String {
        if gifts.isEmpty { return "nada ainda" }
        let total = GiftLogic.plannedTotal(gifts)
        return "\(GiftLogic.pendingText(gifts)) · previsto \(money.text(total))\(money.brl(total).map { " \($0)" } ?? "")"
    }

    // MARK: Filtro

    private var filters: some View {
        let people = GiftLogic.people(gifts)
        return Picker("Mostrar", selection: $filter) {
            Text("Faltam").tag(GiftFilter.pending)
            Text("Todos").tag(GiftFilter.all)
            if people.count > 1 { ForEach(people, id: \.self) { Text($0).tag(GiftFilter.person($0)) } }
        }
        .pickerStyle(.menu)
    }

    // MARK: Lista

    private func list(groups: [GiftGroup], near: [String: GiftNearby]) -> some View {
        List {
            Section {
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
                if !gifts.isEmpty { filters }
            }
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
            Section { addField(groups: groups) }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func note(_ text: String) -> some View {
        Section { Text(text).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }

    private func groupHeader(_ group: GiftGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.person).font(.headline).foregroundStyle(.primary).lineLimit(1)
            Spacer(minLength: 8)
            Text(money.text(group.subtotal)).font(.subheadline.monospacedDigit()).lineLimit(1)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ gift: Gift, near: GiftNearby?) -> some View {
        let place = GiftLogic.store(of: gift, places: places)
        let dim = gift.isBought
        return HStack(alignment: .center, spacing: 0) {
            GiftCheckbox(done: gift.isBought, onInk: false) { toggle(gift) }
                .padding(.leading, -8)
            Button { router.push(.presente(id: gift.id), on: .viagem) } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GiftLogic.titleWithQty(gift))
                            .font(.body.weight(.semibold))
                            .strikethrough(dim)
                            .foregroundStyle(dim ? Color.secondary : Color.primary)
                            .lineLimit(3)
                        if let line = meta(gift, storeName: place?.name) {
                            Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if near != nil, !dim {
                        Label("perto", systemImage: "location.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(V9.accent)
                            .fixedSize()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button { toggle(gift) } label: { Label(gift.isBought ? "Marcar como falta" : "Marcar comprado", systemImage: "checkmark") }
                Button { editing = gift } label: { Label("Editar", systemImage: "pencil") }
                Button(role: .destructive) { remove(gift) } label: { Label("Apagar", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Ações de \(gift.title)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { remove(gift) } label: { Label("Apagar", systemImage: "trash") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { toggle(gift) } label: { Label(gift.isBought ? "Falta" : "Comprado", systemImage: "checkmark") }.tint(V9.accent)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 28).accessibilityHidden(true)
                TextField("Novo presente…", text: $draft)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit { addDraft() }
                    .accessibilityLabel("Novo presente")
                    .accessibilityHint("Escreva o nome, ou nome pra Ana, ou cole um link")
                    .onChange(of: draft) { _, new in if !new.isEmpty { justAdded = nil } }
                if !draft.isEmpty {
                    Button("Adicionar") { addDraft() }.font(.subheadline.weight(.semibold))
                }
            }
            .frame(minHeight: 44)
            if let justAdded {
                Text("✓ \(justAdded.title) → \(justAdded.person)")
                    .font(.footnote).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .accessibilityLabel("Adicionado: \(justAdded.title), em \(justAdded.person)")
            }
        }
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
        justAdded = (gift.title, gift.personName)
        tick += 1
        if case .person(let name) = filter, name != gift.personName { filter = .all }
        fieldFocused = true
    }

    // MARK: Apagar com desfazer

    private func remove(_ gift: Gift) {
        commitDelete()
        justAdded = nil
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
            Text("Apagado: \(gift.title)").font(.subheadline).lineLimit(1)
            Spacer(minLength: 8)
            Button("Desfazer") {
                deleteTask?.cancel(); deleteTask = nil
                withAnimation(.snappy(duration: 0.2)) { deleted = nil }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
        .padding(.horizontal, V9.gutter)
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
