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
            option(title: "Colar texto de uma IA ou lista", detail: "a resposta do ChatGPT, nota do celular, e-mail", glyph: .sparkle, filled: true) { sheet = .text }
            option(title: "Colar links", detail: "Instagram, Maps, blog · um por linha", glyph: nil, system: "link") { sheet = .links }
            option(title: "Importar salvos do Google Maps", detail: "arquivo do Takeout (.json ou .kml)", glyph: nil, system: "mappin.and.ellipse") { importing = true }
            option(title: "Começar vazio", detail: "você adiciona no caminho", glyph: .plus) {
                model.startedEmpty = true
                message = "Começa vazio. Dá pra adicionar lugares depois, em Musts."
            }
            .overlay(alignment: .bottom) { Rectangle().fill(V8.rule).frame(height: 1) }

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

    private func option(title: String, detail: String, glyph: V8Glyph.Kind?, system: String? = nil, filled: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().fill(filled ? V8.ink : .clear)
                    Circle().strokeBorder(V8.ink, lineWidth: 1.5)
                    if let glyph { V8Glyph(glyph).frame(width: 22, height: 22).foregroundStyle(filled ? V8.white : V8.ink) }
                    if let system { Image(systemName: system).font(.system(size: 18, weight: .medium)).foregroundStyle(V8.ink) }
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(V8Font.text(19, weight: .bold)).foregroundStyle(V8.ink).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(V8Font.text(15)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, 16)
            .overlay(alignment: .top) { Rectangle().fill(V8.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        Button { sheet = .review } label: {
            HStack(alignment: .center, spacing: 14) {
                Text("\(model.draft.places.count)").font(V8Font.numeral(54)).tracking(-3).foregroundStyle(V8.orange).fixedSize()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.draft.places.count == 1 ? "lugar lido" : "lugares lidos") \(model.placesSource)")
                        .font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.white)
                    let breakdown = model.placesBreakdown
                    Text((breakdown.isEmpty ? "" : breakdown + " · ") + "conferir antes de salvar")
                        .font(V8Font.text(15)).foregroundStyle(V8.muteDark)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(V8.ink))
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
            Text(title).font(V8Font.display(30)).tracking(-1).foregroundStyle(V8.ink)
            NewTripNote(text: prompt)
            TextEditor(text: $text).font(V8Font.text(15)).scrollContentBackground(.hidden)
                .padding(10).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(V8.white))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(V8.bone, lineWidth: 1))
                .frame(minHeight: 200)
            if !note.isEmpty { NewTripNote(text: note) }
            HStack(spacing: 12) {
                V8Button("Colar", .line) { text = UIPasteboard.general.string ?? text }.foregroundStyle(V8.ink)
                V8Button("Ler lugares") {
                    let n = isLinks ? model.importLinks(text) : model.importText(text)
                    if n == 0 { note = "Não achei lugares aí. Tente colar mais texto." } else { dismiss(); onDone() }
                }
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .background(V8.paper.ignoresSafeArea())
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
            Text("Conferir").font(V8Font.display(30)).tracking(-1).foregroundStyle(V8.ink)
            NewTripNote(text: "\(model.draft.places.count) lugares · \(model.placesBreakdown). Deslize pra tirar o que não é lugar.")
            List {
                ForEach(Array(model.draft.places.enumerated()), id: \.offset) { _, place in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink)
                        Text(cityName(place)).font(V8Font.text(13)).foregroundStyle(V8.mute)
                    }
                    .listRowBackground(V8.paper)
                }
                .onDelete { for i in $0.sorted(by: >) { model.removePlace(at: i) } }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            V8Button("Pronto") { dismiss() }
        }
        .padding(20)
        .background(V8.paper.ignoresSafeArea())
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
                Text("\(Int(model.draft.perDayBudget ?? 0))").font(V8Font.numeral(150)).tracking(-9).foregroundStyle(V8.orange)
                    .lineLimit(1).minimumScaleFactor(0.4).frame(height: 150 * 0.78).accessibilityHidden(true)
                Text(symbol).font(V8Font.display(44)).foregroundStyle(V8.ink).padding(.bottom, 10)
                Spacer(minLength: 0)
                NewTripStepper(minusLabel: "Menos", plusLabel: "Mais", filledPlus: true,
                               onMinus: { model.stepBudget(-1) }, onPlus: { model.stepBudget(1) })
                    .padding(.bottom, 12)
            }
            .accessibilityElement(children: .contain)
            .accessibilityValue("\(Int(model.draft.perDayBudget ?? 0)) \(model.draft.currency) por dia")

            Rectangle().fill(V8.rule).frame(height: 1).padding(.top, 14)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total da viagem").font(V8Font.text(20, weight: .bold)).foregroundStyle(V8.ink)
                    Text(totalDetail).font(V8Font.text(15)).foregroundStyle(V8.mute)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(money(model.totalBudget, symbol)).font(V8Font.mono(19, weight: .bold)).foregroundStyle(V8.ink)
                    if let brl = model.totalInReais { Text("≈ " + money(brl, "R$")).font(V8Font.mono(17, weight: .semibold)).foregroundStyle(V8.mute) }
                }
            }
            .padding(.vertical, 16)
            Rectangle().fill(V8.rule).frame(height: 1)

            if foreign {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Câmbio").font(V8Font.text(20, weight: .bold)).foregroundStyle(V8.ink)
                    HStack(spacing: 8) {
                        Text("1 \(symbol) = R$").font(V8Font.text(15)).foregroundStyle(V8.mute)
                        TextField("", text: Binding(get: { model.fxText.isEmpty ? defaultText : model.fxText }, set: { model.setFX(text: $0) }))
                            .keyboardType(.decimalPad).focused($fxFocused)
                            .font(V8Font.mono(16, weight: .semibold)).foregroundStyle(V8.ink)
                            .padding(.horizontal, 12).frame(minWidth: 70, maxWidth: 110, minHeight: 40)
                            .background(Capsule().fill(V8.white)).overlay(Capsule().strokeBorder(V8.bone, lineWidth: 1))
                        Text("· último câmbio guardado").font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(2)
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

    private func chip(_ text: String, on: Bool) -> some View { V8Pill(text, active: on) }
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
            Rectangle().fill(V8.rule).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Só no Wi-Fi").font(V8Font.text(19, weight: .bold)).foregroundStyle(V8.ink)
                    Text("no celular, nada baixa sozinho").font(V8Font.text(15)).foregroundStyle(V8.mute)
                }
                Spacer()
                Toggle("Só no Wi-Fi", isOn: $m.draft.wifiOnly).labelsHidden().tint(V8.orange).padding(.trailing, 2)
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
                    Button { maps.download(pack) } label: { V8Pill("Baixar agora", small: true) }
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
                } label: { V8Pill(copied == city.id ? "Comando copiado" : "Copiar comando do mapa", small: true) }
                    .buttonStyle(.plain)
                Text(model.tilesCommand(for: city)).font(V8Font.mono(11)).foregroundStyle(V8.mute).textSelection(.enabled)
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
            Text(title).font(V8Font.text(20, weight: .bold)).foregroundStyle(V8.ink)
            Text(detail).font(V8Font.text(15)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(V8.rule)
                    Capsule().fill(V8.orange).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 5).padding(.top, 8)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(V8.rule).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 9 · Pronto

