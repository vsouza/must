import SwiftData
import SwiftUI

/// Uma votação "A ou B?": o cartaz 1080×1920 e o texto pra mandar, o voto de cada pessoa, o vencedor e o "+ dia".
/// O voto vem pelo WhatsApp; aqui o Vinicius só marca o que cada um respondeu.
struct VotacaoView: View {
    var pollId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var engine

    @Query private var polls: [PlacePoll]
    @Query private var places: [Place]
    @Query(sort: [SortDescriptor(\Companion.order), SortDescriptor(\Companion.createdAt)]) private var people: [Companion]
    @Query private var settingsList: [Settings]

    @State private var posterURL: URL?
    @State private var note: String?

    private var region: Region { store.region }
    private var poll: PlacePoll? { polls.first { $0.id == pollId } }
    private var walkMax: Double { settingsList.first?.walkMaxKm ?? 1.5 }
    private func place(_ id: String) -> Place? { places.first { $0.id == id } }
    private var voters: [String] { [Settlement.me] + people.map(\.name) }

    var body: some View {
        if let poll, let a = place(poll.placeAId), let b = place(poll.placeBId) {
            content(poll, a: a, b: b)
        } else {
            VStack(spacing: 14) {
                Text("Essa votação saiu do ar: um dos lugares saiu do board.").font(.body)
                Button("Voltar") { dismiss() }.v9Secondary()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .v9Screen(grouped: true)
        }
    }

    private func content(_ poll: PlacePoll, a: Place, b: Place) -> some View {
        let here = services.location.current
        let sideA = PollSideInfo.side(a, region: region, here: here, walkMax: walkMax)
        let sideB = PollSideInfo.side(b, region: region, here: here, walkMax: walkMax)
        let message = PollLogic.message(a: a.name, b: b.name, areaA: sideA.area.isEmpty ? nil : sideA.area, areaB: sideB.area.isEmpty ? nil : sideB.area,
                                        minutesA: PollSideInfo.minutes(a, here: here, walkMax: walkMax),
                                        minutesB: PollSideInfo.minutes(b, here: here, walkMax: walkMax))
        let poster = PollPoster(a: sideA, b: sideB, city: region.displayName, coverRGB: TripTheme.forRegion(region).coverRGB)
        let winner = poll.winner
        return List {
            sendBlock(poster: poster, message: message)
            votesBlock(poll)
            resultBlock(poll, a: a, b: b, winner: winner)
            if let note { Section { Text(note).font(.subheadline).foregroundStyle(.secondary) } }
        }
        .navigationTitle("\(a.name) × \(b.name)")
        .navigationBarTitleDisplayMode(.inline)
        .v9Screen(grouped: true)
        .scrollContentBackground(.hidden)
        .j9Footer(poll.addedToDay ? "Já está no dia" : (winner.map { "+ dia · \($0 == .a ? a.name : b.name)" } ?? "Marque o vencedor pra pôr no dia"),
                  enabled: winner != nil && !poll.addedToDay) { addToDay(poll, a: a, b: b) }
        .task(id: poster) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            posterURL = PollPosterRenderer.url(poster)
        }
    }

    // MARK: Mandar

    private func sendBlock(poster: PollPoster, message: String) -> some View {
        let width: CGFloat = 130
        let k = width / PollPosterView.size.width
        return Section("Mandar pro grupo") {
            HStack(alignment: .top, spacing: 16) {
                PollPosterView(poster: poster)
                    .scaleEffect(k, anchor: .topLeading)
                    .frame(width: width, height: PollPosterView.size.height * k, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Prévia do cartaz: \(poster.a.name) ou \(poster.b.name)")
                Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let posterURL {
                ShareLink(item: posterURL, message: Text(message)) { Label("Mandar cartaz + texto", systemImage: "square.and.arrow.up") }
            } else {
                Label("Preparando cartaz…", systemImage: "hourglass").foregroundStyle(.secondary)
            }
            ShareLink(item: message) { Label("Só o texto", systemImage: "text.bubble") }
        }
    }

    // MARK: Votos

    private func votesBlock(_ poll: PlacePoll) -> some View {
        Section {
            ForEach(voters, id: \.self) { person in
                let mine = poll.votes[person]
                HStack(spacing: 10) {
                    Text(person == Settlement.me ? "Você" : person).lineLimit(2)
                    Spacer(minLength: 8)
                    ForEach(PollSide.allCases, id: \.self) { side in
                        Button { poll.vote(person, side); try? context.save() } label: {
                            Text(side.rawValue)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(mine == side ? Color.white : Color.primary)
                                .frame(width: 48, height: 44)
                                .background(mine == side ? V9.accent : V9.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(person == Settlement.me ? "Você" : person) votou \(side.rawValue)")
                        .accessibilityAddTraits(mine == side ? .isSelected : [])
                    }
                }
            }
            if people.isEmpty {
                Button("Adicione as pessoas do grupo pra marcar o voto de cada uma") { router.push(.pessoas, on: router.tab) }
            }
        } header: { Text("O que cada um respondeu") }
    }

    // MARK: Resultado

    private func resultBlock(_ poll: PlacePoll, a: Place, b: Place, winner: PollSide?) -> some View {
        let t = PollLogic.tally(poll.votes)
        return Section("Resultado") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(t.a) × \(t.b)").font(.largeTitle.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(winner == nil ? Color.primary : V9.accent)
                Text(winner.map { "\($0.rawValue) · \($0 == .a ? a.name : b.name)" } ?? (t.a + t.b == 0 ? "sem votos ainda" : "empate"))
                    .font(.headline).lineLimit(2)
            }
            Picker("Ficou", selection: Binding(get: { poll.picked }, set: { poll.picked = $0; try? context.save() })) {
                Text("—").tag(PollSide?.none)
                ForEach(PollSide.allCases, id: \.self) { side in Text("Ficou \(side.rawValue)").tag(PollSide?.some(side)) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: + dia

    /// O mesmo encaixe do Quero… (`DayFit`): a parada de 25 min num buraco do dia de hoje, sem mover nada.
    private func addToDay(_ poll: PlacePoll, a: Place, b: Place) {
        guard let side = poll.winner else { return }
        let place = side == .a ? a : b
        let now = AppClock.now
        let today = region.calendar.startOfDay(for: now)
        let origin = services.location.current?.coordinate ?? region.defaultCenter
        let plan = engine.plan(for: today, region: region, context: context)
        guard let slot = DayFit.slot(at: place.coordinate, plan: plan, now: now, region: region, origin: origin, walkMaxKm: walkMax) else {
            note = "Não cabe hoje: o dia já está cheio ou passou das 22:30."
            return
        }
        let stop = DayFit.stop(placeId: place.id, name: place.name, note: "votação · 25 min", slot: slot,
                               area: AreaCatalog.areas(for: region).first { $0.id == place.area }?.id, at: place.coordinate)
        let updated = DayFit.inserting(stop, into: plan, date: now, region: region, walkMaxKm: walkMax)
        do { try DayEngineV8.save(updated, region: region, context: context) } catch {
            note = "Não consegui gravar o dia."
            return
        }
        poll.addedToDay = true
        try? context.save()
        router.push(.linha(date: today), on: .hoje)
    }
}
