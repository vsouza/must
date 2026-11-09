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
        NavigationStack {
            Form {
                Section {
                    field("Nome") { TextField("ramen tonkotsu instantâneo", text: $name) }
                    field("Categoria") {
                        FlowLayout(spacing: 8) {
                            ForEach(ShoppingCategory.allCases) { option in
                                Button { category = option } label: { V9Chip(option.label, isOn: category == option) }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section("Loja") {
                    FlowLayout(spacing: 8) {
                        ForEach(shopStores) { place in
                            Button {
                                storeId = place.id
                                if area.isEmpty { area = place.area ?? "" }
                            } label: { V9Chip(place.name, isOn: storeId == place.id) }
                                .buttonStyle(.borderless)
                        }
                        Button { storeId = nil } label: { V9Chip("Outra loja", isOn: storeId == nil) }
                            .buttonStyle(.borderless)
                    }
                    if storeId == nil {
                        field("Nome da loja") { TextField("Map Camera", text: $storeName) }
                    }
                    field("Bairro (opcional)") { TextField("Shinjuku", text: $area) }
                }
                Section {
                    field("Preço total estimado (\(region.currencySymbol))") {
                        TextField("95000", text: $estText).monospacedDigit().keyboardType(.numberPad)
                    }
                    Stepper("Quantidade: \(qty)", value: $qty, in: 1...99)
                }
                Section("Situação") {
                    Picker("Situação", selection: $status) {
                        ForEach(ShoppingStatus.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if status == .bought {
                        field("Quanto pagou (opcional, \(region.currencySymbol))") {
                            TextField("o estimado, se vazio", text: $paidText).monospacedDigit().keyboardType(.numberPad)
                        }
                    }
                    Toggle(isOn: $taxFree) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tem recibo tax-free")
                            Text("entra no reembolso da saída, se a loja/dia passar de \(ShoppingReport.money(ShoppingRules.pack(for: region).limits.taxFreeMinYen, currency: region == .it ? "EUR" : "JPY"))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    if category == .food {
                        field("Ingredientes (a checagem de porco e leite cru lê daqui)") {
                            TextField("arroz, caldo de porco, tempero…", text: $ingredients, axis: .vertical).lineLimit(2...6)
                        }
                    }
                    field("Observação (volume, sabor…)") {
                        TextField("720 ml · sabor matcha", text: $notes, axis: .vertical).lineLimit(1...4)
                    }
                } footer: {
                    Text("Comprado vira gasto de compras e marca a loja como visitada. Os alertas da volta aparecem na própria lista.")
                }
                if item != nil {
                    Section { Button("Apagar", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(item == nil ? "Novo item" : "Editar item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(trimmedName.isEmpty) }
            }
        }
        .v9Screen(grouped: true)
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

    private func field<C: View>(_ label: String, @ViewBuilder _ content: @escaping () -> C) -> some View {
        V9Field(label) { content() }
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
