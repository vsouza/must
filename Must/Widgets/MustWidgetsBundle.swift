import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MustWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        NearbyWidget()
        PlanTomorrowWidget()
        NextStopLiveActivity()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Lê o retrato que o app escreveu no App Group; atualiza a cada 30 min.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : (WidgetSnapshot.load() ?? .sample)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

private struct OpenAppHint: View {
    var body: some View {
        Text("Abra o Must uma vez pra aparecer aqui.")
            .font(SharedStyle.text(12))
            .foregroundStyle(SharedStyle.secondary)
    }
}

// MARK: - Hoje (médio)

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.viniso.must.today", provider: SnapshotProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
                .containerBackground(.white, for: .widget)
                .widgetURL(URL(string: "must://hoje"))
        }
        .configurationDisplayName("Hoje")
        .description("Gasto do dia, paradas feitas e a próxima.")
        .supportedFamilies([.systemMedium])
    }
}

struct TodayWidgetView: View {
    var snapshot: WidgetSnapshot?

    var body: some View {
        if let s = snapshot {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gasto hoje").font(SharedStyle.text(13)).foregroundStyle(SharedStyle.secondary)
                    Text(s.spentText).font(SharedStyle.mono(28, .semibold)).foregroundStyle(SharedStyle.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    let progress = Text(s.hasDay ? "\(s.doneCount) de \(s.totalCount) feitos" : "sem dia montado").bold()
                    Text("de \(s.budgetText) · \(progress)")
                        .font(SharedStyle.text(12)).foregroundStyle(SharedStyle.secondary)
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        ForEach(Array(s.seals.prefix(6).enumerated()), id: \.offset) { i, seal in
                            ZStack {
                                switch seal {
                                case .done:
                                    Circle().fill(SharedStyle.green)
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(SharedStyle.greenText)
                                case .next:
                                    Circle().fill(SharedStyle.ink)
                                    Text("\(i + 1)").font(SharedStyle.text(10, .bold)).foregroundStyle(.white)
                                case .future:
                                    Circle().fill(SharedStyle.surface)
                                    Text("\(i + 1)").font(SharedStyle.text(10, .bold)).foregroundStyle(SharedStyle.secondary)
                                }
                            }
                            .frame(width: 22, height: 22)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Próxima").font(SharedStyle.text(12)).foregroundStyle(SharedStyle.blueText)
                    Spacer(minLength: 0)
                    Text(s.nextName ?? "Montar o dia").font(SharedStyle.text(15, .semibold)).foregroundStyle(SharedStyle.ink).lineLimit(2)
                    Text([s.nextTime, s.nextMinutes.map { "\($0) min" }].compactMap { $0 }.joined(separator: " · "))
                        .font(SharedStyle.mono(12, .semibold)).foregroundStyle(SharedStyle.blueText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(SharedStyle.blueGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            OpenAppHint()
        }
    }
}

// MARK: - Perto de você (pequeno)

struct NearbyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.viniso.must.nearby", provider: SnapshotProvider()) { entry in
            NearbyWidgetView(snapshot: entry.snapshot)
                .containerBackground(SharedStyle.greenGradient, for: .widget)
                .widgetURL(URL(string: "must://mapa"))
        }
        .configurationDisplayName("Perto de você")
        .description("Quantos musts estão abertos perto (última posição do app).")
        .supportedFamilies([.systemSmall])
    }
}

struct NearbyWidgetView: View {
    var snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Perto de você\(snapshot?.tempNow.map { " · \($0)°" } ?? "")")
                .font(SharedStyle.text(12)).foregroundStyle(SharedStyle.greenText)
            Spacer(minLength: 0)
            Text("\(snapshot?.nearbyCount ?? 0)").font(SharedStyle.mono(44, .semibold)).foregroundStyle(SharedStyle.ink)
            Text("musts abertos").font(SharedStyle.text(14, .semibold)).foregroundStyle(SharedStyle.ink)
            Text(snapshot?.area ?? "—").font(SharedStyle.text(12)).foregroundStyle(SharedStyle.greenText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Montar o dia (pequeno, escuro)

struct PlanTomorrowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.viniso.must.plan", provider: SnapshotProvider()) { entry in
            PlanTomorrowView(snapshot: entry.snapshot)
                .containerBackground(SharedStyle.ink, for: .widget)
                .widgetURL(URL(string: "must://montar?date=\(entry.snapshot?.tomorrowDate ?? "")"))
        }
        .configurationDisplayName("Montar o dia")
        .description("Previsão de amanhã e um atalho pra montar o roteiro.")
        .supportedFamilies([.systemSmall])
    }
}