/// A viagem criada: cor do lugar, contagem regressiva em numeral gigante, primeiro dia e o voo. É o "Pronto" do fluxo;
/// depois de "Abrir a viagem" quem mostra a viagem é a capa do app.
struct NewTripReady: View {
    var model: NewTripModel
    var onOpen: () -> Void
    var onRetry: () -> Void
    var onBack: () -> Void

    private var cover: Color { Color(hex: UInt32(model.draft.colorHex.dropFirst(), radix: 16) ?? 0x0A5C48) }

    var body: some View {
        switch model.createState {
        case .failed(let message): failure(message)
        case .idle, .creating: creating
        case .done: ready
        }
    }

    private var creating: some View {
        ZStack {
            cover.ignoresSafeArea()
            Rings(color: .white, count: 3, diameter: 420, opacity: 0.4, offset: CGSize(width: -60, height: -150)).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(.white)
                Text("Montando a viagem…").font(V8Font.text(18, weight: .bold)).foregroundStyle(.white)
            }
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("Quase lá.").font(V8Font.display(40)).tracking(-1.8).foregroundStyle(V8.ink)
            NewTripNote(text: message)
            V8Button("Tentar de novo", action: onRetry)
            V8Button("Voltar e ajustar", .line, action: onBack).foregroundStyle(V8.ink)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(V8.paper.ignoresSafeArea())
    }

