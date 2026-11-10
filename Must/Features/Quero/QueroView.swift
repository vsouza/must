import CoreLocation
import SwiftData
import SwiftUI

/// Pedir (Quero, prompt 32 §6, visual V9): uma vontade ("comprar um Seiko") vira lugar físico perto de hoje e termina
/// **sempre num lugar no mapa** ("Ver no mapa"). Texto ou voz; o parser no aparelho entende o verbo e o objeto; a busca é
/// só de lugar físico. Duas faixas: **seus Musts** (mesmo longe, na cidade de hoje) e **aqui perto agora** (fora do board).
/// Pergunta ("dá tempo…?", "que drink monto no 7-Eleven?") vira resposta curta + "Continuar no Assistente" + o lugar mais perto.
/// Link / Vídeo / Texto / Ingresso / Presente ficam embaixo ("ou guarde").
struct QueroView: View {
    var initialText: String?
    /// Página da aba de busca (iOS 26): "fechar" volta pra aba anterior.
    var inTab = false

    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dayEngine) private var engine
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(TodayContextModel.self) private var todayContext
    @Environment(\.showEvents) private var showEvents

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    @Query private var gifts: [Gift]

    @State private var model = QueroModel(provider: QueroView.provider(), extras: QueroView.extras())
    @State private var speech = SpeechInput()
    @State private var secondary: AddMode?
    @State private var saved: String?
    @State private var failure: String?
    @FocusState private var focused: Bool

    private func dismiss() {
        if inTab {
            model.text = ""
            router.leaveQuero()
        } else {
            systemDismiss()
        }
    }

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

    /// Wikipedia (sem chave) pro "ver"; fora no fake dos prints e com os dados ao vivo desligados.
    static func extras() -> WantExtras? {
        #if DEBUG
        if DebugFlags.string("debugPlaces") == "fake" || DebugFlags.string("debugAutocomplete") == "fake" { return nil }
        #endif
        return DevOverrides.liveData ? .live : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            band
            CutRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    fieldBlock
                    verbs
                    results
                    guardarSection
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(V8.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        .toolbar(.hidden, for: .navigationBar)
        .v8Legacy()
        .sheet(item: $secondary) { mode in
            switch mode {
            case .name: BuscarNomeView(initialQuery: model.intent?.object ?? model.text, preferredListId: nil)
            default: AddLinkView(initialURL: nil, preferredListId: nil, initialMode: mode)
            }
        }
        .onAppear {
            model.answerer = { [context, services, store, engine] text in
                await QueroAnswerer.answer(text, context: context, region: store.region, services: services,
                                           useModel: (try? context.fetch(FetchDescriptor<Settings>()).first?.onDeviceAI) ?? true, engine: engine)
            }
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

    // MARK: Topo (cor do bairro, régua)

    private var hasResult: Bool { model.phase != .idle || model.question != nil }

    private var band: some View {
        CutBand(photo: nil) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    if !inTab { CutCornerButton(systemName: "xmark", label: "Fechar", tint: V8.white) { dismiss() } }
                    Spacer(minLength: 8)
                    SpecStack(lines: ["QUERO · \(areaName)", hasResult && model.phase == .done ? "\(model.rows.count) achados" : region.timeString(now)],
                              color: V8.white.opacity(0.9), alignment: .trailing)
                }
                Spacer(minLength: 6)
                Text(hasResult ? "Quero em \(areaName)" : "\(areaName), quero")
                    .font(V8Font.display(hasResult ? 34 : 46))
                    .tracking(-1.2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(V8.white)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(height: hasResult ? 140 : 190)
    }

    /// O campo grande "quero ___" no bloco laranja (`CorteFluxo.png` tela 2).
    private var fieldBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $model.text, prompt: Text("comprar um Seiko").foregroundStyle(V8.ink.opacity(0.45)), axis: .vertical)
                .font(V8Font.display(hasResult ? 34 : 44))
                .tracking(-1)
                .foregroundStyle(V8.ink)
                .tint(V8.ink)
                .lineLimit(1...3)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { model.submit(env()) }
                .accessibilityLabel("O que você quer")
            HStack(alignment: .center, spacing: 12) {
                MonoLabel(speech.state == .denied ? "voz desligada nos Ajustes do iPhone"
                          : speech.state == .unavailable ? "voz indisponível agora" : "só lugares físicos",
                          size: 10, color: V8.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button { Task { await speech.toggle() } } label: {
                    Text(speech.isListening ? "OUVINDO…" : "FALAR")
                        .font(V8Font.mono(11, weight: .semibold)).tracking(1)
                        .foregroundStyle(speech.isListening ? V8.orange : V8.ink)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(speech.isListening ? V8.ink : Color.clear)
                        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isListening ? "Parar de ouvir" : "Falar")
                Button { model.submit(env()) } label: {
                    Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold)).foregroundStyle(V8.orange)
                        .frame(width: 44, height: 44).background(V8.ink).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Buscar")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V8.orange)
    }

    private var verbs: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("vontades de agora", size: 10, color: V8.mute)
            FlowLayout(spacing: 8) {
                ForEach(WantVerb.allCases, id: \.self) { verb in
                    Button { model.choose(verb, env: env()) } label: { CutChip(text: verb.label, isOn: model.verb == verb) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { IndexRule() }
    }

    // MARK: Guardar

    /// Guardar (v9): Link · Vídeo · Texto · Ingresso · Presente, e "Buscar por nome" embaixo.
    enum Guardar: CaseIterable, Hashable {
        case link, video, text, ticket, gift

        var label: String {
            switch self {
            case .link: "Link"
            case .video: "Vídeo"
            case .text: "Texto"
            case .ticket: "Ingresso"
            case .gift: "Presente"
            }
        }
    }

    private var guardarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("ou guarde", size: 10, color: V8.mute)
            FlowLayout(spacing: 8) {
                ForEach(Guardar.allCases, id: \.self) { item in
                    Button { guardar(item) } label: { CutChip(text: item.label, minHeight: 44) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Guardar \(item.label.lowercased())")
                }
                Button { secondary = .name } label: { CutChip(text: "Buscar por nome", minHeight: 44) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func guardar(_ item: Guardar) {
        switch item {
        case .link, .video: secondary = .link
        case .text: secondary = .text
        case .ticket: later { router.sheet = .ticketImport(inboxId: nil) }
        case .gift: later { router.sheet = .presenteNovo(source: nil) }
        }
    }

    /// Fecha o Quero e roda depois que a sheet sai (o `router` não abre sheet por cima de sheet).
    private func later(_ body: @escaping @MainActor () -> Void) {
        if inTab { body(); return }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            body()
        }
    }

    // MARK: Resultado

    private var boardRows: [QueroRow] { model.rows.filter { $0.result.origin == .board } }
    private var nearRows: [QueroRow] { model.rows.filter { $0.result.origin != .board } }

    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let question = model.question {
                QueroQuestionSlab(question: question) {
                    let text = question.text
                    later { router.sheet = .assistantAsk(text: text) }
                }
                if let extras = question.extras { questionExtras(extras) }
            }
            if model.offline {
                strip("sem internet · offline ok · só os seus Musts", tone: .ink)
            } else if let notice = model.notice {
                strip(notice, tone: .paper)
            }
            if let understood = model.understood {
                DayStrip {
                    (Text("Entendi: ").foregroundStyle(V8.mute) + Text(understood.object).bold() + Text(" · \(understood.rest)").foregroundStyle(V8.mute))
                        .font(V8Font.text(14)).foregroundStyle(V8.ink)
                }
            }
            if !model.giftRows.isEmpty { giftSection }
            switch model.phase {
            case .idle where model.question != nil:
                EmptyView()
            case .idle:
                Text("Diga o que quer: comprar, comer, ver. Eu acho o lugar de verdade, perto de hoje, e vejo se cabe no dia.")
                    .font(V8Font.text(15)).foregroundStyle(V8.mute)
                    .padding(.horizontal, 20).padding(.vertical, 16)
            case .searching:
                HStack(spacing: 8) { ProgressView(); Text("procurando perto de \(areaName)…").font(V8Font.text(14)).foregroundStyle(V8.mute) }
                    .padding(.horizontal, 20).padding(.vertical, 16)
            case .done:
                if model.rows.isEmpty && model.giftRows.isEmpty {
                    Text(model.offline ? "Nada no aparelho pra isso ainda." : "Nenhum lugar físico por perto pra isso. Tente outra palavra.")
                        .font(V8Font.text(15)).foregroundStyle(V8.mute)
                        .padding(.horizontal, 20).padding(.vertical, 16)
                }
                if !boardRows.isEmpty {
                    sectionBar("Seus Musts · \(boardRows.count)", trailing: "mesmo longe", tone: .orange)
                    ForEach(boardRows) { row in boardRow(row) }
                }
                if !nearRows.isEmpty {
                    sectionBar("Aqui perto agora · \(nearRows.count)", trailing: nearSources, tone: .ink)
                    ForEach(nearRows) { row in nearRow(row) }
                }
                if !model.rows.isEmpty || model.dropped > 0 {
                    MonoLabel(model.footer(region: region), size: 10, color: V8.mute)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                }
            }
        }
    }

    private var nearSources: String {
        Set(nearRows.map(\.result.origin)).contains(.places) ? "google" : "lojas"
    }

    private func strip(_ text: String, tone: DayStrip<Text>.Tone) -> some View {
        DayStrip(tone: tone) {
            Text(text.uppercased()).font(V8Font.mono(10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(tone == .ink ? V8.white : V8.ink)
        }
    }

    private func sectionBar(_ title: String, trailing: String, tone: DayStrip<Text>.Tone) -> some View {
        let color = tone == .ink ? V8.white : V8.ink
        return HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(color)
            Spacer(minLength: 8)
            Text(trailing.uppercased()).font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(color)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone == .ink ? V8.ink : V8.orange)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Numeral de distância: "850 / METROS", "2,1 / KM · 9 MIN".
    private func distanceBlock(_ meters: Double, minutes: Int?, color: Color) -> some View {
        let km = meters >= 1000
        let value = km ? (meters / 1000).formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(1)))
                       : "\(max(10, Int((meters / 10).rounded()) * 10))"
        let unit = (km ? "km" : "metros") + (minutes.map { " · \($0) min" } ?? "")
        return VStack(alignment: .leading, spacing: 2) {
            Text(value).font(V8Font.display(28, width: 78, weight: 800)).tracking(-1).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(unit.uppercased()).font(V8Font.mono(8.5)).tracking(0.8).foregroundStyle(color.opacity(0.7)).lineLimit(2)
        }
        .frame(width: 68, alignment: .leading)
    }

    private func boardRow(_ row: QueroRow) -> some View {
        let selected = row.id == model.selected?.id
        let fits = row.slot != nil
        return Button { model.selectedId = row.id } label: {
            HStack(alignment: .top, spacing: 12) {
                distanceBlock(row.result.distance, minutes: row.minutes, color: V8.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.result.name).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.meta).font(V8Font.text(13)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true)
                    Text(reason(row)).font(V8Font.text(13, weight: fits ? .regular : .semibold)).foregroundStyle(fits ? V8.mute : V8.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if fits {
                    goButton(coordinate: row.result.coordinate, name: row.result.name)
                } else {
                    CutTag(text: row.otherDay != nil || model.intent?.when == .amanha ? "amanhã" : "não dá")
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? V8.ink.opacity(0.07) : Color.clear)
            .overlay(alignment: .leading) { if selected { Rectangle().fill(V8.ink).frame(width: 5) } }
            .overlay(alignment: .bottom) { IndexRule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func nearRow(_ row: QueroRow) -> some View {
        let selected = row.id == model.selected?.id
        return Button { model.selectedId = row.id } label: {
            HStack(alignment: .top, spacing: 12) {
                distanceBlock(row.result.distance, minutes: nil, color: V8.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.result.name).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.meta).font(V8Font.text(13)).foregroundStyle(V8.muteDark).fixedSize(horizontal: false, vertical: true)
                    Text(reason(row)).font(V8Font.text(13)).foregroundStyle(V8.muteDark).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { guardar(row) } label: {
                    Text("+ BOARD").font(V8Font.mono(11, weight: .semibold)).tracking(0.8).foregroundStyle(V8.white)
                        .padding(.horizontal, 10).frame(minHeight: 44)
                        .overlay(Rectangle().stroke(V8.white, lineWidth: 2)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Guardar \(row.result.name) no board")
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? V8.graphite : V8.ink)
            .overlay(alignment: .leading) { if selected { Rectangle().fill(V8.orange).frame(width: 5) } }
            .overlay(alignment: .bottom) { Rectangle().fill(V8.white.opacity(0.18)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func goButton(coordinate: CLLocationCoordinate2D, name: String) -> some View {
        Button { MapsLinks.openApple(to: coordinate, name: name) } label: {
            Text("IR").font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.ink)
                .padding(.horizontal, 12).frame(minWidth: 44, minHeight: 44)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ir até \(name)")
    }

    /// "cabe 15:10" / "não cabe hoje · motivo".
    private func reason(_ row: QueroRow) -> String {
        if row.result.origin != .board { return "\(row.minutes) min a pé" + (row.slot.map { " · cabe \(region.timeString($0.start))" } ?? "") }
        if let slot = row.slot { return "cabe \(region.timeString(slot.start))" }
        if model.intent?.when == .amanha { return "fica pra amanhã" }
        let why = DayFit.noFitReason(plan: model.lastPlan, now: AppClock.now, region: region)
        return ["não cabe hoje", row.otherDay ?? why].joined(separator: " · ")
    }

    private var giftSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionBar("Presentes que faltam · \(model.giftRows.count)", trailing: "perto", tone: .orange)
            ForEach(model.giftRows) { g in
                CutRow(title: "\(g.title) · \(g.person)",
                       detail: "\(g.storeName) · \(g.minutes) min · \(g.isOpen ? "aberta" : "fechada agora")") {
                    goButton(coordinate: g.coordinate, name: g.storeName)
                }
            }
        }
    }

    // MARK: Pergunta

    @ViewBuilder private func questionExtras(_ extras: QueroQuestionExtras) -> some View {
        if !extras.recipes.isEmpty {
            sectionBar("Receitas do konbini · \(extras.recipes.count)", trailing: "sem fogão", tone: .orange)
            ForEach(extras.recipes) { r in
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.title).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink)
                    Text(r.ingredients.joined(separator: " + ")).font(V8Font.text(13)).foregroundStyle(V8.mute)
                    Text(r.step).font(V8Font.text(14)).foregroundStyle(V8.ink)
                    Text(r.when).font(V8Font.text(12)).foregroundStyle(V8.mute)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { IndexRule() }
                .accessibilityElement(children: .combine)
            }
        }
        if !extras.places.isEmpty {
            sectionBar("Mais perto · \(extras.places.count)", trailing: extras.mapTitle ?? "agora", tone: .ink)
            ForEach(extras.places) { p in
                HStack(alignment: .top, spacing: 12) {
                    distanceBlock(p.distance, minutes: nil, color: V8.white)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.white).fixedSize(horizontal: false, vertical: true)
                        if let line = p.note ?? p.address {
                            Text(line).font(V8Font.text(13)).foregroundStyle(V8.muteDark).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { MapsLinks.openApple(to: p.coordinate, name: p.name) } label: {
                        Text("IR").font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.white)
                            .padding(.horizontal, 12).frame(minWidth: 44, minHeight: 44)
                            .overlay(Rectangle().stroke(V8.white, lineWidth: 2)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ir até \(p.name)")
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(V8.ink)
                .overlay(alignment: .bottom) { Rectangle().fill(V8.white.opacity(0.18)).frame(height: 1) }
            }
        }
        if let note = extras.note { strip(note, tone: .paper) }
    }

    // MARK: Embaixo: ver no mapa, encaixe e guardar

    @ViewBuilder private var bottom: some View {
        let showcase = model.showcase()
        let row = model.phase == .done ? model.selected : nil
        if showcase != nil || row != nil || saved != nil || failure != nil {
            VStack(spacing: 0) {
                Rectangle().fill(V8.ink).frame(height: 2)
                if let saved {
                    Text(saved).font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.orange)
                        .padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                } else if let failure {
                    Text(failure).font(V8Font.text(13)).foregroundStyle(V8.ink)
                        .padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let row { fitCard(row) }
                HStack(spacing: 0) {
                    if let showcase {
                        Button { router.showOnMap(showcase) } label: {
                            HStack(spacing: 8) {
                                Text("VER NO MAPA").font(V8Font.mono(12, weight: .semibold)).tracking(1)
                                Image(systemName: "map").font(.system(size: 14, weight: .bold))
                            }
                            .foregroundStyle(V8.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(V8.paper)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ver no mapa")
                        .accessibilityHint("abre o mapa só com estes lugares")
                    }
                    if let row {
                        Button { encaixar(row) } label: {
                            Text(row.slot == nil ? "NÃO CABE HOJE" : "ENCAIXAR HOJE ↗")
                                .font(V8Font.mono(12, weight: .semibold)).tracking(1)
                                .foregroundStyle(V8.ink.opacity(row.slot == nil ? 0.5 : 1))
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(row.slot == nil ? V8.orange.opacity(0.35) : V8.orange)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(row.slot == nil)
                    }
                }
                .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 2) }
            }
            .padding(.bottom, inTab ? 72 : 0)
            .background(V8.paper.ignoresSafeArea(edges: .bottom))
        }
    }

    private func fitCard(_ row: QueroRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.slot.map { region.timeString($0.start) } ?? "—")
                .font(V8Font.mono(20, weight: .semibold)).foregroundStyle(V8.orange).lineLimit(1).fixedSize()
            Text(fitTitle(row)).font(V8Font.text(14, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
            Spacer(minLength: 0)
            Button("SÓ GUARDAR") { guardar(row) }
                .font(V8Font.mono(11, weight: .semibold)).tracking(0.8).foregroundStyle(V8.ink)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
    }

    private func fitTitle(_ row: QueroRow) -> String {
        guard let slot = row.slot else {
            if model.intent?.when == .amanha { return "Fica pra amanhã" }
            return "Hoje não cabe · " + DayFit.noFitReason(plan: model.lastPlan, now: AppClock.now, region: region)
        }
        if let after = slot.after { return "Encaixa hoje depois do \(short(after.label))" }
        if let before = slot.before { return "Encaixa hoje antes do \(short(before.label))" }
        return "Cabe agora · \(row.minutes) min até lá"
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
            saved = nil
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

    /// O bairro que a capa mostra (prompt 32 §3): serve de origem quando o GPS está fora da cidade da viagem.
    private var contextArea: Area? { todayContext.context.areaId.flatMap { id in areas.first { $0.id == id } } }

    private var gpsArea: Area? {
        guard let here = services.location.current?.coordinate else { return nil }
        let id = AreaAssigner(areas: areas).areaId(name: nil, cityId: city?.id ?? region.rawValue, lat: here.latitude, lng: here.longitude)
        return id.flatMap { id in areas.first { $0.id == id } }
    }

    private var areaName: String { contextArea?.name ?? planArea?.name ?? gpsArea?.name ?? city?.name ?? region.displayName }

    private func env() -> QueroEnv {
        var e = QueroEnv.make(region: region, now: now, places: places, trip: trip, settings: settingsList.first, plan: plan,
                              gps: services.location.current?.coordinate, online: services.connectivity.status != .offline,
                              upcoming: QueroEnv.upcomingDays(context: context, areas: areas, today: today),
                              areaHint: contextArea ?? planArea ?? gpsArea, shows: showEvents.today(region: region, at: now), gifts: gifts)
        // Seus Musts da cidade de hoje entram mesmo longe (a faixa "Seus Musts").
        e.boardAnyDistance = true
        return e
    }
}

extension AddMode: Identifiable {
    var id: Self { self }
}

/// A aba de busca da barra nativa: o Pedir como página. `token` recria a página quando alguém pede um texto novo.
struct QueroTabPage: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        QueroView(initialText: router.queroText, inTab: true)
            .id(router.queroToken)
    }
}