struct PlanTomorrowView: View {
    var snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Amanhã\(snapshot?.tomorrowWeather.map { " · \($0)" } ?? "")")
                .font(SharedStyle.text(12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            Spacer(minLength: 0)
            Text("Montar o dia").font(SharedStyle.text(16, .semibold)).foregroundStyle(.white)
            Text(snapshot?.tomorrowLine ?? "toque pra montar").font(SharedStyle.text(11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            Text("Montar").font(SharedStyle.text(12, .semibold)).foregroundStyle(SharedStyle.greenText)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(SharedStyle.green))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Live Activity

/// v8 (prompt 23 §4): "saia às" gigante em laranja, a parada, a seguinte e o último trem. Tinta + laranja, nada mais.
struct NextStopLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextStopAttributes.self) { context in
            LockScreenStopView(state: context.state)
                .activityBackgroundTint(SharedStyle.v8Ink)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "must://hoje"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        NumberBadge(number: context.state.number, anchor: context.state.isAnchor)
                        Text(context.state.name).font(SharedStyle.text(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LeaveTime(state: context.state, size: 18)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressDetail(state: context.state)
                        AfterLine(state: context.state)
                    }
                }
            } compactLeading: {
                NumberBadge(number: context.state.number, anchor: context.state.isAnchor)
            } compactTrailing: {
                if let leave = context.state.leaveAt, leave > .now {
                    Text(leave, style: .time).font(SharedStyle.mono(13, .semibold)).foregroundStyle(SharedStyle.v8Orange)
                } else {
                    Text("agora").font(SharedStyle.mono(13, .semibold)).foregroundStyle(SharedStyle.v8Orange)
                }
            } minimal: {
                NumberBadge(number: context.state.number, anchor: context.state.isAnchor)
            }
            .widgetURL(URL(string: "must://hoje"))
        }
    }
}

private struct NumberBadge: View {
    var number: Int
    var anchor = false
    var body: some View {
        Text("\(number)").font(SharedStyle.text(12, .bold)).foregroundStyle(anchor ? SharedStyle.v8Ink : .white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(anchor ? SharedStyle.v8Orange : SharedStyle.v8Ink))
            .overlay(Circle().strokeBorder(.white.opacity(anchor ? 0 : 0.5), lineWidth: 1))
    }
}

private struct LeaveTime: View {
    var state: NextStopAttributes.ContentState
    var size: CGFloat

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let leave = state.leaveAt, leave > .now {
                Text(leave, style: .time).font(SharedStyle.mono(size, .semibold)).foregroundStyle(SharedStyle.v8Orange)
                Text("saia às").font(SharedStyle.text(12)).foregroundStyle(SharedStyle.v8Mute)
            } else {
                Text(state.arriveBy ?? state.at, style: .time).font(SharedStyle.mono(size, .semibold)).foregroundStyle(SharedStyle.v8Orange)
                Text(state.arriveBy != nil ? "chegue às" : "saia agora").font(SharedStyle.text(12)).foregroundStyle(SharedStyle.v8Mute)
            }
        }
    }
}

private struct ProgressDetail: View {
    var state: NextStopAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(SharedStyle.v8Orange).frame(width: geo.size.width * max(0.04, state.progress))
                }
            }
            .frame(height: 4)
            Text(state.detail).font(SharedStyle.mono(12)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).fixedSize()
        }
    }
}

/// "depois 15:48 Shinjuku Gyoen · último trem 00:12".
private struct AfterLine: View {
    var state: NextStopAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            if let name = state.nextName, let at = state.nextAt {
                Text("DEPOIS").font(SharedStyle.mono(10)).foregroundStyle(SharedStyle.v8Mute)
                Text(at, style: .time).font(SharedStyle.mono(12, .semibold)).foregroundStyle(.white)
                Text(name).font(SharedStyle.text(12)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let last = state.lastTrainAt {
                Text("ÚLTIMO TREM").font(SharedStyle.mono(10)).foregroundStyle(SharedStyle.v8Mute)
                Text(last, style: .time).font(SharedStyle.mono(12, .semibold)).foregroundStyle(.white)
            }
        }
        .lineLimit(1)
    }
}

struct LockScreenStopView: View {
    var state: NextStopAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PARADA \(state.number) DE \(state.total)").font(SharedStyle.mono(11)).foregroundStyle(SharedStyle.v8Mute)
                    Text(state.name).font(SharedStyle.text(20, .semibold)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer()
                LeaveTime(state: state, size: 26)
            }
            ProgressDetail(state: state)
            AfterLine(state: state)
        }
        .padding(18)
    }
}

#Preview("Hoje", as: .systemMedium) { TodayWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
#Preview("Perto", as: .systemSmall) { NearbyWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
#Preview("Montar", as: .systemSmall) { PlanTomorrowWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
