import CoreLocation
import SwiftData
import SwiftUI

/// Quero… (prompt 25 · A, `Quero.png`): uma vontade ("comprar um Seiko") vira lugar físico perto de hoje e uma parada.
/// Texto ou voz; o parser no aparelho entende o verbo e o objeto; a busca é só de lugar físico (Places com tipo, lojas de
/// marca, o board). Cada linha diz se **cabe hoje** e a que horas. Não é chat: três toques.
/// Link / Texto / Nome (o Adicionar de antes) ficam como abas secundárias.
struct QueroView: View {
    var initialText: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dayEngine) private var engine
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var model = QueroModel(provider: QueroView.provider())
    @State private var speech = SpeechInput()
    @State private var secondary: AddMode?
    @State private var saved: String?
    @State private var failure: String?
    @FocusState private var focused: Bool

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var today: Date { region.calendar.startOfDay(for: now) }

    /// Places real, o fake dos prints (`-debugPlaces fake`) ou nenhum (dados ao vivo desligados no menu de testes).
    static func provider() -> (any WantPlacesSearching)? {
        #if DEBUG
        if DebugFlags.string("debugPlaces") == "fake" || DebugFlags.string("debugAutocomplete") == "fake" { return FakeWantPlaces() }
        #endif
        return DevOverrides.liveData ? PlacesService() : nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            V8PaperBackground(dark: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.top, 8)
                    Text("Quero…")
                        .font(V8Font.display(44))
                        .tracking(-1.2)
                        .foregroundStyle(V8.white)
                        .padding(.top, 14)
                        .accessibilityAddTraits(.isHeader)
                    field.padding(.top, 14)
                    verbs.padding(.top, 12)
                    secondaryTabs.padding(.top, 12)
                    results.padding(.top, 22)
                    Color.clear.frame(height: 230)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            bottom
        }
        .preferredColorScheme(.dark)
        .sheet(item: $secondary) { mode in
            switch mode {
            case .name: BuscarNomeView(initialQuery: model.intent?.object ?? model.text, preferredListId: nil)
            default: AddLinkView(initialURL: nil, preferredListId: nil, initialMode: mode)
            }
        }
        .onAppear {
            speech.onFinal = { text in
                model.text = text
                model.submit(env())
            }
            if let initialText, model.text.isEmpty {
                model.text = initialText
                model.submit(env())
            } else if model.text.isEmpty {
                focused = true
            }
        }
        .onDisappear { speech.cancel() }
        // A rede voltou e a lista era só do aparelho: busca de novo (a consulta tem cache, não repete chamada).
        .onChange(of: services.connectivity.status) { _, status in
            if status != .offline, model.offline { model.submit(env()) }
        }
    }

    // MARK: Topo

    private var header: some View {
        HStack(alignment: .top) {
            V8CornerButton(systemName: "xmark", label: "Fechar", onInk: true) { dismiss() }
            Spacer(minLength: 12)
            V8SpecStack(lines: ["\(areaName) · \(region.timeString(now))",
                                model.verb == .comprar || model.verb == nil ? "só lojas físicas, nesta cidade" : "só lugares de verdade, nesta cidade"],
                        color: V8.muteDark, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .padding(.top, 14)
        }
    }

    private var field: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(V8.white)
                .accessibilityHidden(true)
            TextField("", text: $model.text, prompt: Text("comprar um Seiko").foregroundStyle(V8.muteDark))
                .font(V8Font.text(17, weight: .semibold))
                .foregroundStyle(V8.white)
                .tint(V8.orange)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { model.submit(env()) }
                .accessibilityLabel("O que você quer")
            Button { Task { await speech.toggle() } } label: {
                Text(speech.isListening ? "ouvindo…" : "ou fale")
                    .font(V8Font.mono(11, weight: .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(speech.isListening ? V8.orange : V8.muteDark)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel(speech.isListening ? "Parar de ouvir" : "Falar")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(V8.graphite))
        .overlay(alignment: .bottomLeading) {
            if speech.state == .denied || speech.state == .unavailable {
                Text(speech.state == .denied ? "voz desligada nos Ajustes do iPhone" : "voz indisponível agora")
                    .font(V8Font.text(12)).foregroundStyle(V8.muteDark).offset(y: 22)
            }
        }
    }

    private var verbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WantVerb.allCases, id: \.self) { verb in
                    Button { model.choose(verb, env: env()) } label: { V8Pill(verb.label, active: model.verb == verb, onInk: true) }
                        .buttonStyle(MustPressStyle())
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
        .scrollClipDisabled()
    }

    /// Link · Texto · Nome: o Adicionar de antes, como abas secundárias.
    private var secondaryTabs: some View {
        HStack(spacing: 14) {
            MonoLabel("ou adicione por", size: 9, color: V8.muteDark)
            ForEach(AddMode.allCases, id: \.self) { mode in
                Button { secondary = mode } label: {
                    Text(mode.label)
                        .font(V8Font.text(13, weight: .semibold))
                        .underline()
                        .foregroundStyle(V8.white)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel("Adicionar por \(mode.label.lowercased())")
            }
        }
    }

    // MARK: Resultado

    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.offline {
                chip("sem internet · a busca volta quando a rede voltar")
            } else if let notice = model.notice {
                chip(notice)
            }
            if let understood = model.understood {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Text("Entendi: ").foregroundStyle(V8.muteDark))\(Text(understood.object).font(V8Font.text(14, weight: .bold)).foregroundStyle(V8.white))\(Text(" · \(understood.rest)").foregroundStyle(V8.muteDark))")
                        .font(V8Font.text(14))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if model.phase == .done { MonoLabel("\(model.rows.count)", color: V8.muteDark) }
                }
                .padding(.bottom, 4)
            }
            switch model.phase {
            case .idle:
                Text("Diga o que quer — comprar, comer, ver. Eu acho o lugar de verdade, perto de hoje, e vejo se cabe no dia.")
                    .font(V8Font.text(15)).foregroundStyle(V8.muteDark).fixedSize(horizontal: false, vertical: true)
            case .searching:
                Text("procurando perto de \(areaName)…").font(V8Font.text(14)).foregroundStyle(V8.muteDark).padding(.vertical, 12)
            case .done:
                if model.rows.isEmpty {
                    Text(model.offline ? "Nada no aparelho pra isso ainda." : "Nenhum lugar físico por perto pra isso. Tente outra palavra.")
                        .font(V8Font.text(15)).foregroundStyle(V8.muteDark).padding(.vertical, 12)
                }
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { i, row in
                    Button { model.selectedId = row.id } label: {
                        QueroRowView(index: i + 1, row: row, selected: row.id == (model.selected?.id), region: region)
                    }
                    .buttonStyle(.plain)
                }
                if !model.rows.isEmpty || model.dropped > 0 {
                    MonoLabel(model.footer(region: region), size: 10, color: V8.muteDark)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(V8.orange).frame(width: 6, height: 6)
            Text(text).font(V8Font.text(13, weight: .semibold)).foregroundStyle(V8.white).lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(V8.graphite))
        .padding(.bottom, 8)
    }

    // MARK: Embaixo: o encaixe e as duas ações

    @ViewBuilder private var bottom: some View {
        VStack(spacing: 10) {
            if let saved {
                Text(saved).font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.orange)
            } else if let failure {
                Text(failure).font(V8Font.text(13)).foregroundStyle(V8.orange)
            }
            if let row = model.selected, model.phase == .done {
                fitCard(row)
                HStack(spacing: 10) {
                    BigButton(title: "Só guardar", style: .line, lineColor: V8.white, lineFill: V8.ink) { guardar(row) }
                    BigButton(title: row.slot == nil ? "Não cabe hoje" : "Encaixar hoje", style: .orange,
                              systemImage: row.slot == nil ? nil : "arrow.up.right") { encaixar(row) }
                        .disabled(row.slot == nil)
                        .opacity(row.slot == nil ? 0.45 : 1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 36)
        .padding(.bottom, 10)
        .background(BottomFade(color: V8.ink, height: 300).allowsHitTesting(false))
    }

    private func fitCard(_ row: QueroRow) -> some View {
        HStack(spacing: 14) {
            Text(row.slot.map { region.timeString($0.start) } ?? "—")
                .font(V8Font.mono(22, weight: .semibold))
                .foregroundStyle(V8.orange)
                .lineLimit(1)
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text(fitTitle(row)).font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.white).lineLimit(2)
                Text(fitDetail(row)).font(V8Font.text(13)).foregroundStyle(V8.muteDark).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(V8.graphite))
        .accessibilityElement(children: .combine)
    }

    private func fitTitle(_ row: QueroRow) -> String {
        guard let slot = row.slot else { return model.intent?.when == .amanha ? "Fica pra amanhã" : "Hoje não cabe" }
        if let after = slot.after { return "Encaixa hoje depois do \(short(after.label))" }
        if let before = slot.before { return "Encaixa hoje antes do \(short(before.label))" }
        return "Cabe agora · \(row.minutes) min até lá"
    }

    private func fitDetail(_ row: QueroRow) -> String {
        let name = short(row.result.name)
        guard let slot = row.slot else {
            return row.otherDay.map { "Só guardar deixa no board · \($0)" } ?? "o dia está cheio até 22:30 · Só guardar deixa no board"
        }
        var parts: [String] = []
        if let before = slot.before {
            parts.append(slot.detour <= 10 ? "\(name) fica no caminho pro \(short(before.label))" : "desvio de \(slot.detour) min antes do \(short(before.label))")
        } else if env().plan == nil {
            parts.append("sem dia montado: vira a parada de agora")
        }
        parts.append("\(DayFit.minutes) min lá dentro")
        return parts.joined(separator: " · ")
    }

    /// "Shinjuku Gyoen · golden" → "Shinjuku Gyoen"; "Bic Camera Shinjuku Higashi-guchi" → "Bic Camera".
    private func short(_ label: String) -> String {
        let base = label.components(separatedBy: " · ").first ?? label
        let words = base.split(separator: " ")
        return words.count > 3 ? words.prefix(2).joined(separator: " ") : base
    }

    private var listName: String {
        QueroSave.list(for: model.intent, lists: lists)?.name.capitalized ?? "Musts"
    }

    // MARK: Ações

    private func guardar(_ row: QueroRow) {
        guard let place = QueroSave.place(for: row, intent: model.intent, text: model.text, lists: lists, cityId: env().cityId,
                                          region: region, sync: services.sync, context: context) else { return }
        saved = row.result.boardPlaceId != nil ? "\(place.name) já está no board" : "Guardado em \(place.list?.name.capitalized ?? listName)"
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        }
    }

    private func encaixar(_ row: QueroRow) {
        let env = env()
        guard row.slot != nil,
              let place = QueroSave.place(for: row, intent: model.intent, text: model.text, lists: lists, cityId: env.cityId,
                                          region: region, sync: services.sync, context: context) else { return }
        do {
            _ = try QueroSave.encaixar(row, place: place, env: env, context: context)
            dismiss()
            router.push(.linha(date: today), on: .hoje)
        } catch {
            failure = "não deu pra gravar o dia: \(error.localizedDescription)"
        }
    }

    // MARK: Ambiente

    private var trip: TripInfo? { trips.first }
    private var city: City? { trip?.city(on: now, calendar: region.calendar) }
    private var areas: [Area] { AreaCatalog.areas(for: region) }

    private var plan: DayPlan? { engine.plan(for: today, region: region, context: context) }

    private var planArea: Area? { plan?.area.flatMap { id in areas.first { $0.id == id } } }

    private var gpsArea: Area? {
        guard let here = services.location.current?.coordinate else { return nil }
        let id = AreaAssigner(areas: areas).areaId(name: nil, cityId: city?.id ?? region.rawValue, lat: here.latitude, lng: here.longitude)
        return id.flatMap { id in areas.first { $0.id == id } }
    }

    private var areaName: String { planArea?.name ?? gpsArea?.name ?? city?.name ?? region.displayName }

    private func env() -> QueroEnv {
        let cityCenter = city.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? region.defaultCenter
        let gps = services.location.current?.coordinate
        let gpsInCity = gps.map { DaySolver.streetKm($0, cityCenter) < 60 } ?? false
        let origin = gpsInCity ? gps! : (planArea?.centroid.clCoordinate ?? cityCenter)
        let plan = plan
        let center = plan.flatMap { _ in planArea?.centroid.clCoordinate } ?? origin
        let cityId = city?.id ?? trip?.cities.first?.id ?? region.rawValue
        let group = AreaCatalog.cityGroup(forCityId: cityId)
        let tz = region.timeZone
        let board = places.compactMap { p -> WantBoardPlace? in
            guard AreaCatalog.cityGroup(forCityId: p.cityId) == group, p.lat != 0 || p.lng != 0 else { return nil }
            let until = p.hours?.closesAt(now, timeZone: tz).map(ListGrouping.hourLabel)
            return WantBoardPlace(id: p.id, name: p.name, lat: p.lat, lng: p.lng, listId: p.list?.id, sub: p.sub, notes: p.notes,
                                  placeId: p.placeId, area: p.area, until: until, done: p.isDone)
        }
        return QueroEnv(region: region, now: now, plan: plan, center: center, origin: origin, areaName: areaName, cityGroup: group,
                        cityId: cityId, online: services.connectivity.status != .offline, board: board,
                        useModel: settingsList.first?.onDeviceAI ?? true,
                        walkMaxKm: settingsList.first?.walkMaxKm ?? 1.5, upcoming: upcoming())
    }

    /// Próximos 14 dias aceitos e os bairros das paradas (pro "sáb · Ginza").
    private func upcoming() -> [(date: Date, areaIds: Set<String>)] {
        let start = today.addingTimeInterval(86_400)
        let end = today.addingTimeInterval(15 * 86_400)
        let days = (try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date >= start && $0.date < end && $0.accepted },
                                                                     sortBy: [SortDescriptor(\.date)]))) ?? []
        let assigner = AreaAssigner(areas: areas)
        return days.map { day in
            let ids = day.stops.compactMap { stop -> String? in
                guard let p = stop.place else { return nil }
                return assigner.areaId(name: p.area, cityId: p.cityId, lat: p.lat, lng: p.lng)
            }
            return (day.date, Set(ids))
        }
    }
}

