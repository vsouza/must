import SwiftUI
import UniformTypeIdentifiers

// Passos 6 a 9 do fluxo Nova viagem (prompt 28 · F3/F4): O que não pode faltar?, Quanto gastar?, Leve pro bolso, Pronto.

// MARK: - 6 · O que não pode faltar?

struct NewTripStep6: View {
    var model: NewTripModel
    @State private var sheet: Mode?
    @State private var importing = false
    @State private var message = ""

    enum Mode: String, Identifiable {
        case text, links, review
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            option(title: "Colar texto de uma IA ou lista", detail: "a resposta do ChatGPT, nota do celular, e-mail", glyph: "sparkles", filled: true) { sheet = .text }
            option(title: "Colar links", detail: "Instagram, Maps, blog · um por linha", glyph: nil, system: "link") { sheet = .links }
            option(title: "Importar salvos do Google Maps", detail: "arquivo do Takeout (.json ou .kml)", glyph: nil, system: "mappin.and.ellipse") { importing = true }
            option(title: "Começar vazio", detail: "você adiciona no caminho", glyph: "plus") {
                model.startedEmpty = true
                message = "Começa vazio. Dá pra adicionar lugares depois, em Musts."
            }
            .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .separator)).frame(height: 1) }

            if !model.draft.places.isEmpty { summary.padding(.top, 20) }
            if !message.isEmpty { NewTripNote(text: message).padding(.top, 14) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .xml, .data], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { message = "Não consegui abrir o arquivo."; return }
            let n = model.importSaved(data)
            message = n == 0 ? "Nenhum lugar nesse arquivo." : ""
            if n > 0 { sheet = .review }
        }
        .sheet(item: $sheet) { mode in
            switch mode {
            case .text: PasteSheet(model: model, title: "Colar texto", prompt: "Cole aqui a resposta da IA, a lista ou o e-mail.", isLinks: false) { sheet = .review }
            case .links: PasteSheet(model: model, title: "Colar links", prompt: "Um link por linha.", isLinks: true) { sheet = .review }
            case .review: ReviewSheet(model: model)
            }
        }
    }

    private func option(title: String, detail: String, glyph: String?, system: String? = nil, filled: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(filled ? Color.primary : .clear)
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                    if let glyph { Image(systemName: glyph).font(.body.weight(.bold)).foregroundStyle(filled ? Color.white : Color.primary) }
                    if let system { Image(systemName: system).font(.system(size: 18, weight: .medium)).foregroundStyle(Color.primary) }
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(J9.font(19, .bold)).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(J9.font(15)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, 16)
            .overlay(alignment: .top) { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .separator)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        Button { sheet = .review } label: {
            HStack(alignment: .center, spacing: 14) {
                Text("\(model.draft.places.count)").font(J9.font(54, .semibold).monospacedDigit()).foregroundStyle(V9.accent).fixedSize()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.draft.places.count == 1 ? "lugar lido" : "lugares lidos") \(model.placesSource)")
                        .font(.headline).foregroundStyle(Color.primary)
                    let breakdown = model.placesBreakdown
                    Text((breakdown.isEmpty ? "" : breakdown + " · ") + "conferir antes de salvar")
                        .font(J9.font(15)).foregroundStyle(Color.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .v9Card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toque pra conferir")
    }
}

private struct PasteSheet: View {
    var model: NewTripModel
    var title: String
    var prompt: String
    var isLinks: Bool
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(J9.font(30, .bold)).foregroundStyle(Color.primary)
            NewTripNote(text: prompt)
            TextEditor(text: $text).font(J9.font(15)).scrollContentBackground(.hidden)
                .padding(10).overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
                .frame(minHeight: 200)
            if !note.isEmpty { NewTripNote(text: note) }
            HStack(spacing: 12) {
                J9Button("Colar", prominent: false) { text = UIPasteboard.general.string ?? text }.foregroundStyle(Color.primary)
                J9Button("Ler lugares") {
                    let n = isLinks ? model.importLinks(text) : model.importText(text)
                    if n == 0 { note = "Não achei lugares aí. Tente colar mais texto." } else { dismiss(); onDone() }
                }
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .background(V9.background.ignoresSafeArea())
        .presentationDetents([.large])
    }
}

/// Conferência antes de salvar: tira o que não é lugar. Nada vai pro Places agora (a primeira sincronização resolve,
/// dentro do `ApiBudget`).
private struct ReviewSheet: View {
    var model: NewTripModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conferir").font(J9.font(30, .bold)).foregroundStyle(Color.primary)
            NewTripNote(text: "\(model.draft.places.count) lugares · \(model.placesBreakdown). Deslize pra tirar o que não é lugar.")
            List {
                ForEach(Array(model.draft.places.enumerated()), id: \.offset) { _, place in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(J9.font(17, .bold)).foregroundStyle(Color.primary)
                        Text(cityName(place)).font(J9.font(13)).foregroundStyle(Color.secondary)
                    }
                    .listRowBackground(V9.background)
                }
                .onDelete { for i in $0.sorted(by: >) { model.removePlace(at: i) } }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            J9Button("Pronto") { dismiss() }
        }
        .padding(20)
        .background(V9.background.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func cityName(_ p: NewTripDraft.PlaceDraft) -> String {
        model.draft.cities.first { $0.id == p.cityId }?.name ?? "sem cidade"
    }
}

// MARK: - 7 · Quanto gastar?

struct NewTripStep7: View {
    var model: NewTripModel
    @FocusState private var fxFocused: Bool

    private var symbol: String { NewTripCatalog.currencySymbol(model.draft.currency) }
    private var foreign: Bool { !model.draft.currency.isEmpty && model.draft.currency != "BRL" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewTripSection(text: "Moeda · vem do país")
            HStack(spacing: 10) {
                if foreign {
                    chip("\(symbol) \(NewTripCatalog.currencyName(model.draft.currency))", on: true)
                    Button { model.draft.currency = "BRL"; model.draft.fxRate = 1 } label: { chip("R$ real", on: false) }.buttonStyle(.plain)
                } else {
                    chip("R$ real", on: true)
                    if let code = NewTripCatalog.country(code: model.draft.countryCode)?.currency, code != "BRL", !code.isEmpty {
                        Button {
                            model.draft.currency = code
                            model.draft.fxRate = NewTripCatalog.cachedRate(code)
                        } label: { chip("\(NewTripCatalog.currencySymbol(code)) \(NewTripCatalog.currencyName(code))", on: false) }
                            .buttonStyle(.plain)
                    }
                }
            }
            NewTripSection(text: "Por dia, por pessoa").padding(.top, 26)
            HStack(alignment: .bottom, spacing: 8) {
                Text("\(Int(model.draft.perDayBudget ?? 0))").font(J9.font(150, .semibold).monospacedDigit()).foregroundStyle(V9.accent)
                    .lineLimit(1).minimumScaleFactor(0.4).frame(height: 150 * 0.78).accessibilityHidden(true)
                Text(symbol).font(J9.font(44, .bold)).foregroundStyle(Color.primary).padding(.bottom, 10)
                Spacer(minLength: 0)
                NewTripStepper(minusLabel: "Menos", plusLabel: "Mais", filledPlus: true,
                               onMinus: { model.stepBudget(-1) }, onPlus: { model.stepBudget(1) })
                    .padding(.bottom, 12)
            }
            .accessibilityElement(children: .contain)
            .accessibilityValue("\(Int(model.draft.perDayBudget ?? 0)) \(model.draft.currency) por dia")

            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .separator)).frame(height: 1).padding(.top, 14)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total da viagem").font(J9.font(20, .bold)).foregroundStyle(Color.primary)
                    Text(totalDetail).font(J9.font(15)).foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(money(model.totalBudget, symbol)).font(J9.font(19, .bold).monospacedDigit()).foregroundStyle(Color.primary)
                    if let brl = model.totalInReais { Text("≈ " + money(brl, "R$")).font(J9.font(17, .semibold).monospacedDigit()).foregroundStyle(Color.secondary) }
                }
            }
            .padding(.vertical, 16)
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .separator)).frame(height: 1)

            if foreign {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Câmbio").font(J9.font(20, .bold)).foregroundStyle(Color.primary)
                    HStack(spacing: 8) {
                        Text("1 \(symbol) = R$").font(J9.font(15)).foregroundStyle(Color.secondary)
                        TextField("", text: Binding(get: { model.fxText.isEmpty ? defaultText : model.fxText }, set: { model.setFX(text: $0) }))
                            .keyboardType(.decimalPad).focused($fxFocused)
                            .font(J9.font(16, .semibold).monospacedDigit()).foregroundStyle(Color.primary)
                            .padding(.horizontal, 12).frame(minWidth: 70, maxWidth: 110, minHeight: 40)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1))
                        Text("· último câmbio guardado").font(J9.font(13)).foregroundStyle(Color.secondary).lineLimit(2)
                    }
                }
                .padding(.vertical, 16)
            }
            NewTripNote(text: "O orçamento só aparece em Ajustes; o dia mostra o gasto. Exceção por lugar continua valendo.")
                .padding(.top, 6)
        }
    }

    private var defaultText: String {
        (model.draft.fxRate ?? 0).formatted(.number.locale(NewTripCatalog.locale).precision(.fractionLength(2)))
    }

    private var totalDetail: String {
        guard let days = model.tripDays else { return "sem datas ainda" }
        return "\(days) dias × \(symbol) \(Int(model.draft.perDayBudget ?? 0))"
    }

    private func money(_ v: Double?, _ sym: String) -> String {
        let n = (v ?? 0).formatted(.number.locale(NewTripCatalog.locale).precision(.fractionLength(0)))
        return "\(sym) \(n)"
    }

    private func chip(_ text: String, on: Bool) -> some View { J9Chip(text, isOn: on) }
}

