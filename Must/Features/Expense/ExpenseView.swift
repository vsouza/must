import SwiftData
import SwiftUI

/// Registrar gasto: valor no teclado próprio, lugar (GPS → parada do dia a < 150 m), categoria, forma de pagamento.
/// Com lugar, marca 済 (no `Place` e na parada do dia).
struct ExpenseView: View {
    var placeId: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \Place.name) private var places: [Place]
    @Query private var expenses: [Expense]
    @Query private var days: [PlannedDay]
    @Query private var settingsList: [Settings]
    @Query(sort: [SortDescriptor(\Companion.order), SortDescriptor(\Companion.createdAt)]) private var people: [Companion]

    private enum SplitMode { case none, all, choose }

    @State private var paidBy = ""
    @State private var splitMode: SplitMode = .all
    @State private var chosen: Set<String> = []
    @State private var digits = ""
    @State private var selectedPlaceId: String?
    @State private var noPlace = false
    @State private var category: ExpenseCategory?
    @State private var method: PaymentMethod = .card
    @State private var picking = false
    @State private var loaded = false

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var amount: Double {
        Double(digits.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var today: PlannedDay? {
        let start = region.calendar.startOfDay(for: now)
        return days.first { $0.date == start && $0.accepted }
    }

    private var spentToday: Double {
        let range = region.dayRange(now)
        return expenses.filter { range.contains($0.at) }.reduce(0) { $0 + $1.amount }
    }

    private var budget: Double { today?.budget ?? settingsList.first?.perDayBudget ?? region.defaultBudget }

    private var place: Place? {
        guard !noPlace, let id = selectedPlaceId else { return nil }
        return places.first { $0.id == id }
    }

    /// Parada do dia a < 150 m, senão a próxima parada.
    private func detectPlace() -> (id: String, label: String)? {
        let stops = today?.orderedStops ?? []
        if let here = services.location.current {
            if let hit = stops.enumerated().first(where: { $0.element.place.map { $0.location.distance(from: here) < 150 } ?? false }),
               let p = hit.element.place {
                return (p.id, "você está aqui · parada \(hit.offset + 1)")
            }
        }
        if let hit = stops.enumerated().first(where: { !$0.element.done }), let p = hit.element.place {
            return (p.id, "próxima parada · \(hit.offset + 1)")
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quanto foi?").font(.subheadline).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(region.currencySymbol).font(.title.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                            Text(displayAmount)
                                .font(.system(size: 56, weight: .semibold).monospacedDigit())
                                .lineLimit(1).minimumScaleFactor(0.4)
                        }
                        Text(fitLine).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, V9.gutter)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)

                    placeCard.padding(.horizontal, V9.gutter).padding(.top, 8)
                    categories.padding(.top, 14)
                    if !people.isEmpty { group.padding(.horizontal, V9.gutter).padding(.top, 14) }
                    keypad.padding(.horizontal, V9.gutter).padding(.top, 14)
                    payment.padding(.horizontal, V9.gutter).padding(.top, 14)
                    Color.clear.frame(height: 16)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Gasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Gasto").font(.headline)
                        Text("hoje \(region.money(spentToday, symbol: true)) de \(region.money(budget, symbol: false))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .j9Footer(buttonTitle, enabled: !(amount == 0 && place == nil), action: save)
            .v9Screen()
        }
        .sheet(isPresented: $picking) {
            PlacePicker(places: places) { picked in
                selectedPlaceId = picked?.id
                noPlace = picked == nil
                if let picked { category = picked.defaultCategory }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear(perform: load)
    }

    // MARK: Valor

    private var displayAmount: String {
        if digits.isEmpty { return "0" }
        if digits.contains(",") {
            let parts = digits.split(separator: ",", omittingEmptySubsequences: false)
            let int = Double(parts[0]) ?? 0
            return "\(region.money(int, symbol: false)),\(parts.count > 1 ? parts[1] : "")"
        }
        return region.money(amount, symbol: false)
    }

    private var fitLine: String {
        var parts: [String] = []
        if region.profile.money?.showsBRL == true, let fx = settingsList.first?.fxRate, amount > 0 {
            parts.append("≈ \((amount * fx).formatted(.money("BRL")))")
        }
        let left = budget - spentToday - amount
        parts.append(left >= 0 ? "cabe: sobram \(region.money(left)) hoje" : "passa \(region.money(-left)) da meta")
        return parts.joined(separator: " · ")
    }

    // MARK: Lugar

    private var placeCard: some View {
        HStack(spacing: 14) {
            if let place {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(V9.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.body.weight(.semibold)).lineLimit(2)
                    Text(placeSubtitle(place)).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sem lugar").font(.body.weight(.semibold))
                    Text("gasto solto · metrô, konbini, gorjeta").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Outro lugar") { picking = true }.buttonStyle(.bordered)
        }
        .v9Card(padding: 12)
    }

    private func placeSubtitle(_ place: Place) -> String {
        var parts: [String] = []
        if let detected = detectPlace(), detected.id == place.id { parts.append(detected.label) }
        if let list = place.list { parts.append(list.displayName) }
        if place.isDone { parts.append("já estava feito") }
        return parts.joined(separator: " · ")
    }

    private static let categoryOrder: [(ExpenseCategory, String)] = [
        (.coffee, "Café"), (.food, "Comida"), (.transit, "Metrô"), (.shop, "Compra"), (.ticket, "Entrada"), (.other, "Outro"),
    ]

    /// Quebra de linha (nada de rolar pro lado): em letra grande o último item não some mais.
    private var categories: some View {
        FlowLayout(spacing: 8) {
            ForEach(Self.categoryOrder, id: \.0) { cat, label in
                Button { category = cat } label: { J9Chip(label, isOn: (category ?? .other) == cat) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, V9.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Teclado

    private var keypad: some View {
        let extra = region.profile.money?.amountQuickKey ?? ","
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", extra, "0", "⌫"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(keys, id: \.self) { key in
                Button { press(key) } label: {
                    Group {
                        if key == "⌫" {
                            Image(systemName: "delete.left").font(.system(size: 20, weight: .regular))
                        } else {
                            Text(key).font(J9.font(key.count > 1 ? 17 : 26, .semibold).monospacedDigit())
                        }
                    }
                    .foregroundStyle(key.count > 1 || key == "," ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(V9.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(key == "⌫" ? "Apagar" : key)
            }
        }
    }

    private func press(_ key: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch key {
        case "⌫": if !digits.isEmpty { digits.removeLast() }
        case ",": if !digits.contains(",") { digits += digits.isEmpty ? "0," : "," }
        default:
            if let comma = digits.firstIndex(of: ","), digits.distance(from: comma, to: digits.endIndex) > 2 { return }
            guard digits.count < 9 else { return }
            if digits == "0" { digits = "" }
            if key == "000" && digits.isEmpty { return }
            digits += key
        }
    }

    // MARK: Pagamento

    private var payment: some View {
        FlowLayout(spacing: 8) {
            ForEach(region.profile.money?.paymentMethods?.compactMap(PaymentMethod.init(rawValue:)) ?? [.cash, .card], id: \.self) { m in
                Button { method = m } label: { J9Chip(m == .cash ? "pago em dinheiro" : m.label, isOn: method == m) }
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Grupo (prompt 32)

    private func personLabel(_ name: String) -> String { name == Settlement.me ? "Você" : name }

    /// Quem pagou e com quem dividiu. Só aparece com pessoas cadastradas na viagem.
    private var group: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quem pagou").font(.footnote).foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach([Settlement.me] + people.map(\.name), id: \.self) { name in
                    let on = (paidBy.isEmpty ? Settlement.me : paidBy) == name
                    Button { paidBy = name == Settlement.me ? "" : name } label: { J9Chip(personLabel(name), isOn: on) }
                        .buttonStyle(.plain)
                }
            }
            Text("Dividido com").font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
            FlowLayout(spacing: 8) {
                modeChip("Todos", .all)
                modeChip("Escolher", .choose)
                modeChip("Só meu", .none)
            }
            if splitMode == .choose {
                FlowLayout(spacing: 8) {
                    ForEach([Settlement.me] + people.map(\.name), id: \.self) { name in
                        Button {
                            if chosen.contains(name) { chosen.remove(name) } else { chosen.insert(name) }
                        } label: { J9Chip(personLabel(name), isOn: chosen.contains(name)) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if let share = shareLine { Text(share).font(J9.font(13)).foregroundStyle(Color.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modeChip(_ title: String, _ mode: SplitMode) -> some View {
        Button {
            splitMode = mode
            if mode == .choose, chosen.isEmpty { chosen = Set([Settlement.me] + people.map(\.name)) }
        } label: { J9Chip(title, isOn: splitMode == mode) }.buttonStyle(.plain)
    }

    /// "R$ 40 por pessoa" — a conta de cabeça antes de registrar.
    private var shareLine: String? {
        guard amount > 0 else { return nil }
        let count = splitMode == .all ? people.count + 1 : splitMode == .choose ? chosen.count : 0
        guard count > 1 else { return nil }
        return "\(region.money((amount / Double(count)).rounded())) por pessoa · \(count) pessoas"
    }

    private var splitWith: String {
        guard !people.isEmpty else { return "" }
        switch splitMode {
        case .none: return ""
        case .all: return Settlement.everyone
        case .choose: return Settlement.join(([Settlement.me] + people.map(\.name)).filter { chosen.contains($0) })
        }
    }

    private var buttonTitle: String {
        let money = region.money(amount)
        guard place != nil else { return "Registrar \(money)" }
        return amount == 0 ? "Marcar feito sem gasto" : "Registrar \(money) e marcar feito"
    }

    // MARK: Ações

    private func load() {
        guard !loaded else { return }
        loaded = true
        selectedPlaceId = placeId ?? detectPlace()?.id
        if let p = place {
            category = p.defaultCategory
            if let price = NumberInput.rounded(p.price), price > 0 { digits = String(price) }
        }
        if region.profile.money?.cashCommon == true { method = .cash }
    }

    private func save() {
        PlaceActions.record(amount: amount, place: place, category: category, method: method, day: today,
                            paidBy: people.isEmpty ? "" : paidBy, splitWith: splitWith, context: context)
        dismiss()
    }
}

/// Busca de lugar do board pro gasto.
private struct PlacePicker: View {
    var places: [Place]
    var onPick: (Place?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Button { onPick(nil); dismiss() } label: { J9Row("Sem lugar", subtitle: "gasto solto") }
                    .foregroundStyle(.primary)
                ForEach(places.filter { $0.matches(query) }) { place in
                    Button { onPick(place); dismiss() } label: {
                        J9Row(place.name, subtitle: [place.list?.displayName, place.area].compactMap { $0 }.joined(separator: " · "))
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar no board…")
            .navigationTitle("Lugar do gasto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
    }
}
