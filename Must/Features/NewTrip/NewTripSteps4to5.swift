import PhotosUI
import SwiftUI

// Passos 4 e 5 do fluxo Nova viagem (prompt 28 · F3): Onde fica? (hospedagem) e Como vai? (voos).

private func zone(_ id: String?, fallback: String) -> TimeZone {
    TimeZone(identifier: id ?? "") ?? TimeZone(identifier: fallback) ?? .current
}

private func stamp(_ date: Date?, in zone: TimeZone, withDay: Bool = true) -> String {
    guard let date else { return "—" }
    var style = Date.FormatStyle(timeZone: zone).locale(NewTripCatalog.locale)
    style = withDay ? style.day().month(.abbreviated).hour().minute() : style.hour().minute()
    return date.formatted(style).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " ").replacingOccurrences(of: ",", with: " ·")
}

/// Pílula-botão (contorno) com ícone opcional, como os "Colar reserva / Só o bairro".
private struct NewTripAction: View {
    var title: String
    var icon: String?
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
                Text(title).font(J9.font(16, .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 18).frame(minHeight: 48)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 4 · Onde fica?

struct NewTripStep4: View {
    var model: NewTripModel
    @State private var lodgingFor: NewTripDraft.City?
    @State private var neighborhoodFor: NewTripDraft.City?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.draft.cities.isEmpty {
                NewTripNote(text: "Sem cidades ainda. Volte um passo e adicione, ou pule: a hospedagem entra depois em Viagem.")
            }
            ForEach(model.draft.cities) { city in
                NewTripSection(text: city.name).padding(.top, 4)
                if city.lodgingName != nil { lodgingCard(city) }
                else if let hood = city.neighborhoodOnly { hoodCard(city, hood) }
                else { missing(city) }
                Spacer().frame(height: 18)
            }
            NewTripNote(text: "A hospedagem vira o ponto de partida do dia e entra em “Boa noite”. Pode pular: o dia parte do GPS.")
        }
        .sheet(item: $lodgingFor) { city in LodgingSheet(model: model, cityId: city.id) }
        .sheet(item: $neighborhoodFor) { city in NeighborhoodSheet(model: model, cityId: city.id) }
    }

