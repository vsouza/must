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
            HStack {
                IconButton(.fechar, label: "Fechar") { dismiss() }
                Spacer()
                Micro("gasto · hoje \(region.money(spentToday, symbol: true)) de \(region.money(budget, symbol: false))")
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)

            VStack(spacing: 6) {
                Text("Quanto foi?").font(.must.archivo(15)).foregroundStyle(Color.must.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(region.currencySymbol).font(.must.mono(26, .semibold)).foregroundStyle(Color.must.secondary)
                    MonoNumber(displayAmount, size: 76).foregroundStyle(Color.must.ink)
                }
                Text(fitLine).mustSerif(18).foregroundStyle(Color.must.secondary)
            }
            .padding(.top, 24)

            placeCard.padding(.horizontal, 22).padding(.top, 22)
            categories.padding(.top, 14)
            keypad.padding(.horizontal, 22).padding(.top, 14)
            Spacer(minLength: 8)
            payment
            PrimaryButton(buttonTitle) { save() }
                .disabled(amount == 0 && place == nil)
                .opacity(amount == 0 && place == nil ? 0.5 : 1)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .background {
            ZStack {
                Color.must.bg
                BlobBackground(style: .custom([
                    Blob(cx: 340, cy: 225, rx: 95, ry: 70, rotation: -18, fill: .green),
                    Blob(cx: 30, cy: 315, rx: 75, ry: 52, rotation: 12, fill: .blue),
                ]))
            }
            .ignoresSafeArea()
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
                KanjiSeal(done: true, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).mustPlace().lineLimit(1)
                    Text(placeSubtitle(place)).mustMeta().lineLimit(2)
                }
            } else {
                MustIconView(.yenGasto, size: 18).frame(width: 36, height: 36).background(Circle().fill(Color.must.surface))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sem lugar").mustPlace()
                    Text("gasto solto · metrô, konbini, gorjeta").mustMeta()
                }
            }
            Spacer(minLength: 8)
            Button { picking = true } label: { Pill("Outro lugar") }
                .buttonStyle(MustPressStyle())
        }
        .padding(16)
        .glass(cornerRadius: 22)
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

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.categoryOrder, id: \.0) { cat, label in
                    Button { category = cat } label: { Pill(label, isOn: (category ?? .other) == cat) }
                        .buttonStyle(MustPressStyle())
                }
            }
            .padding(.horizontal, 22)
        }
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
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(key.count > 1 || key == "⌫" || key == "," ? Color.clear : Color.must.surface2))
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
        HStack(spacing: 8) {
            ForEach(region.profile.money?.paymentMethods?.compactMap(PaymentMethod.init(rawValue:)) ?? [.cash, .card], id: \.self) { m in
                Button { method = m } label: {
                    Text(m == .cash ? "pago em dinheiro" : m.label)
                        .font(.must.archivo(14))
                        .foregroundStyle(Color.must.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(method == m ? Color.must.surface : Color.white))
                        .overlay(Capsule().strokeBorder(method == m ? Color.clear : Color.must.lineStrong))
                }
                .buttonStyle(MustPressStyle())
            }
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
        PlaceActions.record(amount: amount, place: place, category: category, method: method, day: today, context: context)
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
            SheetHandle().frame(maxWidth: .infinity)
            TextField("Buscar no board…", text: $query)
                .font(.must.archivo(16))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.must.surface, in: Capsule())
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
        .background(Color.must.bg)
    }
}