// MARK: - 8 · Leve pro bolso

struct NewTripStep8: View {
    var model: NewTripModel
    @Environment(Services.self) private var services
    @State private var copied: String?

    private var maps: OfflineMaps { services.maps }
    private var lowData: Bool { services.connectivity.status == .constrained }
    private var offline: Bool { services.connectivity.status == .offline }

    var body: some View {
        @Bindable var m = model
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.draft.cities) { city in
                row(city)
            }
            if model.draft.cities.isEmpty {
                NewTripNote(text: "Sem cidades, sem mapa pra baixar. Dá pra baixar depois em Ajustes › Mapas offline.").padding(.vertical, 16)
            }
            if !model.draft.places.isEmpty {
                block(title: "Fotos dos \(model.draft.places.count) lugares",
                      detail: "\(model.draft.places.count * 3 / 2) MB · uma por lugar, 800 px", progress: 0)
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .separator)).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Só no Wi-Fi").font(J9.font(19, .bold)).foregroundStyle(Color.primary)
                    Text("no celular, nada baixa sozinho").font(J9.font(15)).foregroundStyle(Color.secondary)
                }
                Spacer()
                Toggle("Só no Wi-Fi", isOn: $m.draft.wifiOnly).labelsHidden().tint(V9.accent).padding(.trailing, 2)
            }
            .padding(.vertical, 16)
            if lowData {
                NewTripNote(text: "Modo de Pouco Dados ligado: nada baixa sozinho. Use “Baixar agora” em cada mapa.").padding(.bottom, 8)
            }
            NewTripNote(text: "Total \(totalMB) MB. Dá pra pular e baixar depois em Ajustes › Mapas offline.")
        }
        .task { await maps.refreshManifest() }
        .onAppear { applyDefaults() }
    }

    private var totalMB: Int { Int(model.estimatedBytes(maps: maps) / 1_000_000) }

    private func applyDefaults() {
        let any = model.draft.cities.contains { model.pack(for: $0) != nil }
        model.draft.downloadOfflineMaps = any && !lowData && !offline
    }

    @ViewBuilder private func row(_ city: NewTripDraft.City) -> some View {
        if let pack = model.pack(for: city) {
            let phase = maps.phases[pack.id]
            let installed = maps.isInstalled(pack.id)
            let size = maps.bytes(pack.id).map { "\($0 / 1_000_000) MB" } ?? "tamanho no servidor"
            VStack(alignment: .leading, spacing: 0) {
                block(title: "Mapa · \(city.name)", detail: detail(size: size, phase: phase, installed: installed),
                      progress: progress(phase, installed))
                if !installed, phase == nil {
                    Button { maps.download(pack) } label: { J9Chip("Baixar agora") }
                        .buttonStyle(.plain).padding(.bottom, 14)
                        .disabled(offline)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                block(title: "Mapa · \(city.name)", detail: "mapa offline de \(city.name) ainda não existe", progress: 0)
                Button {
                    UIPasteboard.general.string = model.tilesCommand(for: city)
                    copied = city.id
                } label: { J9Chip(copied == city.id ? "Comando copiado" : "Copiar comando do mapa") }
                    .buttonStyle(.plain)
                Text(model.tilesCommand(for: city)).font(J9.font(11).monospacedDigit()).foregroundStyle(Color.secondary).textSelection(.enabled)
                    .padding(.bottom, 14)
            }
        }
    }

    private func detail(size: String, phase: OfflineMaps.Phase?, installed: Bool) -> String {
        switch phase {
        case .downloading(let f): "\(size) · baixando \(Int(f * 100))%"
        case .verifying: "\(size) · conferindo"
        case .failed(let why): "\(why)"
        case nil: installed ? "\(size) · já está no aparelho" : "\(size) · na fila"
        }
    }

    private func progress(_ phase: OfflineMaps.Phase?, _ installed: Bool) -> Double {
        switch phase {
        case .downloading(let f): f
        case .verifying: 1
        default: installed ? 1 : 0
        }
    }

    private func block(title: String, detail: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(J9.font(20, .bold)).foregroundStyle(Color.primary)
            Text(detail).font(J9.font(15)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(V9.accent).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 5).padding(.top, 8)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .separator)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 9 · Pronto

/// A viagem criada: resumo simples (dias que faltam, cidades, noites, musts, voos) e o botão de abrir. Sem capa colorida.
/// Depois de "Abrir a viagem" quem mostra a viagem é a Hoje.
struct NewTripReady: View {
    var model: NewTripModel
    var onOpen: () -> Void
    var onRetry: () -> Void
    var onBack: () -> Void

    var body: some View {
        switch model.createState {
        case .failed(let message): failure(message)
        case .idle, .creating: creating
        case .done: ready
        }
    }

    private var creating: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Montando a viagem…").font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v9Screen()
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Quase lá.").font(.largeTitle.bold())
            NewTripNote(text: message)
            J9Button("Tentar de novo", action: onRetry)
            J9Button("Voltar e ajustar", prominent: false, action: onBack)
            Spacer()
        }
        .padding(V9.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .v9Screen()
    }

    private var firstCity: String { model.draft.cities.first?.name ?? model.draft.name }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(V9.accent)
                        .accessibilityHidden(true)
                    Text("\(model.draft.name) está pronta").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(model.daysUntilStart.map { "Faltam \($0) dias · \(startLine)" } ?? "Viagem em plano, sem datas ainda.")
                        .font(.body).foregroundStyle(.secondary)
                    NewTripCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(model.draft.cities.count) cidades · \(model.draft.totalNights) noites").font(.headline)
                            Text("\(model.draft.places.count) musts · \(model.draft.flights.count) voos").font(.subheadline).foregroundStyle(.secondary)
                            if let per = model.draft.perDayBudget, per > 0 {
                                let sym = NewTripCatalog.currencySymbol(model.draft.currency)
                                Text("\(sym) \(Int(per)) por dia · \(sym) \((model.totalBudget ?? 0).formatted(.number.locale(NewTripCatalog.locale).precision(.fractionLength(0)))) no total")
                                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    Text("Primeiro dia: \(firstCity)").font(.subheadline).foregroundStyle(.secondary)
                    if let flight = model.draft.flights.first { ticket(flight) }
                }
                .padding(V9.gutter)
            }
            J9Button("Abrir a viagem", action: onOpen).padding(V9.gutter).background(.bar)
        }
        .v9Screen()
        .accessibilityElement(children: .contain)
    }

    private var startLine: String {
        guard let start = model.draft.start else { return "" }
        var style = Date.FormatStyle(timeZone: NewTripModel.calendar.timeZone).locale(NewTripCatalog.locale).weekday(.abbreviated).day().month(.abbreviated).year()
        style.timeZone = NewTripModel.calendar.timeZone
        return start.formatted(style).replacingOccurrences(of: ",", with: " ·").replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " ")
    }

    private func ticket(_ f: NewTripDraft.FlightDraft) -> some View {
        let z = Airports.airport(f.from)?.timeZone ?? TimeZone(identifier: model.draft.timeZoneId) ?? .current
        let day = f.departure.map { $0.formatted(Date.FormatStyle(timeZone: z).locale(NewTripCatalog.locale).day().month(.abbreviated)).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " ") } ?? ""
        let hour = f.departure.map { $0.formatted(Date.FormatStyle(timeZone: z).locale(NewTripCatalog.locale).hour().minute()) } ?? ""
        return NewTripCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voo · \(day)").font(.footnote).foregroundStyle(.secondary)
                Text("\(f.from) → \(f.to) · \(hour)").font(.title3.weight(.semibold)).monospacedDigit()
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
