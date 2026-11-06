import SwiftUI

/// Nova viagem (prompt 28 · F3/F4): 9 passos em tela cheia (`design/v8/screens/NovaViagem1…9`). Cada passo é uma pergunta,
/// todos pulam; o rascunho (`NewTripDraft`) só vira viagem no passo 9, via `TripCreating`. Offline é estado normal.
struct NewTripFlow: View {
    var startStep: Int = 1
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tripCreator) private var creator
    @Environment(Services.self) private var services
    @State private var model: NewTripModel?

    var body: some View {
        Group {
            if let model { content(model) } else { V8.paper.ignoresSafeArea() }
        }
        .onAppear {
            guard model == nil else { return }
            model = Self.makeModel(startStep: startStep)
        }
    }

    private static func makeModel(startStep: Int) -> NewTripModel {
        #if DEBUG
        if DebugFlags.string("debugScreen")?.hasPrefix("novaviagem") == true {
            let m = NewTripModel(draft: NewTripModel.sampleDraft, step: startStep)
            m.placesSource = "do texto colado"
            if startStep >= 9 { m.createState = .done("debug") }
            return m
        }
        #endif
        return NewTripModel(step: startStep)
    }

    @ViewBuilder private func content(_ model: NewTripModel) -> some View {
        if model.step >= NewTripModel.stepCount {
            NewTripReady(model: model, onOpen: { dismiss() }, onRetry: { Task { await create(model) } },
                         onBack: { model.createState = .idle; model.back() })
                .task { if model.createState == .idle { await create(model) } }
        } else {
            NewTripStepFrame(model: model, title: Self.title(model.step),
                             primaryTitle: model.step == NewTripModel.questionSteps ? "Criar viagem" : "Continuar",
                             primaryEnabled: model.step != 1 || model.hasDestination,
                             onClose: { dismiss() }, onBack: { withAnimation(.snappy) { model.back() } },
                             onNext: { advance(model) }) {
                stepView(model)
            }
        }
    }

    @ViewBuilder private func stepView(_ model: NewTripModel) -> some View {
        switch model.step {
        case 1: NewTripStep1(model: model)
        case 2: NewTripStep2(model: model)
        case 3: NewTripStep3(model: model)
        case 4: NewTripStep4(model: model)
        case 5: NewTripStep5(model: model)
        case 6: NewTripStep6(model: model)
        case 7: NewTripStep7(model: model)
        default: NewTripStep8(model: model)
        }
    }

    static func title(_ step: Int) -> String {
        switch step {
        case 1: "Pra onde?"
        case 2: "Quando?"
        case 3: "Quais cidades?"
        case 4: "Onde fica?"
        case 5: "Como vai?"
        case 6: "O que não pode faltar?"
        case 7: "Quanto gastar?"
        default: "Leve pro bolso."
        }
    }

    private func advance(_ model: NewTripModel) {
        if model.step == NewTripModel.questionSteps {
            startDownloads(model)
        }
        withAnimation(.snappy) { model.next() }
    }

    /// Mapas das cidades que têm pack: só no Wi-Fi (se ligado), nunca no Modo de Pouco Dados, nunca offline.
    private func startDownloads(_ model: NewTripModel) {
        guard model.draft.downloadOfflineMaps else { return }
        let status = services.connectivity.status
        guard status == .online else { return }
        if model.draft.wifiOnly, !services.connectivity.isWiFi { return }
        for city in model.draft.cities {
            if let pack = model.pack(for: city), !services.maps.isInstalled(pack.id) { services.maps.download(pack) }
        }
    }

    private func create(_ model: NewTripModel) async {
        await model.create(with: creator)
    }
}

#if DEBUG
extension NewTripModel {
    /// Rascunho de exemplo dos prints (`-debugScreen novaviagem1…9`): Portugal · Lisboa e Porto · 12–20 mar 2027.
    static var sampleDraft: NewTripDraft {
        var d = NewTripDraft()
        d.name = "Portugal"; d.countryCode = "PT"; d.currency = "EUR"; d.timeZoneId = "Europe/Lisbon"; d.colorHex = "#0A5C48"
        d.start = day(2027, 3, 12); d.end = day(2027, 3, 20)
        let lisbon = TimeZone(identifier: "Europe/Lisbon")!, saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
        func at(_ day: Int, _ h: Int, _ m: Int, _ z: TimeZone) -> Date {
            var c = Calendar(identifier: .gregorian); c.timeZone = z
            return c.date(from: DateComponents(year: 2027, month: 3, day: day, hour: h, minute: m)) ?? Date()
        }
        var lis = NewTripDraft.City(name: "Lisboa", latitude: 38.7223, longitude: -9.1393, nights: 5, timeZoneId: "Europe/Lisbon")
        lis.lodgingName = "Casa no Chiado"; lis.lodgingAddress = "R. Garrett 41 · Chiado"
        lis.checkIn = at(12, 15, 0, lisbon); lis.checkOut = at(17, 11, 0, lisbon); lis.lodgingFromEmail = true
        let por = NewTripDraft.City(name: "Porto", latitude: 41.1579, longitude: -8.6291, nights: 3, timeZoneId: "Europe/Lisbon")
        d.cities = [lis, por]
        d.flights = [
            .init(number: "TP 82", from: "GRU", to: "LIS", departure: at(11, 22, 5, saoPaulo), arrival: at(12, 11, 20, lisbon), isReturn: false),
            .init(number: "TP 8", from: "OPO", to: "GRU", departure: at(20, 12, 40, lisbon), arrival: at(20, 18, 15, saoPaulo), isReturn: true),
        ]
        let names: [(String, Int)] = [("Pastéis de Belém", 0), ("Time Out Market", 0), ("Miradouro da Senhora do Monte", 0), ("LX Factory", 0),
                                      ("Livraria Bertrand", 0), ("Tasca da Esquina", 0), ("Castelo de São Jorge", 0), ("Alfama", 0), ("Cervejaria Ramiro", 0),
                                      ("Livraria Lello", 1), ("Ribeira", 1), ("Casa da Música", 1)]
        d.places = names.map { .init(name: $0.0, cityId: d.cities[$0.1].id, listId: nil, latitude: nil, longitude: nil, googlePlaceId: nil, note: nil) }
        d.perDayBudget = 120; d.fxRate = 6.12
        return d
    }
}
#endif
