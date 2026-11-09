import SwiftData
import SwiftUI

/// Compras (V9, `List` nativa): previsto e já gasto, cota do Brasil, categoria que filtra, uma seção por categoria
/// e "Comidinhas pra levar" com as regras.
struct ShoppingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store

    @Query(sort: [SortDescriptor(\ShoppingItem.createdAt)]) private var items: [ShoppingItem]
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]

    @State private var filter: ShoppingCategory?
    @State private var editing: ShoppingItem?
    @State private var adding = false

    private var region: Region { store.region }
    /// R$ por 1 unidade da moeda das regras (¥ no Japão e em BH, € em Roma): o câmbio de Ajustes vale na região dele.
    private var baseRate: Double { ShoppingFX.baseRate(for: region, userRate: settingsList.first?.fxRate) }
    private var brlPerUSD: Double { settingsList.first?.brlPerUSD ?? ShoppingFX.brlPerUSD }
    private var stores: [Place] { places.filter { $0.list?.id == "shop" } }

    /// Regras da volta da região (Itália → Brasil em Roma, com a conta em €).
    private func makeReport(_ items: [ShoppingItem]) -> ShoppingReport {
        ShoppingReport(items: items, fxRate: baseRate, brlPerUSD: brlPerUSD, regionCurrency: region.currency,
                       rules: ShoppingRules.pack(for: region), timeZone: region.timeZone)
    }

    var body: some View {
        let report = makeReport(items)
        List {
            alertsRow(report)
            if items.isEmpty {
                emptyState
            } else {
                totalCard(report)
                if presentCategories.count > 1 {
                    Section { categoryPicker }
                }
                ForEach(visibleCategories, id: \.self) { category in
                    section(category)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Compras")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Adicionar à lista")
            }
        }
        .v9Screen(grouped: true)
        .onAppear {
            ShoppingFlightSync.refresh(context: context, region: region)
            #if DEBUG
            if DebugFlags.string("debugScreen") == "compras-item" { adding = true }
            #endif
        }
        .sheet(item: $editing, onDismiss: { ShoppingFlightSync.refresh(context: context, region: region) }) { item in
            ShoppingItemEditor(item: item)
        }
        .sheet(isPresented: $adding, onDismiss: { ShoppingFlightSync.refresh(context: context, region: region) }) {
            ShoppingItemEditor(item: nil)
        }
    }

    // MARK: Topo

    /// Linha das regras da volta (alerta em vermelho do sistema quando há).
    private func alertsRow(_ report: ShoppingReport) -> some View {
        let alerts = report.alerts.count
        return Section {
            Button { router.push(.regrasVolta, on: router.tab) } label: {
                HStack(spacing: 12) {
                    Image(systemName: alerts > 0 ? "exclamationmark.triangle.fill" : "checkmark.shield")
                        .font(.title3).foregroundStyle(alerts > 0 ? Color.red : Color.secondary).frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Regras da volta").font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text("\(alerts) \(alerts == 1 ? "alerta" : "alertas")").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Previsto e cota

    /// Totais na moeda da região; a outra moeda aparece em "≈". Cota do Brasil sempre em US$.
    private func totalCard(_ report: ShoppingReport) -> some View {
        let tax = report.taxFree
        let currency = report.regionCurrency
        let symbol = MoneyFormatStyle.symbol(for: currency)
        let other = currency == "BRL" ? "JPY" : "BRL"
        let boughtShare = min(1, report.boughtUSD / report.limits.airAllowanceUSD)
        let plannedShare = max(0, min(1 - boughtShare, report.usedUSD / report.limits.airAllowanceUSD - boughtShare))
        let planned = report.regionAmount(yen: report.planned)
        let refund = report.regionAmount(yen: tax.refund)
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Previsto").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("já gasto \(ShoppingReport.money(report.regionAmount(yen: report.spent), currency: currency))")
                        .font(.subheadline.monospacedDigit())
                }
                Text("\(symbol) \(ShoppingReport.yen(planned))")
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("≈ \(ShoppingReport.money(report.amount(yen: report.planned, in: other), currency: other)) · volta ~\(symbol)\(ShoppingReport.compact(refund))")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).lineLimit(2)
                ProgressView(value: min(1, boughtShare + plannedShare)).tint(V9.accent)
                Text("Cota do Brasil: \(ShoppingReport.usdText(report.usedUSD)) de \(ShoppingReport.usdText(report.limits.airAllowanceUSD))")
                    .font(.subheadline)
                Text("Tax-free a receber \(ShoppingReport.money(refund, currency: currency))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Categorias

    private var presentCategories: [ShoppingCategory] {
        ShoppingCategory.allCases.filter { category in items.contains { $0.category == category } }
    }

    private var visibleCategories: [ShoppingCategory] {
        if let filter { return [filter] }
        return presentCategories
    }

    private var categoryPicker: some View {
        Picker("Categoria", selection: $filter) {
            Text("Todas · \(items.count)").tag(ShoppingCategory?.none)
            ForEach(presentCategories) { category in
                Text("\(category.label) · \(items.filter { $0.category == category }.count)").tag(ShoppingCategory?.some(category))
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: Seções

    @ViewBuilder private func section(_ category: ShoppingCategory) -> some View {
        let list = items.filter { $0.category == category }
        if category == .food {
            foodSection(list)
        } else if !list.isEmpty {
            Section {
                ForEach(list) { item in
                    ShoppingItemCard(item: item, storeName: storeName(item), currency: makeReport(items).currency(of: item)) {
                        editing = item
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(category.label).font(.headline).foregroundStyle(.primary).textCase(nil)
                    Spacer(minLength: 8)
                    Text(areas(list)).font(.footnote).textCase(nil).lineLimit(1)
                }
            }
        }
    }

    /// "Comidinhas pra levar": uma linha por item, com a regra que ele passa ou não passa.
    @ViewBuilder private func foodSection(_ list: [ShoppingItem]) -> some View {
        if !list.isEmpty {
            let report = makeReport(items)
            let alcohol = list.filter { $0.flags.contains(.alcohol) }
            let food = list.filter { !$0.flags.contains(.alcohol) }
            let litres = report.liquorLitres
            let limit = report.limits.liquorLitres
            let stores = Array(Set(list.map(storeName).filter { !$0.isEmpty })).sorted().prefix(2).joined(separator: " · ")
            Section {
                ForEach(food) { item in
                    Button { editing = item } label: {
                        ShoppingRuleChip(text: chipText(item), tone: chipTone(item))
                    }
                    .buttonStyle(.plain)
                }
                if !alcohol.isEmpty {
                    ShoppingRuleChip(text: "álcool \(ShoppingReport.litres(litres)) de \(ShoppingReport.litres(limit)) L",
                                     tone: litres > limit ? .no : .warn)
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(ShoppingCategory.food.label).font(.headline).foregroundStyle(.primary).textCase(nil)
                    Spacer(minLength: 8)
                    Text(stores.isEmpty ? "" : "no fim · \(stores)").font(.footnote).textCase(nil).lineLimit(1)
                }
            }
        }
    }

    private func chipText(_ item: ShoppingItem) -> String {
        let name = item.qty > 1 ? "\(item.name) × \(item.qty)" : item.name
        if item.flags.isEmpty { return "\(name) · lacrado" }
        let labels = item.flags.map(\.label).joined(separator: ", ")
        return "\(name) · \(labels)"
    }

    private func chipTone(_ item: ShoppingItem) -> ShoppingTone {
        item.flags.isEmpty ? .ok : .no
    }

    // MARK: Textos

    private func storeName(_ item: ShoppingItem) -> String { item.storeLabel(board: places) }

    /// "Akihabara · Shinjuku · Nakano": as áreas das lojas da categoria, sem repetir.
    private func areas(_ list: [ShoppingItem]) -> String {
        var seen: [String] = []
        for item in list {
            let area = item.area ?? stores.first { $0.id == item.storeId }?.area ?? ""
            if !area.isEmpty, !seen.contains(area) { seen.append(area) }
        }
        return seen.prefix(3).joined(separator: " · ")
    }

    // MARK: Vazio

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nada na lista ainda").font(.headline)
                Text("Toque em + pra anotar o que quer trazer. As regras da volta conferem cada item.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
