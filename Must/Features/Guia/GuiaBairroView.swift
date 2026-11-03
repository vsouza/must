import CoreLocation
import SwiftData
import SwiftUI

/// Guia do dia (prompt 18 · C.16, `GuiaBairro.png`): mini-mapa com o percurso (trem na cor da linha, a pé pontilhado),
/// "Guia de hoje · Shinjuku+" com o selo, as paradas na hora com a cor do tipo, e entre elas o deslocamento
/// (linha, minutos ou "a pé"). Fim com o último trem pra casa. A visão por bairro do mesmo `PlannedDay`.
struct GuiaBairroView: View {
    /// Meia-noite do dia do guia.
    var date: Date

    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var days: [PlannedDay]

    @State private var model = GuideModel()
    @State private var command: MapCameraCommand?

    private var region: Region { store.region }

    private var day: PlannedDay? {
        days.first { $0.date == date && $0.accepted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                miniMap
                VStack(alignment: .leading, spacing: 0) {
                    if model.hasDay {
                        header.padding(.top, 16)
                        timeline.padding(.top, 18)
                    } else {
                        emptyState.padding(.top, 40)
                    }
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 22)
            }
        }
        .scrollIndicators(.hidden)
        .tripWash()
        .background(Color.must.bg.ignoresSafeArea())
        .overlay(alignment: .topLeading) { backButton.padding(.leading, 16).padding(.top, 6) }
        .safeAreaInset(edge: .bottom) { if model.hasDay { bottomBar } }
        .navigationBarHidden(true)
        .onAppear {
            refresh()
            command = model.fitCommand()
        }
        .task { await clock() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in refresh() }
        .onChange(of: services.location.current.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" }) { _, _ in refresh() }
    }

    // MARK: Gatilhos

    private func refresh() {
        model.refresh(day: day, region: region, location: services.location.current)
    }

    /// Relógio: o "saia às" e o "agora" mudam a cada minuto.
    private func clock() async {
        while !Task.isCancelled {
            let seconds = 60 - Int(AppClock.now.timeIntervalSince1970) % 60
            try? await Task.sleep(for: .seconds(Double(seconds) + 0.5))
            refresh()
        }
    }

    // MARK: Topo

