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
    @Environment(Services.self) private var services

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
                Picker("Agrupar", selection: groupingBinding) {
                    ForEach(BoardGrouping.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                if groups.isEmpty {
                    Text(query.isFiltering ? "Nada com “\(query.text)” no board." : "Nenhum lugar no board.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            } footer: {
                Text("\(places.count) lugares · \(lists.count) listas")
            }
            ForEach(groups) { group in groupSection(group) }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .environment(\.editMode, $editMode)
        .navigationTitle("Tudo")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nome, bairro, nota, fonte…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Ordenar", selection: sortBinding) {
                        ForEach(BoardSort.allCases) { Text($0.label).tag($0) }
                    }
                    Section("Filtrar") {
                        ForEach(BoardFilter.allCases) { filter in
                            Button {
                                model.query.filter = query.filter == filter ? nil : filter
                            } label: {
                                if query.filter == filter { Label(chipTitle(filter), systemImage: "checkmark") } else { Text(chipTitle(filter)) }
                            }
                        }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("Ordenar e filtrar")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNameSearch = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Adicionar por nome")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "Pronto" : "Editar") { editMode = editing ? .inactive : .active }
            }
        }
        .v9Screen(grouped: true)
        .safeAreaInset(edge: .bottom) {
            if (editing && !model.selection.isEmpty) || message != nil {
                bottomBar.padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showNameSearch) { BuscarNomeView() }
        .onAppear {
            #if DEBUG
            if DebugFlags.string("debugScreen") == "corte-board-filtro" { model.query.filter = .saveForEnd }
            #endif
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

    private var groupingBinding: Binding<BoardGrouping> {
        Binding(get: { model.query.grouping }, set: { model.query.grouping = $0 })
    }

    private var sortBinding: Binding<BoardSort> {
        Binding(get: { model.query.sort }, set: { model.query.sort = $0 })
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
            ForEach(shown) { place in
                HStack(spacing: 4) {
                    BoardRow(place: place, region: region, isEditing: editing, isSelected: model.selection.contains(place.id),
                             here: services.location.current)
                    if !editing { rowMenu(place) }
                }
                .contentShape(Rectangle())
                .onTapGesture { tap(place) }
                .draggable(PlaceDragItem(id: place.id))
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button { sheet = .done(place.id) } label: { Label("Feito", systemImage: "checkmark") }
                        .tint(V9.accent)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { pendingDelete = [place.id] } label: { Label("Apagar", systemImage: "trash") }
                    Button { toggleSaveForEnd([place]) } label: { Label("Fica pro fim", systemImage: "clock") }
                        .tint(.gray)
                }
            }
            .onMove(perform: reorderable ? { reorder(group, $0, $1) } : nil)
            if collapsed {
                Button("Mostrar mais \(group.places.count - shown.count) em \(group.title)") { model.expanded.insert(group.id) }
            }
        } header: {
            BoardGroupHeader(group: group, onEditList: group.list.map { list in { router.cover = .editList(id: list.id) } })
                .dropDestination(for: PlaceDragItem.self) { (items: [PlaceDragItem], _: CGPoint) -> Bool in
                    drop(items, onto: group)
                }
        }
    }

    /// Mesmas ações do deslizar, num menu visível na linha.
    private func rowMenu(_ place: Place) -> some View {
        Menu {
            Button { sheet = .done(place.id) } label: { Label("Marcar feito", systemImage: "checkmark") }
            Button { toggleSaveForEnd([place]) } label: {
                Label(place.saveForEnd ? "Tirar do fim" : "Fica pro fim", systemImage: "clock")
            }
            Button(role: .destructive) { pendingDelete = [place.id] } label: { Label("Apagar", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Ações de \(place.name)")
    }

    // MARK: Barra de lote

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 10) {
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
