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
        VStack(spacing: 0) {
            CutScreenHeader(title: "Gasto", corner: ["hoje \(region.money(spentToday, symbol: true)) de \(region.money(budget, symbol: false))"],
                            height: 120, onBack: { dismiss() }, backIcon: "xmark")
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        MonoLabel("quanto foi?", color: V8.mute)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(region.currencySymbol).font(V8Font.mono(26, weight: .semibold)).foregroundStyle(V8.mute)
                            Text(displayAmount)
                                .font(V8Font.numeral(76)).tracking(-2)
                                .foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.4)
                        }
                        Text(fitLine).font(V8Font.text(14)).foregroundStyle(V8.mute)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .overlay(alignment: .bottom) { IndexRule() }

                    placeCard.padding(.horizontal, 20).padding(.top, 16)
                    categories.padding(.top, 14)
                    if !people.isEmpty { group.padding(.horizontal, 20).padding(.top, 14) }
                    keypad.padding(.horizontal, 20).padding(.top, 14)
                    payment.padding(.horizontal, 20).padding(.top, 14)
                    Color.clear.frame(height: 16)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(V8.paper.ignoresSafeArea())
        .cutFooter(buttonTitle, enabled: !(amount == 0 && place == nil), action: save)
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
                KanjiSeal(done: true, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                    Text(placeSubtitle(place)).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(2)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sem lugar").font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink)
                    Text("gasto solto · metrô, konbini, gorjeta").font(V8Font.text(13)).foregroundStyle(V8.mute)
                }
            }
            Spacer(minLength: 8)
            Button { picking = true } label: { Pill("Outro lugar") }
                .buttonStyle(MustPressStyle())
        }
        .padding(14)
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
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
                Button { category = cat } label: { CutChip(text: label, isOn: (category ?? .other) == cat) }
                    .buttonStyle(MustPressStyle())
            }
        }
        .padding(.horizontal, 20)
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
                            Text(key).font(.must.mono(key.count > 1 ? 17 : 26, .semibold))
                        }
                    }
                    .foregroundStyle(key.count > 1 || key == "," ? Color.must.secondary : Color.must.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .overlay(Rectangle().stroke(V8.ink, lineWidth: key.count > 1 || key == "⌫" || key == "," ? 0 : 2))
                }
                .buttonStyle(MustPressStyle())
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
                Button { method = m } label: {
                    Text(m == .cash ? "pago em dinheiro" : m.label)
                        .font(V8Font.text(14))
                        .foregroundStyle(Color.must.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(method == m ? V8.orange : Color.clear)
                        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                }
                .buttonStyle(MustPressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Grupo (prompt 32)

    private func personLabel(_ name: String) -> String { name == Settlement.me ? "Você" : name }

    /// Quem pagou e com quem dividiu. Só aparece com pessoas cadastradas na viagem.
    private var group: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("quem pagou", size: 10, color: V8.mute)
            FlowLayout(spacing: 8) {
                ForEach([Settlement.me] + people.map(\.name), id: \.self) { name in
                    let on = (paidBy.isEmpty ? Settlement.me : paidBy) == name
                    Button { paidBy = name == Settlement.me ? "" : name } label: { CutChip(text: personLabel(name), isOn: on) }
                        .buttonStyle(MustPressStyle())
                }
            }
            MonoLabel("dividido com", size: 10, color: V8.mute).padding(.top, 6)
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
                        } label: { CutChip(text: personLabel(name), isOn: chosen.contains(name)) }
                            .buttonStyle(MustPressStyle())
                    }
                }
            }
            if let share = shareLine { Text(share).font(V8Font.text(13)).foregroundStyle(V8.mute) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modeChip(_ title: String, _ mode: SplitMode) -> some View {
        Button {
            splitMode = mode
            if mode == .choose, chosen.isEmpty { chosen = Set([Settlement.me] + people.map(\.name)) }
        } label: { CutChip(text: title, isOn: splitMode == mode) }.buttonStyle(MustPressStyle())
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
        VStack(alignment: .leading, spacing: 12) {
            TextField("Buscar no board…", text: $query)
                .font(V8Font.text(16))
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            ScrollView {
                VStack(spacing: 0) {
                    Button { onPick(nil); dismiss() } label: {
                        FormRow("Sem lugar", subtitle: "gasto solto")
                    }
                    .buttonStyle(.plain)
                    ForEach(places.filter { $0.matches(query) }) { place in
                        RowDivider()
                        Button { onPick(place); dismiss() } label: {
                            FormRow(place.name, subtitle: [place.list?.displayName, place.area].compactMap { $0 }.joined(separator: " · "))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .background(V8.paper)
    }
}