    private func lodgingCard(_ city: NewTripDraft.City) -> some View {
        let z = zone(city.timeZoneId, fallback: model.draft.timeZoneId)
        return Button { lodgingFor = city } label: {
            NewTripCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(city.lodgingName ?? "").font(J9.font(22, .bold)).foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if city.lodgingFromEmail { NewTripTag(text: "Lido do e-mail", filled: true) }
                    }
                    if let address = city.lodgingAddress {
                        Text(address).font(J9.font(16)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            J9Label("Entrada")
                            Text(stamp(city.checkIn, in: z)).font(J9.font(17, .bold)).foregroundStyle(Color.primary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            J9Label("Saída")
                            Text(stamp(city.checkOut, in: z)).font(J9.font(17, .bold)).foregroundStyle(Color.primary)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Toque pra editar")
    }

    private func hoodCard(_ city: NewTripDraft.City, _ hood: String) -> some View {
        Button { neighborhoodFor = city } label: {
            NewTripCard {
                VStack(alignment: .leading, spacing: 6) {
                    J9Label("Só o bairro")
                    Text(hood).font(J9.font(22, .bold)).foregroundStyle(Color.primary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func missing(_ city: NewTripDraft.City) -> some View {
        NewTripCard(dashed: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Falta a hospedagem \(NewTripModel.preposition(city.name) == "no" ? "do" : "de") \(city.name)")
                    .font(J9.font(20, .bold)).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actions(city) }
                    VStack(alignment: .leading, spacing: 10) { actions(city) }
                }
            }
        }
    }

    @ViewBuilder private func actions(_ city: NewTripDraft.City) -> some View {
        NewTripAction(title: "Colar reserva") { lodgingFor = city }
        NewTripAction(title: "Só o bairro") { neighborhoodFor = city }
    }
}

extension NewTripDraft.City: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Reserva (nome, endereço, entrada, saída): colar o e-mail preenche; tudo editável antes de salvar.
private struct LodgingSheet: View {
    var model: NewTripModel
    var cityId: String
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var name = ""
    @State private var address = ""
    @State private var checkIn = Date()
    @State private var checkOut = Date()
    @State private var fromEmail = false
    @State private var hint = ""

    private var city: NewTripDraft.City? { model.draft.cities.first { $0.id == cityId } }
    private var cityZone: TimeZone { zone(city?.timeZoneId, fallback: model.draft.timeZoneId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hospedagem · \(city?.name ?? "")").font(J9.font(30, .bold)).foregroundStyle(Color.primary)
                NewTripSection(text: "Colar reserva")
                TextEditor(text: $pasted)
                    .font(J9.font(15)).scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(10).overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
                HStack(spacing: 10) {
                    NewTripAction(title: "Colar do clipboard", icon: "doc.on.clipboard") {
                        pasted = UIPasteboard.general.string ?? pasted
                        read()
                    }
                    NewTripAction(title: "Ler") { read() }
                }
                if !hint.isEmpty { NewTripNote(text: hint) }
                NewTripSection(text: "Conferir").padding(.top, 10)
                field("Nome", text: $name)
                field("Endereço", text: $address)
                DatePicker("Entrada", selection: $checkIn).font(J9.font(16, .semibold))
                DatePicker("Saída", selection: $checkOut).font(J9.font(16, .semibold))
                HStack(spacing: 12) {
                    J9Button("Cancelar", prominent: false) { dismiss() }.foregroundStyle(Color.primary)
                    J9Button("Salvar") {
                        model.setLodging(cityId: cityId, name: name.trimmingCharacters(in: .whitespaces),
                                         address: address.trimmingCharacters(in: .whitespaces),
                                         checkIn: checkIn, checkOut: checkOut, fromEmail: fromEmail)
                        dismiss()
                    }
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if city?.lodgingName != nil {
                    Button("Tirar hospedagem", role: .destructive) { model.clearLodging(cityId: cityId); dismiss() }
                        .font(J9.font(15, .semibold))
                }
            }
            .padding(20)
        }
        .environment(\.timeZone, cityZone)
        .background(V9.background.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            J9Label(label)
            TextField("", text: text).font(J9.font(18, .semibold)).foregroundStyle(Color.primary)
                .padding(.horizontal, 16).frame(minHeight: 50)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
        }
    }

    private func load() {
        guard let city else { return }
        name = city.lodgingName ?? ""
        address = city.lodgingAddress ?? ""
        fromEmail = city.lodgingFromEmail
        let i = model.draft.cities.firstIndex { $0.id == cityId } ?? 0
        let range = model.cityRange(at: i)
        checkIn = city.checkIn ?? range.map { NewTripReaders.wall(day: $0.from, hour: 15, zone: cityZone) } ?? Date()
        checkOut = city.checkOut ?? range.map { NewTripReaders.wall(day: $0.to, hour: 11, zone: cityZone) } ?? Date()
    }

    private func read() {
        let found = NewTripReaders.lodging(from: pasted, zone: cityZone)
        guard !found.isEmpty else { hint = "Não achei nada nesse texto. Preencha à mão abaixo."; return }
        if !found.name.isEmpty { name = found.name }
        if !found.address.isEmpty { address = found.address }
        if let d = found.checkIn { checkIn = d }
        if let d = found.checkOut { checkOut = d }
        fromEmail = true
        hint = "Lido no aparelho. Confira antes de salvar."
    }
}

private struct NeighborhoodSheet: View {
    var model: NewTripModel
    var cityId: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Só o bairro").font(J9.font(30, .bold)).foregroundStyle(Color.primary)
            NewTripNote(text: "Sem reserva ainda: o dia parte desse bairro. Dá pra trocar por uma hospedagem depois.")
            TextField("", text: $text, prompt: Text("ex.: Chiado").foregroundStyle(Color.secondary))
                .font(J9.font(20, .semibold)).foregroundStyle(Color.primary)
                .padding(.horizontal, 18).frame(minHeight: 56)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
                .submitLabel(.done)
            HStack(spacing: 12) {
                J9Button("Cancelar", prominent: false) { dismiss() }.foregroundStyle(Color.primary)
                J9Button("Salvar") { model.setNeighborhood(cityId: cityId, text); dismiss() }
            }
            Spacer()
        }
        .padding(20)
        .background(V9.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear { text = model.draft.cities.first { $0.id == cityId }?.neighborhoodOnly ?? "" }
    }
}

// MARK: - 5 · Como vai?

struct NewTripStep5: View {
    var model: NewTripModel
    @State private var sheet: FlightMode?

    enum FlightMode: String, Identifiable {
        case email, photo, hand
        var id: String { rawValue }
    }

    private var outbound: [(Int, NewTripDraft.FlightDraft)] { Array(model.draft.flights.enumerated()).filter { !$0.element.isReturn }.map { ($0.offset, $0.element) } }
    private var inbound: [(Int, NewTripDraft.FlightDraft)] { Array(model.draft.flights.enumerated()).filter { $0.element.isReturn }.map { ($0.offset, $0.element) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !outbound.isEmpty {
                NewTripSection(text: "Ida")
                ForEach(outbound, id: \.0) { card($0.0, $0.1) }
            }
            if !inbound.isEmpty {
                NewTripSection(text: "Volta").padding(.top, 6)
                ForEach(inbound, id: \.0) { card($0.0, $0.1) }
            }
            if model.draft.flights.isEmpty {
                NewTripCard(dashed: true) {
                    Text("Nenhum voo ainda. Cole o e-mail, fotografe o cartão ou digite à mão.")
                        .font(J9.font(17, .semibold)).foregroundStyle(Color.primary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) { first2 }
                    NewTripAction(title: "À mão") { sheet = .hand }
                }
            }
            .padding(.top, 14)
            NewTripNote(text: "Checklist de 72 h, malas, aeroporto e pouso nasce daqui. Status ao vivo só de 24 h antes (cota AeroDataBox).")
                .padding(.top, 18)
        }
        .sheet(item: $sheet) { mode in FlightSheet(model: model, mode: mode) }
    }

    @ViewBuilder private var buttons: some View {
        first2
        NewTripAction(title: "À mão") { sheet = .hand }
    }

    @ViewBuilder private var first2: some View {
        NewTripAction(title: "Colar e-mail", icon: "link") { sheet = .email }
        NewTripAction(title: "Cartão de embarque", icon: "camera") { sheet = .photo }
    }

    private func card(_ index: Int, _ f: NewTripDraft.FlightDraft) -> some View {
        let dz = Airports.airport(f.from)?.timeZone ?? TimeZone(identifier: model.draft.timeZoneId) ?? .current
        let az = Airports.airport(f.to)?.timeZone ?? dz
        return NewTripCard {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(f.from).font(.system(.title, weight: .bold))
                        Image(systemName: "arrow.right").font(.body.weight(.bold)).frame(width: 16, height: 16).foregroundStyle(V9.accent)
                        Text(f.to).font(.system(.title, weight: .bold))
                    }
                    .foregroundStyle(Color.primary)
                    Text("\(f.number) · \(stamp(f.departure, in: dz)) → \(stamp(f.arrival, in: az, withDay: false))")
                        .font(J9.font(15)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                VStack(spacing: 8) {
                    NewTripTag(text: "Lido")
                    Button { model.removeFlight(at: index) } label: {
                        Text("Tirar").font(J9.font(13, .semibold)).foregroundStyle(Color.secondary).frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tirar voo \(f.number)")
                }
            }
        }
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
    }
}

private struct FlightSheet: View {
    var model: NewTripModel
    var mode: NewTripStep5.FlightMode
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var legs: [NewTripReaders.Leg] = []
    @State private var message = ""
    @State private var picked: PhotosPickerItem?
    @State private var reading = false
    // à mão
    @State private var number = ""
    @State private var from = ""
    @State private var to = ""
    @State private var departure = Date()
    @State private var arrival = Date()
    @State private var isReturn = false

    private var tripZone: TimeZone { TimeZone(identifier: model.draft.timeZoneId) ?? .current }
    private var year: Int? { model.draft.start.map { NewTripModel.calendar.component(.year, from: $0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(J9.font(30, .bold)).foregroundStyle(Color.primary)
                switch mode {
                case .email:
                    TextEditor(text: $pasted).font(J9.font(15)).scrollContentBackground(.hidden).frame(minHeight: 130)
                        .padding(10).overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
                    HStack(spacing: 10) {
                        NewTripAction(title: "Colar do clipboard", icon: "doc.on.clipboard") {
                            pasted = UIPasteboard.general.string ?? pasted
                            readText(pasted)
                        }
                        NewTripAction(title: "Ler") { readText(pasted) }
                    }
                case .photo:
                    PhotosPicker(selection: $picked, matching: .images) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera").font(.system(size: 14, weight: .semibold))
                            Text(reading ? "Lendo…" : "Escolher foto do cartão").font(J9.font(16, .semibold))
                        }
                        .foregroundStyle(Color.primary).padding(.horizontal, 18).frame(minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
                    }
                    .onChange(of: picked) { _, item in Task { await readPhoto(item) } }
                case .hand:
                    field("Voo (ex.: TP 82)", $number)
                    HStack(spacing: 10) { field("De (GRU)", $from); field("Para (LIS)", $to) }
                    DatePicker("Partida", selection: $departure).font(J9.font(16, .semibold))
                    DatePicker("Chegada", selection: $arrival).font(J9.font(16, .semibold))
                    Toggle("É o voo de volta", isOn: $isReturn).font(J9.font(16, .semibold)).tint(V9.accent)
                }
                if !message.isEmpty { NewTripNote(text: message) }
                ForEach(Array(legs.enumerated()), id: \.offset) { _, leg in
                    NewTripCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(leg.from) → \(leg.to)").font(J9.font(20, .bold)).foregroundStyle(Color.primary)
                            Text("\(leg.number) · \(stamp(leg.departure, in: Airports.airport(leg.from)?.timeZone ?? tripZone))")
                                .font(J9.font(15)).foregroundStyle(Color.secondary)
                        }
                    }
                }
                HStack(spacing: 12) {
                    J9Button("Cancelar", prominent: false) { dismiss() }.foregroundStyle(Color.primary)
                    J9Button(mode == .hand ? "Adicionar" : "Adicionar \(legs.count)") { save() }
                        .opacity(canSave ? 1 : 0.4).disabled(!canSave)
                }
            }
            .padding(20)
        }
        .background(V9.background.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear {
            let base = model.draft.start ?? Date()
            departure = NewTripReaders.wall(day: base, hour: 10, zone: tripZone)
            arrival = departure.addingTimeInterval(3600 * 8)
        }
    }

    private var title: String {
        switch mode {
        case .email: "Colar e-mail"
        case .photo: "Cartão de embarque"
        case .hand: "Voo à mão"
        }
    }

    private var canSave: Bool {
        mode == .hand ? (!number.isEmpty && from.count == 3 && to.count == 3) : !legs.isEmpty
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            J9Label(label)
            TextField("", text: text).font(J9.font(18, .semibold)).foregroundStyle(Color.primary)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(.horizontal, 16).frame(minHeight: 50)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
        }
    }

    private func readText(_ text: String) {
        legs = NewTripReaders.flightLegs(from: text, defaultYear: year, fallbackZone: tripZone)
        message = legs.isEmpty ? "Não achei voo nesse texto. Use “À mão”." : "Lido no aparelho. Confira antes de adicionar."
    }

    private func readPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        reading = true
        defer { reading = false }
        guard let reading = try? await TicketReader.readImage(data) else {
            message = "Não consegui ler a foto. Use “À mão”."
            return
        }
        readText(reading.text)
    }

    private func save() {
        if mode == .hand {
            model.addFlight(.init(number: number.uppercased(), from: from.uppercased(), to: to.uppercased(),
                                  departure: departure, arrival: arrival, isReturn: isReturn))
        } else {
            for (i, leg) in legs.enumerated() {
                model.addFlight(.init(number: leg.number, from: leg.from, to: leg.to, departure: leg.departure, arrival: leg.arrival,
                                      isReturn: model.isReturn(departure: leg.departure, order: i + model.draft.flights.count)))
            }
        }
        dismiss()
    }
}
