import SwiftData
import SwiftUI

/// Adicionar ou editar um item de compra à mão. Salvar roda a checagem (`ShoppingChecks`) e liga o gasto/loja (`ShoppingPurchase`).
struct ShoppingItemEditor: View {
    /// Item existente (nil = novo).
    var item: ShoppingItem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]

    @State private var name = ""
    @State private var category: ShoppingCategory = .other
    @State private var storeId: String?
    @State private var storeName = ""
    @State private var area = ""
    @State private var estText = ""
    @State private var qty = 1
    @State private var status: ShoppingStatus = .want
    @State private var paidText = ""
    @State private var taxFree = false
    @State private var ingredients = ""
    @State private var notes = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    private var region: Region { store.region }
    private var shopStores: [Place] {
        places.filter { $0.list?.id == "shop" }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        CutSheet(title: item == nil ? "Novo item" : "Editar item", corner: ["Compras", region.shortName],
                 footer: "Salvar", footerEnabled: !trimmedName.isEmpty, onFooter: save) {
            field("nome") { TextField("ramen tonkotsu instantâneo", text: $name).font(V8Font.text(16, weight: .semibold)) }

            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("categoria", size: 10, color: V8.mute)
                FlowLayout(spacing: 8) {
                    ForEach(ShoppingCategory.allCases) { option in
                        Button { category = option } label: { Pill(option.label, isOn: category == option) }
                            .buttonStyle(MustPressStyle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("loja", size: 10, color: V8.mute)
                FlowLayout(spacing: 8) {
                    ForEach(shopStores) { place in
                        Button {
                            storeId = place.id
                            if area.isEmpty { area = place.area ?? "" }
                        } label: { Pill(place.name, isOn: storeId == place.id) }
                            .buttonStyle(MustPressStyle())
                    }
                    Button { storeId = nil } label: { Pill("outra loja", isOn: storeId == nil) }
                        .buttonStyle(MustPressStyle())
                }
                if storeId == nil {
                    field("nome da loja") { TextField("Map Camera", text: $storeName).font(V8Font.text(15)) }
                }
            }

            field("bairro (opcional)") { TextField("Shinjuku", text: $area).font(V8Font.text(15)) }
            field("preço total estimado (\(region.currencySymbol))") {
                TextField("95000", text: $estText).font(V8Font.mono(17)).keyboardType(.numberPad)
            }

            CutBox(label: "quantidade") {
                Stepper("\(qty)", value: $qty, in: 1...99).font(V8Font.mono(15))
            }

            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("situação", size: 10, color: V8.mute)
                FlowLayout(spacing: 8) {
                    ForEach(ShoppingStatus.allCases) { option in
                        Button { status = option } label: { Pill(option.label, isOn: status == option) }
                            .buttonStyle(MustPressStyle())
                    }
                }
            }

            if status == .bought {
                field("quanto pagou (opcional, \(region.currencySymbol))") {
                    TextField("o estimado, se vazio", text: $paidText).font(V8Font.mono(17)).keyboardType(.numberPad)
                }
            }

            Toggle(isOn: $taxFree) {
                FormRow("Tem recibo tax-free", subtitle: "entra no reembolso da saída, se a loja/dia passar de \(ShoppingReport.money(ShoppingRules.pack(for: region).limits.taxFreeMinYen, currency: region == .it ? "EUR" : "JPY"))")
            }
            .toggleStyle(.must)

            if category == .food {
                field("ingredientes (a checagem de porco e leite cru lê daqui)") {
                    TextField("arroz, caldo de porco, tempero…", text: $ingredients, axis: .vertical)
                        .font(V8Font.text(15)).lineLimit(2...6)
                }
            }
            field("observação (volume, sabor…)") {
                TextField("720 ml · sabor matcha", text: $notes, axis: .vertical).font(V8Font.text(15)).lineLimit(1...4)
            }

            Text("Comprado vira gasto de compras e marca a loja como visitada. Os alertas da volta aparecem na própria lista.")
                .font(V8Font.text(13)).foregroundStyle(V8.mute)

            if item != nil {
                CutButton(title: "Apagar") { confirmDelete = true }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Apagar \(item?.name ?? "item")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Apagar", role: .destructive) {
                if let item { ShoppingPurchase.delete(item, context: context) }
                try? context.save()
                dismiss()
            }
        } message: {
            Text("O gasto dele também sai. A loja continua visitada.")
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        CutBox(label: label) { content() }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let item else { return }
        name = item.name
        category = item.category
        storeId = item.storeId
        storeName = item.storeName
        area = item.area ?? ""
        estText = item.estPrice > 0 ? ShoppingReport.yen(item.estPrice).replacingOccurrences(of: ".", with: "") : ""
        qty = item.qty
        status = item.status
        paidText = item.paid.map { ShoppingReport.yen($0).replacingOccurrences(of: ".", with: "") } ?? ""
        taxFree = item.taxFreeReceipt
        ingredients = item.ingredients
        notes = item.notes
    }

    private func save() {
        let target: ShoppingItem
        if let item {
            target = item
        } else {
            target = ShoppingItem(name: trimmedName)
            context.insert(target)
        }
        let chosen = storeId.flatMap { id in shopStores.first { $0.id == id } }
        target.name = trimmedName
        target.category = category
        target.storeId = chosen?.id
        target.storeName = chosen == nil ? storeName.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let typedArea = area.trimmingCharacters(in: .whitespacesAndNewlines)
        target.area = typedArea.isEmpty ? chosen?.area : typedArea
        target.estPrice = TicketMoney.parse(estText)
        target.qty = max(1, qty)
        target.status = status
        target.paid = status == .bought && !paidText.isEmpty ? TicketMoney.parse(paidText) : nil
        target.taxFreeReceipt = taxFree
        target.ingredients = ingredients
        target.notes = notes
        target.flags = ShoppingChecks.flags(name: trimmedName, ingredients: ingredients, food: category == .food)
        ShoppingPurchase.sync(target, store: chosen, context: context, regionCurrency: region.currency,
                              brlPerYen: ShoppingFX.rate(for: region, userRate: settingsList.first?.fxRate),
                              brlPerUSD: settingsList.first?.brlPerUSD ?? ShoppingFX.brlPerUSD,
                              brlPerEUR: ShoppingFX.eurRate(for: region, userRate: settingsList.first?.fxRate))
        try? context.save()
        dismiss()
    }
}
