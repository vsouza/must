import ActivityKit
import Foundation
import SwiftUI

// Compartilhado entre o app e a extensão MustWidgets (os dois targets compilam este arquivo).

enum MustShared {
    static let appGroup = "group.dev.viniso.must"
    static let snapshotKey = "widget.snapshot"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }
}

/// Live Activity "próxima parada".
struct NextStopAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var number: Int
        var name: String
        var nameLocal: String?
        /// Hora marcada da parada.
        var at: Date
        /// "Saia às" (nil = já é pra ir).
        var leaveAt: Date?
        /// Minutos até lá (a pé/metrô).
        var minutesAway: Int?
        /// "350 m · reserva 19:00"
        var detail: String
        var done: Int
        var total: Int
        // v8 (prompt 23 §4): "saia às", a parada seguinte e o último trem. Opcionais: estados antigos continuam lendo.
        /// "Chegue às" (lugar com fila e sem reserva: abertura).
        var arriveBy: Date? = nil
        /// Parada depois desta ("depois · 15:48 Shinjuku Gyoen").
        var nextName: String? = nil
        var nextAt: Date? = nil
        /// Último trem do dia ("Hibiya Ginza → Naka-Meguro", 00:12).
        var lastTrainLine: String? = nil
        var lastTrainAt: Date? = nil
        /// A parada é âncora (reserva, ingresso, golden): selo laranja.
        var isAnchor: Bool = false

        var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    /// "sáb · 31 out"
    var dayLabel: String
}

/// O que os widgets mostram, escrito pelo app no App Group (sem GPS no widget).
struct WidgetSnapshot: Codable, Equatable {
    enum Seal: String, Codable { case done, next, future }

    var updatedAt: Date
    var hasDay: Bool
    var spentText: String
    var budgetText: String
    var doneCount: Int
    var totalCount: Int
    var seals: [Seal]
    var nextName: String?
    var nextTime: String?
    var nextMinutes: Int?
    var nearbyCount: Int
    var area: String
    var tempNow: Int?
    var tomorrowWeather: String?
    var tomorrowLine: String
    /// "2026-11-02" (deep link do "Montar o dia").
    var tomorrowDate: String

    static let sample = WidgetSnapshot(
        updatedAt: .now, hasDay: true, spentText: "¥ 7.650", budgetText: "15.000", doneCount: 3, totalCount: 5,
        seals: [.done, .done, .done, .next, .future], nextName: "Udatsu Sushi", nextTime: "19:00", nextMinutes: 4,
        nearbyCount: 6, area: "Naka-Meguro", tempNow: 12, tomorrowWeather: "13° sol", tomorrowLine: "templo cedo, ramen, café",
        tomorrowDate: "2026-11-16"
    )

    static func load() -> WidgetSnapshot? {
        guard let data = MustShared.defaults?.data(forKey: MustShared.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        MustShared.defaults?.set(data, forKey: MustShared.snapshotKey)
    }
}

/// Cores e fontes do Must pra extensão (sem depender do DesignSystem do app).
enum SharedStyle {
    static func rgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    static let ink = rgb(0x121316)
    static let secondary = rgb(0x7A7F87)
    static let surface = rgb(0xF1F2F4)
    static let green = rgb(0x22DD7E)
    static let greenText = rgb(0x0B2A18)
    static let blue = rgb(0x2B7BFF)
    static let blueText = rgb(0x0F3B8C)
    // v8: tinta, papel e laranja (a única cor: ação e "agora").
    static let v8Ink = rgb(0x121212)
    static let v8Paper = rgb(0xF2F0EA)
    static let v8Orange = rgb(0xFF4A1C)
    static let v8Mute = rgb(0xA3A39C)
    static let greenGradient = LinearGradient(colors: [rgb(0xB9F5CF), rgb(0x22DD7E)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let blueGradient = LinearGradient(colors: [rgb(0x9FD6FF), rgb(0x2B7BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func archivo(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Archivo", fixedSize: size).weight(weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Geist Mono", fixedSize: size).weight(weight).monospacedDigit() }
    static func kanji(_ size: CGFloat) -> Font { .custom("ZenKakuGothicNew-Bold", fixedSize: size) }
}
