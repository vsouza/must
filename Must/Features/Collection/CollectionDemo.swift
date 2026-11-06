#if DEBUG
import Foundation
import SwiftData

/// `-debugScreen colecao` e `colecionavel-novo[:id]`: marca alguns lugares como feitos (uma vez) pra os prints. Só no
/// DEBUG; só se o board tem poucos feitos; nunca desfaz nada.
@MainActor
enum CollectionDemo {
    static func ensure(context: ModelContext, region: Region, make id: String? = nil) {
        guard let screen = DebugFlags.string("debugScreen"), screen.hasPrefix("colecao") || screen.hasPrefix("colecionavel") else { return }
        let places = ((try? context.fetch(FetchDescriptor<Place>())) ?? []).sorted { $0.id < $1.id }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = region.timeZone
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12)) ?? AppClock.now
        let doneCount = places.filter(\.isDone).count
        if doneCount < 8 {
            for (i, p) in places.filter({ !$0.isDone }).prefix(12).enumerated() {
                p.done = DoneMark(at: start.addingTimeInterval(Double(i) * 5 * 3600), spent: i == 0 ? 1250 : nil)
            }
        }
        // O do momento é o mais novo.
        if let id, let p = places.first(where: { $0.id == id }) {
            let latest = places.compactMap { $0.done?.at }.max() ?? start
            if p.done == nil || (p.done?.at ?? .distantPast) < latest { p.done = DoneMark(at: latest.addingTimeInterval(3600), spent: 1250) }
        }
        try? context.save()
    }
}
#endif