    private var miniMap: some View {
        MapLibreView(scene: model.scene, command: command, interactive: false)
            .frame(height: 230)
            .allowsHitTesting(false)
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.must.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.92)))
                .shadow(color: Color.must.ink.opacity(0.12), radius: 10, y: 4)
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel("Voltar")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Micro("Guia de hoje")
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(model.title)
                        .font(.must.archivo(30, .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(Color.must.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if model.plus {
                        Text("+")
                            .font(.must.archivo(30, .semibold))
                            .foregroundStyle(Color.must.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            StationStamp(model.seal, sub: model.sealSub, size: 74, surface: .paper, filled: false, rotation: -8)
        }
    }

    // MARK: Linha do tempo

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.rows) { row in
                switch row {
                case .stop(let stop): stopRow(stop)
                case .leg(_, let leg): legRow(leg)
                case .home(let label, let time): homeRow(label: label, time: time)
                }
            }
        }
    }

    private func stopRow(_ stop: GuideModel.GuideStop) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(region.timeString(stop.at))
                    .font(.must.mono(15, .bold))
                    .foregroundStyle(stop.status == .current ? Color.must.greenText : (stop.status == .done ? Color.must.secondary : Color.must.ink))
                if let seal = stop.areaSeal {
                    Text(seal)
                        .font(.must.kanji(12))
                        .foregroundStyle(Color.must.secondary)
                }
            }
            .frame(width: 58, alignment: .leading)
            stopCard(stop)
        }
    }

    private func stopCard(_ stop: GuideModel.GuideStop) -> some View {
        HStack(alignment: .center, spacing: 12) {
            PlaceThumb(placeId: stop.placeId, refs: model.photoRefs[stop.placeId] ?? [], color: stop.color, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(.must.archivo(17, .semibold))
                    .foregroundStyle(Color.must.ink)
                    .lineLimit(2)
                if !stop.detail.isEmpty {
                    Text(stop.detail)
                        .font(.must.archivo(12))
                        .foregroundStyle(Color.must.ink.opacity(0.75))
                        .lineLimit(1)
                }
                if stop.status == .current {
                    Button { router.push(.comoChegar(placeId: stop.placeId)) } label: {
                        Text(stop.legMinutes.map { "Como chegar · \($0) min" } ?? "Como chegar")
                            .font(.must.archivo(12, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.must.ink))
                    }
                    .buttonStyle(MustPressStyle())
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if stop.status == .done {
                Text("済")
                    .font(.must.kanji(12))
                    .foregroundStyle(Color.must.greenText)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.must.green))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(cardFill(stop)))
        .opacity(stop.status == .done ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }

    /// Cor do cartão: a do tipo a 50% · atual em verde · golden em dourado · noite em cinza.
    private func cardFill(_ stop: GuideModel.GuideStop) -> Color {
        if stop.status == .current { return Color.must.green }
        if stop.isGolden { return MustColor.shop.light }
        if stop.isNight { return Color(hex: 0xEEF0F3) }
        return stop.color.light.opacity(0.5)
    }

    /// Deslocamento: chip da linha (código e cor oficial) com os minutos; a pé, a pé N min.
    private func legRow(_ leg: GuideModel.GuideLeg) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(leg.walk ? Color.must.secondary.opacity(0.5) : Color(hex: leg.line?.rgb ?? 0x7A7F87))
                .frame(width: 4, height: 28)
            if let line = leg.line {
                LineChip(line)
                Text("\(leg.minutes) min")
                    .font(.must.mono(13))
                    .foregroundStyle(Color.must.secondary)
            } else if leg.walk {
                Text("a pé \(leg.minutes) min")
                    .font(.must.archivo(13))
                    .foregroundStyle(Color.must.secondary)
            } else {
                Text("metrô · \(leg.minutes) min")
                    .font(.must.archivo(13))
                    .foregroundStyle(Color.must.secondary)
            }
        }
        .padding(.leading, 70)
    }

    /// Último trem pra casa (tabela `LastTrains`): a linha, a estação e o horário.
    private func homeRow(label: String, time: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.must.ink)
            Text("\(label) · \(time)")
                .font(.must.archivo(13, .semibold))
                .foregroundStyle(Color.must.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.must.surface))
        .padding(.leading, 70)
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Micro("Guia de hoje")
            Text("Sem dia montado")
                .font(.must.archivo(30, .semibold))
                .foregroundStyle(Color.must.ink)
            Button { router.push(.montar(date: date)) } label: {
                Text("Montar o dia")
                    .font(.must.archivo(15, .semibold))
                    .foregroundStyle(Color.must.greenText)
                    .padding(.horizontal, 22)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.must.green))
            }
            .buttonStyle(MustPressStyle())
        }
    }

    // MARK: Base

    /// Trocar (refaz o dia) e "Ir pro <próximo> · saia HH:MM" (Como chegar da parada atual).
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { router.push(.montar(date: date)) } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.must.ink)
                    .frame(width: 52, height: 52)
                    .background(Circle().strokeBorder(Color.must.line, lineWidth: 1.5))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Trocar")
            if let current = model.current, let label = model.goLabel(region: region) {
                Button { router.push(.comoChegar(placeId: current.placeId)) } label: {
                    Text(label)
                        .font(.must.archivo(15, .semibold))
                        .foregroundStyle(Color.must.greenText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Capsule().fill(Color.must.green))
                }
                .buttonStyle(MustPressStyle())
            } else {
                Text("Dia feito 済")
                    .font(.must.archivo(15, .semibold))
                    .foregroundStyle(Color.must.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(Color.must.surface))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 96)
        .background(.white.opacity(0.94))
    }
}
