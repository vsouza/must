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
                Text("Essa votação saiu do ar: um dos lugares saiu do board.").font(V8Font.text(16)).foregroundStyle(V8.ink)
                BigButton(title: "Voltar", style: .line) { dismiss() }.frame(width: 180)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(V8.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
        return CutPage(title: "A ou B?", corner: ["Votar", "\(a.name) × \(b.name)"], height: 200, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
                sendBlock(poster: poster, message: message)
                votesBlock(poll)
                resultBlock(poll, a: a, b: b, winner: winner)
                if let note {
                    Text(note).font(V8Font.text(14)).foregroundStyle(V8.mute).padding(.horizontal, 20).padding(.top, 14)
                }
            }
        }
        .cutFooter(poll.addedToDay ? "Já está no dia" : (winner.map { "+ dia · \($0 == .a ? a.name : b.name)" } ?? "Marque o vencedor pra pôr no dia"),
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
        return HStack(alignment: .top, spacing: 16) {
            PollPosterView(poster: poster)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: width, height: PollPosterView.size.height * k, alignment: .topLeading)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Prévia do cartaz: \(poster.a.name) ou \(poster.b.name)")
            VStack(alignment: .leading, spacing: 10) {
                Text(message).font(V8Font.text(13)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true)
                if let posterURL {
                    ShareLink(item: posterURL, message: Text(message)) { shareLabel("Mandar cartaz + texto", filled: true) }
                } else {
                    shareLabel("Preparando cartaz…", filled: true).opacity(0.5)
                }
                ShareLink(item: message) { shareLabel("Só o texto", filled: false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .overlay(alignment: .bottom) { IndexRule() }
    }

    private func shareLabel(_ title: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased()).font(V8Font.mono(11, weight: .semibold)).tracking(0.8).lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(V8.ink)
        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44)
        .background(filled ? V8.orange : Color.clear)
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
    }

    // MARK: Votos

    private func votesBlock(_ poll: PlacePoll) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel("o que cada um respondeu", size: 10, color: V8.mute).padding(.horizontal, 20).padding(.vertical, 12)
            ForEach(voters, id: \.self) { person in
                let mine = poll.votes[person]
                HStack(spacing: 10) {
                    Text(person == Settlement.me ? "Você" : person)
                        .font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                    Spacer(minLength: 8)
                    ForEach(PollSide.allCases, id: \.self) { side in
                        Button { poll.vote(person, side); try? context.save() } label: {
                            Text(side.rawValue)
                                .font(V8Font.mono(15, weight: .bold))
                                .foregroundStyle(mine == side ? V8.ink : V8.ink)
                                .frame(width: 48, height: 44)
                                .background(mine == side ? V8.orange : Color.clear)
                                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(person == Settlement.me ? "Você" : person) votou \(side.rawValue)")
                        .accessibilityAddTraits(mine == side ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(V8.rule).frame(height: 1) }
            }
            if people.isEmpty {
                Button { router.push(.pessoas, on: router.tab) } label: {
                    Text("Adicione as pessoas do grupo pra marcar o voto de cada uma →")
                        .font(V8Font.text(14)).foregroundStyle(V8.ink).underline()
                        .multilineTextAlignment(.leading).padding(.horizontal, 20).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { IndexRule() }
    }

    // MARK: Resultado

    private func resultBlock(_ poll: PlacePoll, a: Place, b: Place, winner: PollSide?) -> some View {
        let t = PollLogic.tally(poll.votes)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("\(t.a) × \(t.b)").font(V8Font.numeral(56)).tracking(-1.5).foregroundStyle(winner == nil ? V8.ink : V8.orange)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(winner.map { "\($0.rawValue) · \($0 == .a ? a.name : b.name)" } ?? (t.a + t.b == 0 ? "sem votos ainda" : "empate"))
                    .font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
            }
            HStack(spacing: 8) {
                ForEach(PollSide.allCases, id: \.self) { side in
                    Button { poll.picked = poll.picked == side ? nil : side; try? context.save() } label: {
                        CutChip(text: "Ficou \(side.rawValue)", isOn: poll.picked == side)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
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