/// Linha do Quero… (`.r` do `Quero.html`): índice laranja, nome, meta, e à direita o tempo e "cabe HH:MM".
private struct QueroRowView: View {
    var index: Int
    var row: QueroRow
    var selected: Bool
    var region: Region

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(index)")
                .font(Font(V8Fonts.bricolage(28, weight: 800, width: 80, opticalSize: 96)))
                .tracking(-1)
                .foregroundStyle(V8.orange)
                .frame(width: 30, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.result.name)
                    .font(V8Font.text(16, weight: .bold))
                    .foregroundStyle(V8.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(row.meta).font(V8Font.text(12)).foregroundStyle(V8.muteDark).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(row.minutes) min").font(V8Font.mono(10, weight: .semibold)).foregroundStyle(V8.white)
                if let slot = row.slot {
                    Text("cabe \(region.timeString(slot.start))").font(V8Font.mono(10, weight: .semibold)).foregroundStyle(V8.orange)
                } else if let other = row.otherDay {
                    Text(other).font(V8Font.mono(10, weight: .semibold)).foregroundStyle(V8.muteDark)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, selected ? 12 : 0)
        .background {
            if selected { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(V8.white.opacity(0.08)) }
        }
        .padding(.horizontal, selected ? -12 : 0)
        .overlay(alignment: .top) {
            if !selected && index > 1 { Rectangle().fill(V8.white.opacity(0.14)).frame(height: 1) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(row.slot.map { "cabe hoje às \(region.timeString($0.start))" } ?? "hoje não cabe")
    }
}

extension AddMode: Identifiable {
    var id: Self { self }
}
