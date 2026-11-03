import CoreLocation
import Foundation

// Avisos locais do guia (prompt 18 · C.17). Função pura: dia aceito → avisos com hora, texto e id.
// Sem GPS em segundo plano: a distância é a estimativa do solver a partir da parada anterior (ou da origem).

/// Parada do dia como o aviso precisa dela (valores, sem SwiftData).
struct GuideStop: Sendable {
    var placeId: String
    var name: String
    var lat: Double
    var lng: Double
    /// Início da parada (hora marcada).
    var start: Date
    /// Início + duração padrão do papel do lugar.
    var end: Date
    /// Lista do tipo photo (golden).
    var isPhoto: Bool
    var isDone: Bool
    var hours: PlaceHours?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// Dia aceito de hoje, pronto pra planejar os avisos.
struct GuideDay: Sendable {
    /// Meia-noite do dia, no fuso da região.
    var date: Date
    /// Hora de começar o dia (Ajustes › Começar o dia): abertura só conta depois dela.
    var dayStart: Date
    var timeZone: TimeZone
    /// De onde se sai (posição de agora se estiver na cidade; senão, o centro).
    var origin: CLLocationCoordinate2D
    /// Andar máximo a pé já com o nível do dia (`DaySolver.effectiveWalkMax`).
    var walkMaxKm: Double
    /// Paradas na ordem do roteiro.
    var stops: [GuideStop]
}

/// Um aviso local pronto pra agendar.
struct GuideNudge: Sendable, Hashable, Identifiable {
    enum Kind: Int, Sendable, Hashable {
        /// Prioridade 1: "saia em 5 min pro <parada>".
        case leave = 0
        /// Prioridade 2: "golden em 20 min, você está a N min do <lugar photo>".
        case golden = 1
        /// Prioridade 3: "<lugar> abre agora, está a N min".
        case opens = 2
    }

    /// `guide.<dia>.<n>`: prefixo próprio, pra não tocar nos lembretes de ingresso e voo.
    var id: String
    var kind: Kind
    var fireAt: Date
    var title: String
    var body: String
    var placeId: String
}

enum GuideNudges {
    static let idPrefix = "guide."
    /// No máximo um aviso a cada 45 min.
    static let minGap: TimeInterval = 45 * 60
    /// "saia em 5 min": o aviso chega 5 min antes da saída calculada (hora de chegar − deslocamento).
    static let leaveLead: TimeInterval = 5 * 60
    static let goldenLead: TimeInterval = 20 * 60
    /// Não agenda o que cai nos próximos 60 s.
    static let minLead: TimeInterval = 60

    private struct Candidate {
        var kind: GuideNudge.Kind
        var fireAt: Date
        var title: String
        var body: String
        var placeId: String
    }

    /// Avisos do dia, depois de `now`, sem dois a menos de 45 min (prioridade: saída > golden > abre agora).
    /// `taken`: horas de avisos `guide.*` que já tocaram hoje (contam pro espaçamento).
    static func plan(_ day: GuideDay, now: Date, taken: [Date] = []) -> [GuideNudge] {
        let earliest = now.addingTimeInterval(minLead)
        let tz = day.timeZone
        var candidates: [Candidate] = []
        var previous = day.origin

        for stop in day.stops {
            let minutes = DaySolver.leg(previous, stop.coordinate, walkMax: day.walkMaxKm).minutes
            defer { previous = stop.coordinate }
            let name = stop.name

            // 1. Saída: chega às `start` andando/indo `minutes`; o aviso sai 5 min antes da saída.
            if !stop.isDone {
                let fire = stop.start.addingTimeInterval(-TimeInterval(minutes * 60) - leaveLead)
                if fire >= earliest {
                    candidates.append(Candidate(kind: .leave, fireAt: whole(fire), title: "Saia em 5 min pro \(name)",
                                                body: "~\(minutes) min até lá · chega às \(clock(stop.start, tz))", placeId: stop.placeId))
                }
            }

            // 2. Golden: lista photo cuja janela de golden (manhã ou tarde) cai perto da parada.
            if stop.isPhoto, !stop.isDone {
                let sun = SunService.day(stop.start, latitude: stop.lat, longitude: stop.lng, timeZone: tz)
                for window in [sun.goldenAM, sun.goldenPM].compactMap({ $0 }) {
                    let fire = window.start.addingTimeInterval(-goldenLead)
                    let nearStop = window.start.addingTimeInterval(-3600) <= stop.end && window.end.addingTimeInterval(3600) >= stop.start
                    guard fire >= earliest, nearStop else { continue }
                    candidates.append(Candidate(kind: .golden, fireAt: whole(fire), title: "Golden em 20 min",
                                                body: "Você está a \(minutes) min do \(name)", placeId: stop.placeId))
                }
            }

            // 3. Abre agora: fechado no início do dia, abre depois dele e antes da parada.
            if !stop.isDone, let hours = stop.hours, hours.hasPeriods, hours.isOpen(at: day.dayStart, timeZone: tz) == false,
               let opening = hours.openings(on: day.date, timeZone: tz).first(where: { $0 > day.dayStart && $0 <= stop.start }),
               opening >= earliest {
                candidates.append(Candidate(kind: .opens, fireAt: whole(opening), title: "\(name) abre agora",
                                            body: "Está a \(minutes) min daqui", placeId: stop.placeId))
            }
        }

        // Por prioridade e, dentro dela, por hora: cada aviso aceito fecha 45 min pros outros.
        let ordered = candidates.sorted { $0.kind.rawValue != $1.kind.rawValue ? $0.kind.rawValue < $1.kind.rawValue : $0.fireAt < $1.fireAt }
        var chosen: [Candidate] = []
        for candidate in ordered {
            let clash = (taken + chosen.map(\.fireAt)).contains { abs($0.timeIntervalSince(candidate.fireAt)) < minGap }
            if !clash { chosen.append(candidate) }
        }

        let dayId = BoardDates(timeZone: tz).dayString(day.date)
        return chosen.sorted { $0.fireAt < $1.fireAt }.enumerated().map { index, c in
            GuideNudge(id: "\(idPrefix)\(dayId).\(index + 1)", kind: c.kind, fireAt: c.fireAt, title: c.title, body: c.body, placeId: c.placeId)
        }
    }

    /// Segundos inteiros (o trigger de calendário não guarda frações).
    private static func whole(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    /// "09:42" no fuso da região.
    static func clock(_ date: Date, _ timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

extension PlaceHours {
    /// Instantes em que o lugar abre no dia de `date` (fuso da região), em ordem.
    func openings(on date: Date, timeZone: TimeZone) -> [Date] {
        let weekday = Self.weekMinute(date, in: timeZone).day
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: date)
        return (periods ?? []).filter { $0.open.day == weekday }
            .compactMap { cal.date(byAdding: .minute, value: $0.open.hour * 60 + $0.open.minute, to: start) }
            .sorted()
    }
}
