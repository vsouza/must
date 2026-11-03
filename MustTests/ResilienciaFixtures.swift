import Foundation
import Testing
@testable import Must

/// Prompt 18 · A (travamentos): fixtures compartilhados pelos testes de cache, GPS e índice de abertos.

/// Caixa de estado pros callbacks de `withObservationTracking` (que são `@Sendable`).
final class ObservedFlag: @unchecked Sendable {
    var fired = false
}

let fixtureTokyo = TimeZone(identifier: "Asia/Tokyo")!

func fixtureAt(_ s: String) -> Date { BoardDates.parseDateTime(s)! }

/// Ter–dom 18:00–23:00 (fecha segunda).
func fixtureDinnerHours() -> PlaceHours {
    PlaceHours(weekdayText: nil, periods: [0, 2, 3, 4, 5, 6].map { day in
        .init(open: .init(day: day, hour: 18, minute: 0), close: .init(day: day, hour: 23, minute: 0))
    }, fetchedAt: nil)
}

/// Sex 20:00 → sáb 02:00.
func fixtureLateBarHours() -> PlaceHours {
    PlaceHours(weekdayText: nil, periods: [.init(open: .init(day: 5, hour: 20, minute: 0), close: .init(day: 6, hour: 2, minute: 0))], fetchedAt: nil)
}
