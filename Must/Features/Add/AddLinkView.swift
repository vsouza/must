import CoreLocation
import SwiftData
import SwiftUI

/// Estado do fluxo "Adicionar por link".
@MainActor
@Observable
final class AddLinkModel {
    enum Phase: Equatable { case idle, reading, needsText(String), done, failed(String) }

    var input = ""
    var phase: Phase = .idle
    var resolved: ResolvedLink?
    var caption: Caption?
    var matches: [MatchedPlace] = []
    /// Lista escolhida por resultado.
    var listChoice: [String: String] = [:]
    /// Resultados marcados pra adicionar.
    var included: Set<String> = []
    var pastedText = ""

    var detectedSource: LinkSource? {
        let source = LinkResolver.resolve(input).source
        return source.badge == nil ? nil : source
    }

    /// Modelo no aparelho / reforço na nuvem (de Ajustes).
    var extractorOptions = AIPlaceExtractor.Options(onDevice: true, cloudBoost: false, knownAreas: [])
    /// Por onde a extração passou ("no aparelho", "reforço na nuvem", "palavras-chave").
    var extractedVia: String?

    func run(places: [Place], lists: [MustList], city: City?, region: Region, knownAreas: [String]) async {
        let link = LinkResolver.resolve(input)
        guard !link.text.isEmpty || link.url != nil else { return }
        resolved = link
        phase = .reading
        matches = []
        do {
            let caption = try await CaptionFetcher().fetch(link)
            await finish(caption, places: places, lists: lists, city: city, region: region, knownAreas: knownAreas)
        } catch {
            Log.network.error("legenda falhou: \(error.localizedDescription, privacy: .public)")
            phase = .needsText((error as? LocalizedError)?.errorDescription ?? "Não consegui ler a legenda.")
        }
    }

    /// Fallback: o usuário cola o texto da legenda.
    func runPasted(places: [Place], lists: [MustList], city: City?, region: Region, knownAreas: [String]) async {
        let source = resolved?.source ?? .text
        let caption = Caption(source: source, title: nil, text: String(pastedText.prefix(CaptionFetcher.maxLength)), url: resolved?.url)
        await finish(caption, places: places, lists: lists, city: city, region: region, knownAreas: knownAreas)
    }

    private func finish(_ caption: Caption, places: [Place], lists: [MustList], city: City?, region: Region, knownAreas: [String]) async {
        self.caption = caption
        var options = extractorOptions
        options.knownAreas = knownAreas
        let (extracted, via) = await AIPlaceExtractor.extract(from: caption, options: options)
        extractedVia = via
        matches = PlaceMatcher.match(extracted, caption: caption, places: places, lists: lists, city: city, region: region)
        listChoice = Dictionary(uniqueKeysWithValues: matches.compactMap { m in m.suggestedListId.map { (m.id, $0) } })
        included = Set(matches.prefix(1).filter { $0.existing == nil }.map(\.id))
        phase = matches.isEmpty ? .needsText("Li a legenda, mas não achei nome de lugar. Cola o trecho com o nome:") : .done
    }

    var stepLines: [(done: Bool, text: String)] {
        guard let resolved else { return [] }
        var lines: [(Bool, String)] = []
        switch resolved.source {
        case .maps: lines.append((caption != nil, "Link do Maps lido · nome e coordenada"))
        case .text: lines.append((true, "Texto lido"))
        default:
            let what = resolved.source == .youtube ? "título e descrição do vídeo" : "legenda do post"
            lines.append((caption != nil, caption != nil ? "Legenda lida · \(what)" : "Lendo a \(what)…"))
        }
        if caption != nil {
            let n = matches.count
            let via = extractedVia.map { " · \($0)" } ?? ""
            lines.append((n > 0, (n == 1 ? "1 lugar encontrado" : "\(n) lugares encontrados") + via))
        }
        return lines
    }
}

/// "Cola o link": Reel, TikTok, YouTube, Maps ou um nome → lugares do board.
struct AddLinkView: View {
    var initialURL: String?
    var preferredListId: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var model = AddLinkModel()
    @FocusState private var fieldFocused: Bool

