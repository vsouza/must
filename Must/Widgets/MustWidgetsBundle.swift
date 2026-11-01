import SwiftUI
import WidgetKit

/// Placeholder do prompt 01. Live Activity e widgets reais chegam no prompt 09.
@main
struct MustWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}

struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.viniso.must.placeholder", provider: PlaceholderProvider()) { _ in
            ZStack {
                Circle().fill(Color(red: 0x22 / 255, green: 0xDD / 255, blue: 0x7E / 255))
                Text("済")
                    .font(.custom("ZenKakuGothicNew-Bold", fixedSize: 28))
                    .foregroundStyle(Color(red: 0x0B / 255, green: 0x2A / 255, blue: 0x18 / 255))
            }
            .frame(width: 56, height: 56)
            .containerBackground(.white, for: .widget)
        }
        .configurationDisplayName("Must")
        .description("Em breve: Hoje, Perto de você e Montar o dia.")
        .supportedFamilies([.systemSmall])
    }
}
