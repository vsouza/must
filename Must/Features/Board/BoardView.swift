import SwiftData
import SwiftUI

/// Board completo (Musts › Ver tudo · editar): todos os lugares da região, por lista ou por cidade.
/// Fora do modo edição: toque abre o lugar, swipe marca feito / fica pro fim / apaga.
/// Modo edição ("Editar"): bolinha de seleção, arrastar pra reordenar ou soltar noutra lista, ações em lote.
struct BoardView: View {
    /// Abre já em modo edição (Route.board(edit: true), usado pelos prints de QA).
    var startEditing = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query(sort: \Place.name) private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var model = BoardModel()
    @State private var editMode: EditMode = .inactive
    @State private var sheet: BoardSheet?
    @State private var showNameSearch = false
    @State private var pendingDelete: [String] = []
    /// Resultado da última ação em lote (ou erro), na barra de baixo.
    @State private var message: String?

    private var region: Region { store.region }
    private var editing: Bool { editMode.isEditing }
    private var query: BoardQuery { model.query }
    private var groups: [BoardGroup] { query.groups(places: places, lists: lists, trip: trips.first, region: region) }
    private var selected: [Place] { places.filter { model.selection.contains($0.id) } }
    private var focusGroup: BoardGroup? { model.focusListId.flatMap { id in groups.first { $0.list?.id == id } } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    cutBlock
                    CutRule()
                    VStack(alignment: .leading, spacing: 0) {
                        SearchPill(text: searchText, placeholder: "Nome, bairro, nota, fonte…") { sortChip }
                            .padding(.top, 18)
                        chips.padding(.top, 14).padding(.bottom, 18)
                        if groups.isEmpty {
                            Text(query.isFiltering ? "Nada com “\(query.text)” no board." : "Nenhum lugar no board.")
                                .mustMeta()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(groups) { group in groupSection(group) }
            Section {
                Color.clear.frame(height: 150)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .environment(\.editMode, $editMode)
        .background(V8.paper.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            if (editing && !model.selection.isEmpty) || message != nil {
                bottomBar.padding(.bottom, 92) // acima da tab bar
            }
        }
        .sheet(isPresented: $showNameSearch) { BuscarNomeView() }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard startEditing else { return }
            editMode = .active
            #if DEBUG
            // QA (`board:editar`): já com dois selecionados, pros prints.
            if DebugFlags.string("debugScreen") == "board:editar" {
                model.selection = Set((groups.first?.places ?? []).prefix(2).map(\.id))
            }
            #endif
        }
        .onChange(of: editMode) { _, mode in
            if !mode.isEditing {
                model.clearSelection()
                message = nil
            }
        }
        .sheet(item: $sheet) { kind in sheetContent(kind) }
        .confirmationDialog(deleteTitle, isPresented: deleteBinding, titleVisibility: .visible) {
            Button(pendingDelete.count == 1 ? "Apagar" : "Apagar \(pendingDelete.count) lugares", role: .destructive) {
                deletePending()
            }
        } message: {
            Text("Apaga do board, sem lixeira. O export do board é o backup.")
        }
    }

    // MARK: Topo (o corte)

    /// Capa de uma lista (a que já está no disco; nunca baixa): a foto só mora aqui, no bloco do topo.
    private var coverURL: URL? {
        lists.lazy.compactMap { ListCover.photo(for: $0) }.first.flatMap { URL(string: $0.largeURL ?? $0.url) }
    }

    /// Bloco do topo: voltar, "+" e Editar nos cantos; "Tudo" gigante e a contagem em mono. A régua é estática.
    private var cutBlock: some View {
        CutBand(photo: coverURL) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    V8CornerButton(systemName: "chevron.left", label: "Voltar", onPhoto: true) { dismiss() }
                    Spacer(minLength: 8)
                    // "+": adicionar um lugar pelo nome (Buscar por nome, prompt 17 · A).
                    V8CornerButton(systemName: "plus", label: "Adicionar por nome", onPhoto: true) { showNameSearch = true }
                    Button { editMode = editing ? .inactive : .active } label: {
                        Text(editing ? "PRONTO" : "EDITAR")
                            .font(V8Font.mono(11, weight: .semibold)).tracking(1)
                            .padding(.horizontal, 14)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(editing ? V8.ink : Color.clear)
                            .overlay(Rectangle().stroke(V8.white, lineWidth: 2))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 58)
                Spacer(minLength: 16)
                MonoLabel("board · \(places.count) lugares · \(lists.count) listas", size: 10, color: V8.white)
                Text("Tudo")
                    .font(V8Font.display(72))
                    .tracking(-2.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                if editing {
                    Text("editando · toque pra selecionar, segure pra arrastar")
                        .font(V8Font.text(14)).opacity(0.9).lineLimit(2)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .frame(height: 330)
        .frame(maxWidth: .infinity)
    }

    private var sortChip: some View {
        Button { model.query.sort = query.sort.next } label: {
            Text(query.sort.label)
                .font(.must.archivo(13, .semibold))
                .foregroundStyle(Color.must.ink)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel("Ordenar por \(query.sort.label)")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BoardGrouping.allCases, id: \.self) { grouping in
                    Button { model.query.grouping = grouping } label: {
                        Pill(grouping.label, isOn: query.grouping == grouping)
                    }
                }
                ForEach(BoardFilter.allCases) { filter in
                    Button { model.query.filter = query.filter == filter ? nil : filter } label: {
                        Pill(chipTitle(filter), isOn: query.filter == filter)
                    }
                }
            }
            .buttonStyle(MustPressStyle())
        }
        .scrollClipDisabled()
    }

    private func chipTitle(_ filter: BoardFilter) -> String {
        switch filter {
        case .noHours, .saveForEnd: "\(filter.label) · \(BoardQuery.count(filter, in: places))"
        case .done: filter.label
        }
    }

    // MARK: Grupos

    private func groupSection(_ group: BoardGroup) -> some View {
        // Lista grande (> 6) abre recolhida em 4; com busca ou filtro, mostra tudo.
        let collapsed = !query.isFiltering && group.places.count > 6 && !model.expanded.contains(group.id)
        let shown = collapsed ? Array(group.places.prefix(4)) : group.places
        let reorderable = editing && !query.isFiltering && query.sort == .manual && group.list != nil && !collapsed
        return Section {
            BoardGroupHeader(group: group, onEditList: group.list.map { list in { router.cover = .editList(id: list.id) } })
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .dropDestination(for: PlaceDragItem.self) { (items: [PlaceDragItem], _: CGPoint) -> Bool in
                    drop(items, onto: group)
                }
            ForEach(shown) { place in
                BoardRow(place: place, region: region, isEditing: editing, isSelected: model.selection.contains(place.id))
                    .boardRow()
                    .contentShape(Rectangle())
                    .onTapGesture { tap(place) }
                    .draggable(PlaceDragItem(id: place.id))
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { sheet = .done(place.id) } label: { Label("Feito", systemImage: "checkmark") }
                            .tint(Color.must.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDelete = [place.id] } label: { Label("Apagar", systemImage: "trash") }
                        Button { toggleSaveForEnd([place]) } label: { Label("Fica pro fim", systemImage: "clock") }
                            .tint(Color.must.ink)
                    }
            }
            .onMove(perform: reorderable ? { reorder(group, $0, $1) } : nil)
            if collapsed {
                Button { model.expanded.insert(group.id) } label: {
                    Text("+ \(group.places.count - shown.count) em \(group.title)")
                        .font(.must.archivo(14, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Capsule().fill(Color.must.surface))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MustPressStyle())
                .boardRow()
            }
        }
    }

    // MARK: Barra de lote

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 10) {
            if let message {
                Text(message)
                    .font(.must.meta)
                    .foregroundStyle(Color.must.secondary)
                    .multilineTextAlignment(.center)
            }
            if editing && !model.selection.isEmpty {
                BoardBatchBar(
                    count: selected.count,
                    focusTitle: focusGroup?.title,
                    saveForEndTitle: selected.allSatisfy(\.saveForEnd) ? "Tirar do fim" : "Fica pro fim",
                    onSelectAll: selectAllInFocus,
                    onMove: { sheet = .move },
                    onSaveForEnd: { toggleSaveForEnd(selected) },
                    onCity: { sheet = .city },
                    onResolve: queueResolve,
                    onDelete: { pendingDelete = selected.map(\.id) }
                )
            }
        }
    }

