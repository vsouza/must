import SwiftData
import SwiftUI

/// Compras (`design/screens/Compras.png`): previsto e já gasto, cota do Brasil, fileira de categorias que filtra,
/// um bloco por categoria (cards horizontais) e "Comidinhas pra levar" com os chips das regras.
struct ShoppingView: View {
    @Environment(\.dismiss) private var dismiss
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar.padding(.top, 8)
                titleRow(report).padding(.top, 22)
                if items.isEmpty {
                    emptyState.padding(.top, 26)
                } else {
                    totalCard(report).padding(.top, 22)
                    categoryStrip.padding(.top, 22)
                    ForEach(visibleCategories, id: \.self) { category in
                        section(category).padding(.top, 30)
                    }
                }
                TabBarSpacer()
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { tabFade }
        .background(Color.must.bg)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { ShoppingFlightSync.refresh(context: context, region: region) }
        .sheet(item: $editing, onDismiss: { ShoppingFlightSync.refresh(context: context, region: region) }) { item in
            ShoppingItemEditor(item: item)
        }
        .sheet(isPresented: $adding, onDismiss: { ShoppingFlightSync.refresh(context: context, region: region) }) {
            ShoppingItemEditor(item: nil)
        }
    }

    // MARK: Topo

    private var topBar: some View {
        let bought = items.filter(\.isBought).count
        return HStack {
            IconButton(.voltar, label: "Voltar") { dismiss() }
            Spacer()
            Micro("\(region.shortName) · \(items.count) \(items.count == 1 ? "item" : "itens") · \(bought) comprados")
            Spacer()
            IconButton(.adicionar, style: .dark, label: "Adicionar à lista") { adding = true }
        }
    }

    private func titleRow(_ report: ShoppingReport) -> some View {
        let alerts = report.alerts.count
        return HStack(alignment: .center, spacing: 10) {
            Text("Compras").mustTitle()
            Spacer(minLength: 8)
            Button { router.push(.regrasVolta, on: router.tab) } label: {
                Text("Regras da volta · \(alerts) \(alerts == 1 ? "alerta" : "alertas")")
                    .font(.must.archivo(14, .semibold))
                    .foregroundStyle(Color(hex: 0x4A2E00))
                    .lineLimit(1)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(Color(hex: 0xFFE3A3)))
            }
            .buttonStyle(MustPressStyle())
        }
    }

    /// Degradê branco na borda de baixo: a lista rola por trás dele até a tab bar.
    private var tabFade: some View {
        LinearGradient(colors: [Color.must.bg.opacity(0), Color.must.bg], startPoint: .top, endPoint: .bottom)
            .frame(height: 90)
            .allowsHitTesting(false)
            .ignoresSafeArea(edges: .bottom)
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
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("previsto").font(.must.archivo(14)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                HStack(spacing: 6) {
                    Text("já gasto").font(.must.archivo(13)).foregroundStyle(.white.opacity(0.7))
                    Text(ShoppingReport.money(report.regionAmount(yen: report.spent), currency: currency))
                        .font(.must.mono(14, .semibold)).foregroundStyle(Color.must.green)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(symbol).font(.must.mono(26, .semibold)).foregroundStyle(.white)
                MonoNumber(ShoppingReport.yen(planned), size: 34).foregroundStyle(.white)
                Text("≈ \(ShoppingReport.money(report.amount(yen: report.planned, in: other), currency: other)) · volta ~\(symbol)\(ShoppingReport.compact(refund))")
                    .font(.must.mono(13)).foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    HStack(spacing: 0) {
                        Capsule().fill(Color.must.green).frame(width: geo.size.width * boughtShare)
                        Capsule().fill(Color.must.blue).frame(width: geo.size.width * plannedShare)
                    }
                }
            }
            .frame(height: 8)
            let cota = HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("cota do Brasil: ").font(.must.archivo(13)).foregroundStyle(.white.opacity(0.7))
                Text(ShoppingReport.usdText(report.usedUSD)).font(.must.archivo(13, .semibold)).foregroundStyle(.white)
                Text(" de \(ShoppingReport.usdText(report.limits.airAllowanceUSD))").font(.must.archivo(13)).foregroundStyle(.white.opacity(0.7))
            }
            let taxText = Text("tax-free a receber \(ShoppingReport.money(refund, currency: currency))")
                .font(.must.archivo(13)).foregroundStyle(.white.opacity(0.85))
            // Uma linha se couber; senão cota e tax-free empilhados, alinhados à esquerda (sem truncar).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    cota.fixedSize()
                    Spacer(minLength: 4)
                    taxText.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    cota.fixedSize()
                    taxText.fixedSize()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.must.ink))
    }

    // MARK: Fileira de categorias

    private var presentCategories: [ShoppingCategory] {
        ShoppingCategory.allCases.filter { category in items.contains { $0.category == category } }
    }

    private var visibleCategories: [ShoppingCategory] {
        if let filter { return [filter] }
        return presentCategories
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(presentCategories) { category in
                    Button { filter = filter == category ? nil : category } label: { stripTile(category) }
                        .buttonStyle(MustPressStyle())
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func stripTile(_ category: ShoppingCategory) -> some View {
        let count = items.filter { $0.category == category }.count
        let selected = filter == category
        return VStack(spacing: 6) {
            ShoppingTile(category: category, size: 58)
                .overlay {
                    if selected { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.must.ink, lineWidth: 2.5).padding(-4) }
                }
            Text("\(category.label) · \(count)")
                .font(.must.archivo(11, .semibold))
                .foregroundStyle(Color.must.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 72)
        }
    }

    // MARK: Seções

    @ViewBuilder private func section(_ category: ShoppingCategory) -> some View {
        let list = items.filter { $0.category == category }
        if category == .food {
            foodSection(list)
        } else if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(category.label).font(.must.archivo(20, .semibold)).foregroundStyle(Color.must.ink)
                    Spacer(minLength: 8)
                    Text(areas(list)).font(.must.archivo(13)).foregroundStyle(Color.must.secondary).lineLimit(1)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(list) { item in
                            ShoppingItemCard(item: item, storeName: storeName(item), currency: makeReport(items).currency(of: item)) {
                                editing = item
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    /// "Comidinhas pra levar": um chip por item, com a regra que ele passa ou não passa.
    @ViewBuilder private func foodSection(_ list: [ShoppingItem]) -> some View {
        if !list.isEmpty {
            let report = makeReport(items)
            let alcohol = list.filter { $0.flags.contains(.alcohol) }
            let food = list.filter { !$0.flags.contains(.alcohol) }
            let litres = report.liquorLitres
            let limit = report.limits.liquorLitres
            let stores = Array(Set(list.map(storeName).filter { !$0.isEmpty })).sorted().prefix(2).joined(separator: " · ")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ShoppingCategory.food.label).font(.must.archivo(20, .semibold)).foregroundStyle(Color.must.ink)
                    Spacer(minLength: 8)
                    Text(stores.isEmpty ? "" : "no fim · \(stores)").font(.must.archivo(13)).foregroundStyle(Color.must.secondary).lineLimit(1)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(food) { item in
                            Button { editing = item } label: {
                                ShoppingRuleChip(text: chipText(item), tone: chipTone(item))
                            }
                            .buttonStyle(MustPressStyle())
                        }
                        if !alcohol.isEmpty {
                            ShoppingRuleChip(text: "álcool \(ShoppingReport.litres(litres)) de \(ShoppingReport.litres(limit)) L",
                                             tone: litres > limit ? .no : .warn)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func chipText(_ item: ShoppingItem) -> String {
        let name = item.qty > 1 ? "\(item.name) × \(item.qty)" : item.name
        if item.flags.isEmpty { return "\(name) · lacrado ✓" }
        let labels = item.flags.map(\.label).joined(separator: ", ")
        return "\(name) · \(labels) ✗"
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
        VStack(alignment: .leading, spacing: 10) {
            Micro("nada na lista ainda")
            Text("Toque em + pra anotar o que quer trazer. As regras da volta conferem cada item.").mustMeta()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.must.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
