import SwiftData
import SwiftUI

/// Tile de uma lista no hub (136 pt): foto tingida ou gradiente, ícone, kanji, contagem.
struct ListTile: View {
    @Environment(Services.self) private var services: Services?
    @Environment(RegionStore.self) private var store: RegionStore?

    var list: MustList
    var height: CGFloat = 136
    /// Prévia na Nova lista: força a contagem e o subtítulo.
    var previewCount: Int?
    var previewSubtitle: String?
    var photoURL: URL?

    private var color: MustColor { list.color }
    /// Capa (`ListCover`: à mão › Google no disco › Commons), calculada fora do `body`.
    @State private var cover: CCPhoto?
    private var url: URL? { photoURL ?? cover.flatMap { URL(string: $0.largeURL ?? $0.url) } ?? list.photo?.url.flatMap(URL.init(string:)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TintedPhoto(url: url, color: color)
            VStack(alignment: .leading, spacing: 0) {
                MustIconView(list.icon, size: 18)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.55)))
                Spacer(minLength: 0)
                MonoNumber("\(previewCount ?? list.places.count)", size: height < 130 ? 26 : 28)
                Text(list.displayName).font(.must.archivo(17, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(previewSubtitle ?? subtitle).font(.must.archivo(11.5)).opacity(0.8).lineLimit(1)
                    .padding(.trailing, url != nil ? 30 : 0)
            }
            .foregroundStyle(color.text)
            .padding(14)
        }
        .overlay(alignment: .topTrailing) {
            if let kanji = list.kanji, !kanji.isEmpty {
                Text(kanji).font(.must.kanji(28)).foregroundStyle(color.text).opacity(0.3)
                    .padding(.top, 10).padding(.trailing, 14)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if url != nil { Credit(cover?.source == "Google" ? "G" : "CC", color: color.text).padding(.trailing, 8).padding(.bottom, 6) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .task(id: "\(list.places.count)|\(list.photo?.url ?? "")") { if photoURL == nil { cover = ListCover.photo(for: list) } }
    }

    private var subtitle: String {
        let done = list.places.filter(\.isDone).count
        let doneText = done == 1 ? "1 feito" : "\(done) feitos"
        let now = AppClock.now
        switch list.kind {
        case .photo:
            // "golden hoje 15:48 · 4 feitos"
            if let first = list.places.first {
                let tz = store?.region.timeZone ?? .current
                let sun = SunService.day(now, first.coordinate, timeZone: tz)
                if let g = sun.goldenPM, let region = store?.region {
                    return "golden \(now <= g.end ? "hoje" : "amanhã") \(region.timeString(g.start)) · \(doneText)"
                }
            }
        case .art:
            // "2 terminam esta semana"
            if let region = store?.region {
                let ending = list.places.filter { p in
                    (p.extra?.art?.daysLeft(from: now, calendar: region.calendar)).map { (0...7).contains($0) } ?? false
                }.count
                if ending > 0 { return "\(ending) \(ending == 1 ? "termina" : "terminam") esta semana · \(doneText)" }
            }
        case .sport:
            // "corrida 3 · jogo 2 · bom agora 23°"
            var parts: [String] = []
            let counts = Dictionary(grouping: list.places.compactMap { $0.extra?.sport?.activity }, by: { $0 })
            for a in SportActivity.allCases { if let n = counts[a]?.count { parts.append("\(a.label.lowercased()) \(n)") } }
            if let region = store?.region, let h = services?.sync.weather(on: now, region: region, trip: nil)?.hour(at: now),
               let spot = list.places.compactMap({ $0.extra?.sport }).first(where: { $0.activity != .watch }) {
                parts.append(SportScore.isGood(h, spot: spot) ? "bom agora \(Int(h.temp.rounded()))°" : "\(Int(h.temp.rounded()))° agora")
            }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        case .place, .experience:
            break
        }
        var parts = list.subs.compactMap { sub -> String? in
            let n = list.places.filter { $0.sub == sub }.count
            return n > 0 ? "\(sub) \(n)" : nil
        }
        parts.append(done == 1 ? "1 feito" : "\(done) feitos")
        return parts.joined(separator: " · ")
    }
}