    private var firstCity: String { model.draft.cities.first?.name ?? model.draft.name }

    private var ready: some View {
        ZStack(alignment: .topLeading) {
            cover.ignoresSafeArea()
            Rings(color: .white, count: 3, diameter: 420, opacity: 0.4, offset: CGSize(width: -60, height: -150)).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    if let until = model.daysUntilStart {
                        SpecLabel("Faltam \(until) dias\n\(startLine)", color: .white)
                    } else {
                        SpecLabel("Viagem em plano\nsem datas ainda", color: .white)
                    }
                    Spacer(minLength: 0)
                    SpecLabel("\(firstCity) · \(model.draft.currency)\nPronta", color: .white).multilineTextAlignment(.trailing)
                }
                .padding(.top, 20)

                Spacer(minLength: 24)
                HStack(alignment: .top) {
                    SpecLabel("\(model.draft.cities.count) cidades · \(model.draft.totalNights) noites\n\(model.draft.places.count) musts · \(model.draft.flights.count) voos", color: .white)
                    Spacer(minLength: 8)
                    if let per = model.draft.perDayBudget, per > 0 {
                        let sym = NewTripCatalog.currencySymbol(model.draft.currency)
                        SpecLabel("\(sym) \(Int(per)) por dia\n\(sym) \((model.totalBudget ?? 0).formatted(.number.locale(NewTripCatalog.locale).precision(.fractionLength(0)))) no total", color: .white).multilineTextAlignment(.trailing)
                    }
                }
                Spacer(minLength: 28)
                HStack(spacing: 10) {
                    Circle().strokeBorder(.white, lineWidth: 2).frame(width: 26, height: 26).overlay(Circle().fill(.white).frame(width: 12, height: 12))
                    SpecLabel(model.draft.name, color: .white)
                }
                SpecLabel("Primeiro dia", color: .white.opacity(0.85)).padding(.top, 18)
                Text(firstCity).font(V8Font.display(64)).tracking(-3).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.6).padding(.top, 8)
                Spacer(minLength: 16)
                if let until = model.daysUntilStart {
                    BigNumeral("\(until)", size: 200, color: .white).opacity(0.95).frame(height: 156).clipped()
                }
                if let flight = model.draft.flights.first { ticket(flight) }
                V8Button("Abrir a viagem", .orange, icon: .avancar, action: onOpen).padding(.top, 14)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .foregroundStyle(.white)
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
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voo · \(day)".uppercased()).font(V8Font.mono(12, weight: .bold)).tracking(1.2).foregroundStyle(V8.orange)
                Text("\(f.from) → \(f.to) · \(hour)").font(V8Font.text(20, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Circle().fill(V8.paper).frame(width: 48, height: 48)
                .overlay { V8Glyph(.arrow).frame(width: 18, height: 18).foregroundStyle(V8.ink) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(V8.ink))
        .accessibilityElement(children: .combine)
    }
}
