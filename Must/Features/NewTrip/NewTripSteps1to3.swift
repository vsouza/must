import MapKit
import SwiftUI

// Passos 1 a 3 do fluxo Nova viagem (prompt 28 · F3): Pra onde?, Quando?, Quais cidades?

/// Busca de cidade do MapKit (sem chave, sem cota). Offline não pesquisa; o país sai da lista local.
@MainActor
@Observable
final class DestinationSearch: NSObject, MKLocalSearchCompleterDelegate {
    struct Hit: Identifiable, Equatable {
        var id: String { title + "|" + subtitle }
        var title: String
        var subtitle: String
        var completion: MKLocalSearchCompletion?
        static func == (a: Hit, b: Hit) -> Bool { a.id == b.id }
    }

    struct Resolved {
        var name: String
        var countryCode: String?
        var latitude: Double
        var longitude: Double
        var timeZoneId: String?
    }

    private(set) var hits: [Hit] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(_ text: String, online: Bool) {
        guard online, text.trimmingCharacters(in: .whitespaces).count >= 2 else {
            hits = []
            completer.cancel()
            return
        }
        completer.queryFragment = text
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { // o MapKit chama o delegate no main
            self.hits = self.completer.results.prefix(5).map { Hit(title: $0.title, subtitle: $0.subtitle, completion: $0) }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.hits = [] }
    }

    func resolve(_ hit: Hit) async -> Resolved? {
        guard let completion = hit.completion else { return nil }
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let placemark = item.placemark
        return Resolved(name: hit.title, countryCode: placemark.isoCountryCode,
                        latitude: placemark.coordinate.latitude, longitude: placemark.coordinate.longitude,
                        timeZoneId: item.timeZone?.identifier)
    }
}

// MARK: - 1 · Pra onde?

struct NewTripStep1: View {
    var model: NewTripModel
    @Environment(\.tripCreator) private var creator
    @Environment(Services.self) private var services
    @State private var query = ""
    @State private var search = DestinationSearch()
    @State private var resolving = false
    @FocusState private var focused: Bool

    private var offline: Bool { services.connectivity.status == .offline }
    private var existing: Set<String> { creator.existingCountryCodes() }