    private var region: Region { store.region }
    private var city: City? { trips.first?.city(on: AppClock.now, calendar: region.calendar) }
    private var knownAreas: [String] { Array(Set(places.compactMap(\.area))) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .custom([
                Blob(cx: 385, cy: 430, rx: 70, ry: 90, rotation: 0, fill: .blue, opacity: 0.85),
                Blob(cx: 0, cy: 500, rx: 60, ry: 70, rotation: 0, fill: .green, opacity: 0.7),
            ]))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        IconButton(.fechar, label: "Fechar") { dismiss() }
                        Spacer()
                        Micro("adicionar")
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cola o link").mustTitle()
                        Text("Reel, TikTok, YouTube ou um nome — eu descubro o lugar").mustSerif(18).foregroundStyle(Color.must.secondary)
                    }
                    .padding(.top, 26)

                    inputField.padding(.top, 18)
                    badges.padding(.top, 14)
                    resultArea.padding(.top, 28)

                    Text(settingsList.first?.cloudBoost == true && CloudBoost.isConfigured
                         ? "Processado no aparelho · legendas difíceis vão pro Claude Haiku (só o texto)"
                         : "Processado no aparelho · nada sai do seu iPhone sem você pedir")
                        .font(.must.meta)
                        .foregroundStyle(Color.must.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)

            mainButton
        }
        .task {
            if let initialURL, model.input.isEmpty {
                model.input = initialURL
                await run()
            }
        }
    }

    // MARK: Entrada

    private var inputField: some View {
        HStack(spacing: 12) {
            MustIconView(.colarLink, size: 18).foregroundStyle(Color.must.ink)
            TextField("instagram.com/reel/…", text: $model.input)
                .font(.must.mono(15))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .submitLabel(.go)
                .onSubmit { Task { await run() } }
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in
                    model.input = text
                    await run()
                }
            }
            .labelStyle(.titleOnly)
            .buttonBorderShape(.capsule)
            .tint(Color.must.ink)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(height: 58)
        .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
    }

    private var badges: some View {
        HStack(spacing: 8) {
            ForEach([LinkSource.instagram, .tiktok, .youtube, .maps], id: \.self) { source in
                let on = model.detectedSource == source
                Text(source.badge ?? "")
                    .font(.must.mono(12, .semibold))
                    .foregroundStyle(on ? .white : Color.must.ink)
                    .frame(minWidth: 32)
                    .padding(.horizontal, 6)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Color.must.ink : Color.must.surface))
            }
            Text("Também pelo Atalho “Compartilhar → Must”").mustMeta().padding(.leading, 4)
        }
    }

    // MARK: Resultado

    @ViewBuilder private var resultArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .reading:
            HStack(spacing: 10) {
                ProgressView()
                Text(model.stepLines.first?.text ?? "Lendo…").mustMeta()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: 26)
        case .needsText(let message):
            pasteCard(message)
        case .failed(let message):
            Text(message).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D))
        case .done:
            foundCards
        }
    }

    private func pasteCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stepsView
            Text(message).font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
            TextField("cola aqui o texto da legenda", text: $model.pastedText, axis: .vertical)
                .font(.must.serif(18))
                .lineLimit(3...8)
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button {
                Task { await model.runPasted(places: places, lists: lists, city: city, region: region, knownAreas: knownAreas) }
            } label: { Pill("Ler texto", style: .green) }
                .buttonStyle(MustPressStyle())
                .disabled(model.pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .glass(cornerRadius: 26)
    }

    private var stepsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(model.stepLines.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(step.done ? Color.must.green : Color.must.surface)
                        if step.done { MustIconView(.ok, size: 12).foregroundStyle(Color.must.greenText) }
                    }
                    .frame(width: 22, height: 22)
                    Text(step.text).font(.must.archivo(14)).foregroundStyle(Color.must.secondary)
                }
            }
        }
    }

    @ViewBuilder private var foundCards: some View {
        let matches = model.matches
        VStack(spacing: -22) {
            if let first = matches.first {
                VStack(alignment: .leading, spacing: 14) {
                    stepsView
                    RowDivider()
                    Micro("encontrei")
                    matchDetail(first, big: true)
                    listPills(for: first)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .padding(.bottom, matches.count > 1 ? 30 : 0)
                .glass(cornerRadius: 26)
                .rotationEffect(.degrees(-1))
                .zIndex(0)
            }
            ForEach(Array(matches.dropFirst().enumerated()), id: \.element.id) { index, match in
                HStack(alignment: .center, spacing: 12) {
                    matchDetail(match, big: false)
                    Spacer(minLength: 8)
                    if match.existing == nil {
                        Button { toggle(match) } label: {
                            Pill(model.included.contains(match.id) ? "Incluído" : "Adicionar", style: model.included.contains(match.id) ? .green : .default)
                        }
                        .buttonStyle(MustPressStyle())
                    }
                }
                .padding(20)
                .background(Color(hex: 0xF4F5F7), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color(hex: 0x121316, opacity: 0.08), radius: 16, x: 0, y: 10)
                .rotationEffect(.degrees(index.isMultiple(of: 2) ? 1.2 : -0.8))
                .padding(.horizontal, 12)
                .zIndex(Double(index + 1))
            }
        }
    }

    private func matchDetail(_ match: MatchedPlace, big: Bool) -> some View {
        let e = match.extracted
        var meta: [String] = []
        if let area = e.area ?? match.existing?.area { meta.append(area) }
        if let sub = e.sub { meta.append(sub.lowercased()) }
        if let here = services.location.current, !match.approx {
            meta.append("\(Walk.distanceText(CLLocationDistance(CLLocation(latitude: match.lat, longitude: match.lng).distance(from: here)))) daqui")
        }
        meta.append(e.hint)
        if let existing = match.existing { meta.append("já está no board · \(existing.list?.displayName ?? "")") }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(match.existing?.name ?? e.name).font(.must.archivo(big ? 30 : 19, .semibold)).tracking(big ? -0.6 : 0)
                    .foregroundStyle(Color.must.ink).lineLimit(2)
                if let local = e.nameLocal ?? match.existing?.nameLocal {
                    Text(local).font(.must.kanji(big ? 17 : 13, bold: false)).foregroundStyle(Color.must.secondary)
                }
            }
            Text(meta.joined(separator: " · ")).font(.must.archivo(big ? 15 : 13)).foregroundStyle(Color.must.secondary)
        }
    }

    private func listPills(for match: MatchedPlace) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(lists) { list in
                let chosen = model.listChoice[match.id] == list.id
                Button { model.listChoice[match.id] = list.id } label: {
                    Pill(chosen ? "\(list.displayName)\(match.extracted.sub.map { " · \($0)" } ?? "")" : list.name.capitalized,
                         style: chosen ? .green : .default)
                }
                .buttonStyle(MustPressStyle())
            }
        }
        .disabled(match.existing != nil)
    }

    // MARK: Ação principal

    private var targetListName: String? {
        let id = model.matches.first.flatMap { model.listChoice[$0.id] } ?? preferredListId
        return lists.first { $0.id == id }?.displayName
    }

    @ViewBuilder private var mainButton: some View {
        let count = model.included.count
        Group {
            if model.phase == .done, let first = model.matches.first, first.existing != nil, count == 0 {
                PrimaryButton("Já está no board · fechar", style: .dark) { dismiss() }
            } else if model.phase == .done {
                PrimaryButton(count > 1 ? "Adicionar \(count) lugares" : "Adicionar ao \(targetListName ?? "board")",
                              icon: .ok, iconTrailing: true) { save() }
                    .disabled(count == 0)
                    .opacity(count == 0 ? 0.5 : 1)
            } else {
                PrimaryButton("Ler o link", icon: .avancar, iconTrailing: true, style: .dark) { Task { await run() } }
                    .disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty || model.phase == .reading)
                    .opacity(model.input.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .center).ignoresSafeArea()
        }
    }

    private func toggle(_ match: MatchedPlace) {
        if model.included.contains(match.id) { model.included.remove(match.id) } else { model.included.insert(match.id) }
    }

    private func run() async {
        fieldFocused = false
        let settings = settingsList.first
        model.extractorOptions = AIPlaceExtractor.Options(onDevice: settings?.onDeviceAI ?? true, cloudBoost: settings?.cloudBoost ?? false, knownAreas: [])
        await model.run(places: places, lists: lists, city: city, region: region, knownAreas: knownAreas)
        if let preferredListId {
            for m in model.matches where m.existing == nil { model.listChoice[m.id] = preferredListId }
        }
    }

    private func save() {
        let today = BoardDates(timeZone: region.timeZone).dayString(AppClock.now)
        let source = model.resolved?.source ?? .text
        let cityId = city?.id ?? trips.first?.cities.first?.id ?? region.rawValue
        for match in model.matches where model.included.contains(match.id) && match.existing == nil {
            let e = match.extracted
            let list = lists.first { $0.id == model.listChoice[match.id] } ?? lists.first
            let place = Place(id: "m-\(UUID().uuidString.prefix(8).lowercased())", name: e.name, cityId: cityId, lat: match.lat, lng: match.lng)
            place.nameLocal = e.nameLocal
            place.area = e.area
            place.approx = match.approx
            place.list = list
            if let sub = e.sub, list?.subs.contains(sub) == true { place.sub = sub }
            place.source = Source(kind: source.sourceKind, url: model.caption?.url?.absoluteString ?? model.resolved?.url?.absoluteString,
                                  savedAt: today, caption: model.caption?.text.isEmpty == false ? model.caption?.text : nil,
                                  author: model.caption?.title)
            place.notes = e.hint == "link do Maps" ? "" : "Achado \(e.hint)."
            context.insert(place)
            // (d) Places Text Search perto da cidade: placeId, coordenada exata e horário, em segundo plano.
            services.sync.resolveNew(place, candidate: nil, region: region, context: context)
            Log.data.info("link → \(place.id, privacy: .public) \(source.rawValue, privacy: .public)")
        }
        try? context.save()
        dismiss()
    }
}