    @ViewBuilder private func sheetContent(_ kind: BoardSheet) -> some View {
        switch kind {
        case .move:
            MoveListSheet(lists: lists, count: selected.count) { moveSelected(to: $0) }
                .presentationDetents([.medium, .large])
        case .city:
            CityPickSheet(options: cityOptions) { setCity($0) }
                .presentationDetents([.medium, .large])
        case .done(let id):
            if let place = places.first(where: { $0.id == id }) {
                DoneSheet(place: place, region: region).presentationDetents([.medium])
            }
        }
    }

    private var cityOptions: [CityOption] {
        let trip = trips.first
        return (trip?.cities ?? []).map { CityOption(id: $0.id, title: trip?.label(for: $0, region: region) ?? $0.name) }
    }

    // MARK: Ações

    private var searchText: Binding<String> {
        Binding(get: { model.query.text }, set: { model.query.text = $0 })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })
    }

    private var deleteTitle: String {
        if pendingDelete.count == 1, let name = places.first(where: { $0.id == pendingDelete[0] })?.name {
            return "Apagar \(name)?"
        }
        return "Apagar \(pendingDelete.count) lugares?"
    }

    private func tap(_ place: Place) {
        if editing {
            model.toggle(place)
        } else {
            router.push(.place(id: place.id))
        }
    }

    private func perform(_ work: () throws -> Void) {
        message = nil
        do {
            try work()
        } catch {
            message = error.localizedDescription
        }
    }

    private func reorder(_ group: BoardGroup, _ from: IndexSet, _ to: Int) {
        perform { try BoardEdits.reorder(group.places, from: from, to: to, context: context) }
    }

    /// Soltar lugares num cabeçalho: vão pro fim daquela lista.
    private func drop(_ items: [PlaceDragItem], onto group: BoardGroup) -> Bool {
        guard let list = group.list else { return false }
        let ids = Set(items.map(\.id))
        let moving = places.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return false }
        perform { try BoardEdits.move(moving, to: list, context: context) }
        return true
    }

    private func moveSelected(to list: MustList) {
        let items = selected
        perform { try BoardEdits.move(items, to: list, context: context) }
        model.clearSelection()
    }

    private func toggleSaveForEnd(_ items: [Place]) {
        let on = !items.allSatisfy(\.saveForEnd)
        perform { try BoardEdits.setSaveForEnd(items, on: on, context: context) }
    }

    private func setCity(_ option: CityOption) {
        let items = selected
        perform { try BoardEdits.setCity(items, cityId: option.id, context: context) }
    }

    private func queueResolve() {
        let items = selected
        perform { try BoardEdits.queueResolve(items, context: context) }
        if message == nil {
            message = "\(items.count) na fila do Places · a próxima sincronização resolve até 50."
        }
    }

    private func selectAllInFocus() {
        guard let group = focusGroup else { return }
        model.selection.formUnion(group.places.map(\.id))
    }

    private func deletePending() {
        let items = places.filter { pendingDelete.contains($0.id) }
        pendingDelete = []
        model.selection.subtract(items.map(\.id))
        perform { try BoardEdits.delete(items, context: context) }
    }
}

private extension View {
    /// Linha do board: sem fundo nem separador do sistema (o divisor é desenhado), margem de 22 pt.
    func boardRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