    private var countries: [NewTripCatalog.Country] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            if let selected = NewTripCatalog.country(code: model.draft.countryCode) { return [selected] }
            return []
        }
        return NewTripCatalog.search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewTripSection(text: "Destino")
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold)).foregroundStyle(V8.ink)
                TextField("", text: $query, prompt: Text("país ou cidade").foregroundStyle(V8.mute))
                    .font(V8Font.text(22, weight: .semibold))
                    .foregroundStyle(V8.ink)
                    .focused($focused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .onSubmit { useTyped() }
                    .onChange(of: query) { _, text in search.update(text, online: !offline) }
            }
            .padding(.horizontal, 22).frame(minHeight: 66)
            .background(Capsule().fill(V8.white))
            .overlay(Capsule().strokeBorder(V8.bone, lineWidth: 1.5))

            if offline {
                Text("sem internet · digite à mão, o resto funciona")
                    .font(V8Font.text(13)).foregroundStyle(V8.mute).padding(.top, 10)
            }

            VStack(spacing: 0) {
                ForEach(countries) { country in countryRow(country) }
                ForEach(search.hits.filter { hit in !countries.contains { $0.name == hit.title } }) { hit in cityRow(hit) }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty, countries.isEmpty, search.hits.isEmpty {
                    Button { useTyped() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Usar “\(query.trimmingCharacters(in: .whitespaces))”").font(V8Font.text(17, weight: .bold))
                            Text("destino digitado à mão").font(V8Font.text(15)).foregroundStyle(V8.mute)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)

            if model.hasDestination, NewTripCatalog.country(code: model.draft.countryCode) == nil {
                selectedManual
            }

            NewTripSection(text: "Cor da capa · vem do país, você troca").padding(.top, 34)
            swatches
            NewTripNote(text: "A cor aparece na capa, no selo e no colecionável. Tinta, papel e laranja não mudam.").padding(.top, 20)
        }
    }

    private var selectedManual: some View {
        HStack(spacing: 14) {
            radio(color: current)
            Text(model.draft.name).font(V8Font.text(20, weight: .bold)).foregroundStyle(V8.ink)
            Spacer()
            V8Glyph(.check).frame(width: 22, height: 22).foregroundStyle(V8.ink)
        }
        .padding(.vertical, 16)
    }

    private var current: Color {
        model.draft.colorHex.isEmpty ? V8.mute : Color(hex: UInt32(model.draft.colorHex.dropFirst(), radix: 16) ?? 0x121212)
    }

    private func radio(color: Color, dim: Bool = false) -> some View {
        ZStack {
            Circle().fill(color)
            Circle().fill(V8.paper).frame(width: 14, height: 14)
        }
        .frame(width: 44, height: 44).opacity(dim ? 0.6 : 1)
    }

    private func countryRow(_ country: NewTripCatalog.Country) -> some View {
        let taken = existing.contains(country.code)
        let selected = model.draft.countryCode == country.code
        let swatch = Color(hex: UInt32(NewTripCatalog.coverHex(for: country.code).dropFirst(), radix: 16) ?? 0)
        return Button {
            guard !taken else { return }
            model.choose(country: country)
            query = ""
            focused = false
        } label: {
            HStack(spacing: 16) {
                radio(color: swatch, dim: taken)
                VStack(alignment: .leading, spacing: 3) {
                    Text(country.name).font(V8Font.text(20, weight: .bold)).lineLimit(1)
                    Text(taken ? "você já tem uma viagem aqui" : country.subtitle)
                        .font(V8Font.text(15)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(taken ? V8.mute.opacity(0.75) : V8.ink, V8.mute)
                Spacer(minLength: 4)
                if selected && !taken { V8Glyph(.check).frame(width: 22, height: 22).foregroundStyle(V8.ink) }
            }
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Rectangle().fill(V8.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(taken)
        .accessibilityLabel(taken ? "\(country.name), você já tem uma viagem aqui" : country.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func cityRow(_ hit: DestinationSearch.Hit) -> some View {
        Button {
            Task { await pick(hit) }
        } label: {
            HStack(spacing: 16) {
                radio(color: V8.mute, dim: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.title).font(V8Font.text(18, weight: .bold)).lineLimit(1)
                    Text(hit.subtitle.isEmpty ? "cidade" : hit.subtitle).font(V8Font.text(15)).foregroundStyle(V8.mute).lineLimit(1)
                }
                .foregroundStyle(V8.ink)
                Spacer()
                if resolving { ProgressView() }
            }
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Rectangle().fill(V8.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Escolheu uma cidade: o país vem do lugar achado e a cidade já entra na lista do passo 3.
    private func pick(_ hit: DestinationSearch.Hit) async {
        resolving = true
        defer { resolving = false }
        guard let place = await search.resolve(hit) else { useTyped(hit.title); return }
        if let code = place.countryCode, let country = NewTripCatalog.country(code: code) {
            guard !existing.contains(code) else { model.draft.name = ""; return }
            model.choose(country: country)
            if !model.draft.cities.contains(where: { $0.name == place.name }) && place.name != country.name {
                model.addCity(name: place.name, latitude: place.latitude, longitude: place.longitude, timeZoneId: place.timeZoneId)
            }
        } else {
            model.chooseManual(name: hit.title)
        }
        query = ""
        focused = false
    }

    private func useTyped(_ text: String? = nil) {
        model.chooseManual(name: text ?? query)
        query = ""
        focused = false
    }

    private var swatches: some View {
        HStack(spacing: 10) {
            ForEach(NewTripCatalog.swatches, id: \.self) { rgb in
                let hex = NewTripCatalog.hex(rgb)
                let on = model.draft.colorHex.uppercased() == hex
                Button { model.draft.colorHex = hex } label: {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: rgb))
                        .aspectRatio(1, contentMode: .fit)
                        .padding(5)
                        .overlay {
                            if on { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(V8.ink, lineWidth: 2.5) }
                        }
                        .frame(minWidth: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cor \(hex)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - 2 · Quando?

struct NewTripStep2: View {
    var model: NewTripModel
    private let cal = NewTripModel.calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthTitle).font(V8Font.display(30)).tracking(-1).foregroundStyle(V8.ink)
                Spacer()
                HStack(spacing: 4) {
                    Button { model.shiftMonth(-1) } label: { V8Glyph(.back).frame(width: 14, height: 14).frame(width: 44, height: 44) }
                        .accessibilityLabel("Mês anterior")
                    Button { model.shiftMonth(1) } label: { V8Glyph(.back).rotationEffect(.degrees(180)).frame(width: 14, height: 14).frame(width: 44, height: 44) }
                        .accessibilityLabel("Próximo mês")
                }
                .foregroundStyle(V8.ink).buttonStyle(.plain)
            }
            weekdays.padding(.top, 10)
            grid.padding(.top, 6)

            if let until = model.daysUntilStart, let start = model.draft.start {
                HStack(alignment: .bottom, spacing: 16) {
                    Text("\(until)").font(V8Font.numeral(96)).tracking(-5.8).foregroundStyle(V8.orange)
                        .lineLimit(1).fixedSize()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(until == 1 ? "dia pra embarcar" : "dias pra embarcar").font(V8Font.text(20, weight: .bold)).foregroundStyle(V8.ink)
                        if let end = model.draft.end, let days = model.tripDays {
                            SpecLabel("\(short(start)) → \(short(end)) · \(days) dias")
                        } else {
                            SpecLabel("escolha a volta")
                        }
                    }
                    .padding(.bottom, 6)
                }
                .padding(.top, 28)
                .accessibilityElement(children: .combine)
            } else {
                NewTripNote(text: "Toque na ida e depois na volta.").padding(.top, 24)
            }

            Button { model.clearDates() } label: {
                V8Pill(model.draft.start == nil ? "Ainda não sei" : "Ainda não sei · limpar datas", active: model.draft.start == nil)
            }
            .buttonStyle(.plain).padding(.top, 22)
            NewTripNote(text: "Sem datas a viagem fica em plano (como Roma) e a capa mostra só o destino.").padding(.top, 12)
        }
    }

    private var monthTitle: String {
        var style = Date.FormatStyle().locale(NewTripCatalog.locale).month(.wide).year()
        style.timeZone = cal.timeZone
        return model.visibleMonth.formatted(style).replacingOccurrences(of: " de ", with: " ")
    }

    private func short(_ d: Date) -> String {
        var style = Date.FormatStyle().locale(NewTripCatalog.locale).weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = cal.timeZone
        return d.formatted(style).replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " ")
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(["seg", "ter", "qua", "qui", "sex", "sáb", "dom"], id: \.self) { d in
                Text(d.uppercased()).font(V8Font.mono(11, weight: .semibold)).tracking(1.2).foregroundStyle(V8.mute)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// Semanas do mês (segunda primeiro); nil = célula vazia.
    private var weeks: [[Date?]] {
        guard let range = cal.range(of: .day, in: .month, for: model.visibleMonth) else { return [] }
        let lead = (cal.component(.weekday, from: model.visibleMonth) + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for d in range { cells.append(cal.date(byAdding: .day, value: d - 1, to: model.visibleMonth)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { col, day in cell(day, column: col) }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ day: Date?, column: Int) -> some View {
        if let day {
            let start = model.draft.start, end = model.draft.end
            let isStart = start == day, isEnd = end == day
            let inside = start != nil && end != nil && day > start! && day < end!
            Button { model.tapDay(day) } label: {
                ZStack {
                    if inside || (isStart && end != nil) || isEnd {
                        // A faixa liga ida e volta; nas pontas só metade, e quebra nas pontas da semana.
                        HStack(spacing: 0) {
                            Rectangle().fill(isStart ? .clear : V8.orange.opacity(0.22))
                            Rectangle().fill(isEnd ? .clear : V8.orange.opacity(0.22))
                        }
                        .frame(height: 40)
                    }
                    if isStart || isEnd { Capsule().fill(V8.orange).frame(height: 40) }
                    Text("\(cal.component(.day, from: day))")
                        .font(V8Font.mono(17, weight: .bold)).foregroundStyle(V8.ink)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(day.formatted(Date.FormatStyle(timeZone: cal.timeZone).locale(NewTripCatalog.locale).day().month(.wide)))
            .accessibilityAddTraits(isStart || isEnd ? .isSelected : [])
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

// MARK: - 3 · Quais cidades?

struct NewTripStep3: View {
    var model: NewTripModel
    @Environment(Services.self) private var services
    @State private var adding = false
    @State private var typed = ""
    @State private var search = DestinationSearch()
    @FocusState private var focused: Bool

    private var offline: Bool { services.connectivity.status == .offline }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewTripSection(text: "Ordem da viagem · use as setas pra reordenar")
            VStack(spacing: 0) {
                ForEach(Array(model.draft.cities.enumerated()), id: \.element.id) { i, city in row(i, city) }
            }
            .overlay(alignment: .top) { Rectangle().fill(V8.rule).frame(height: 1) }

            addButton.padding(.top, 20)
            if adding { addPanel.padding(.top, 14) }

            let check = model.nightsCheck
            Text(checkText(check)).font(V8Font.text(15)).foregroundStyle(check.matches ? V8.mute : V8.orangeDeep)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 18)
        }
    }

    private func checkText(_ c: (sum: Int, of: Int?, matches: Bool)) -> String {
        guard let total = c.of else {
            return "\(c.sum) \(c.sum == 1 ? "noite" : "noites") no total. Voltar a uma cidade vale (Tóquio 1 e 2 contam como a mesma)."
        }
        let days = total + 1
        let base = "\(c.sum) \(c.sum == 1 ? "noite" : "noites") de \(total)"
        if c.matches { return "\(base) · bate os \(days) dias. Voltar a uma cidade vale (Tóquio 1 e 2 contam como a mesma)." }
        return "\(base) · não bate os \(days) dias. Ajuste as noites ou siga assim e acerte depois."
    }

    private func row(_ i: Int, _ city: NewTripDraft.City) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Button { model.moveCity(id: city.id, by: -1) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 22)
                }
                .disabled(i == 0).accessibilityLabel("Subir \(city.name)")
                Button { model.moveCity(id: city.id, by: 1) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 22)
                }
                .disabled(i == model.draft.cities.count - 1).accessibilityLabel("Descer \(city.name)")
            }
            .foregroundStyle(V8.mute).buttonStyle(.plain)
            Text("\(i + 1)").font(V8Font.numeral(34)).foregroundStyle(V8.orangeDeep).frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(city.name).font(V8Font.text(21, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1)
                Text(detail(i, city)).font(V8Font.text(14)).foregroundStyle(V8.mute).lineLimit(2)
            }
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                V8RoundButton(diameter: 44, label: "Menos uma noite em \(city.name)", action: {
                    model.setNights(city.nights - 1, cityId: city.id)
                }) { size in Capsule().fill(.foreground).frame(width: 12, height: 2).frame(width: size, height: size) }
                VStack(spacing: 2) {
                    Text("\(city.nights)").font(V8Font.mono(22, weight: .bold)).foregroundStyle(V8.ink)
                    SpecLabel(city.nights == 1 ? "noite" : "noites")
                }
                .frame(minWidth: 46)
                V8RoundButton(diameter: 44, label: "Mais uma noite em \(city.name)", action: {
                    model.setNights(city.nights + 1, cityId: city.id)
                }) { size in V8Glyph(.plus).frame(width: size, height: size) }
            }
            .foregroundStyle(V8.ink)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.rule).frame(height: 1) }
        .contextMenu {
            Button("Tirar \(city.name)", role: .destructive) { model.removeCity(id: city.id) }
        }
        .accessibilityElement(children: .contain)
    }

    private func detail(_ i: Int, _ city: NewTripDraft.City) -> String {
        var parts: [String] = []
        if let r = model.cityRange(at: i) {
            var style = Date.FormatStyle(timeZone: NewTripModel.calendar.timeZone).locale(NewTripCatalog.locale).day()
            let day = r.from.formatted(style)
            style = style.month(.abbreviated)
            parts.append("\(day) → \(r.to.formatted(style).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " "))")
        }
        parts.append("fuso \(NewTripCatalog.zoneLabel(city.timeZoneId ?? model.draft.timeZoneId))")
        return parts.joined(separator: " · ")
    }

    private var addButton: some View {
        Button { adding.toggle() } label: {
            HStack(spacing: 16) {
                Circle().fill(V8.orange).frame(width: 52, height: 52)
                    .overlay { V8Glyph(.plus).frame(width: 22, height: 22).foregroundStyle(V8.ink) }
                Text("Adicionar cidade").font(V8Font.text(18, weight: .bold)).foregroundStyle(V8.ink)
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(V8.ruleStrongColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }

    private var addPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            let suggestions = NewTripCatalog.suggestedCities(for: model.draft.countryCode)
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.name) { s in
                            Button { model.addCity(name: s.name, latitude: s.latitude, longitude: s.longitude); adding = false } label: {
                                V8Pill(s.name)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            TextField("", text: $typed, prompt: Text(offline ? "nome da cidade (à mão)" : "buscar cidade").foregroundStyle(V8.mute))
                .font(V8Font.text(18, weight: .semibold)).foregroundStyle(V8.ink)
                .padding(.horizontal, 18).frame(minHeight: 52)
                .background(Capsule().fill(V8.white)).overlay(Capsule().strokeBorder(V8.bone, lineWidth: 1.5))
                .focused($focused).submitLabel(.done).autocorrectionDisabled()
                .onSubmit { commitTyped() }
                .onChange(of: typed) { _, t in search.update(t, online: !offline) }
            ForEach(search.hits) { hit in
                Button {
                    Task {
                        if let r = await search.resolve(hit) {
                            model.addCity(name: r.name, latitude: r.latitude, longitude: r.longitude, timeZoneId: r.timeZoneId)
                        } else { model.addCity(name: hit.title) }
                        typed = ""; adding = false
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.title).font(V8Font.text(16, weight: .bold))
                        Text(hit.subtitle).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
                    }
                    .foregroundStyle(V8.ink).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            if !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { commitTyped() } label: { V8Pill("Usar “\(typed.trimmingCharacters(in: .whitespaces))”", active: true) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func commitTyped() {
        let name = typed.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let known = NewTripCatalog.suggestedCities(for: model.draft.countryCode)
            .first { NewTripCatalog.fold($0.name) == NewTripCatalog.fold(name) }
        model.addCity(name: known?.name ?? name, latitude: known?.latitude ?? 0, longitude: known?.longitude ?? 0)
        typed = ""; adding = false
    }
}
