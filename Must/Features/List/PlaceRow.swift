import CoreLocation
import SwiftUI

/// Card branco com linhas de lugares (Lista, busca do hub).
struct PlaceListCard: View {
    var places: [Place]
    var region: Region
    var trip: TripInfo?
    var location: CLLocation?
    var onOpen: (Place) -> Void
    var onEdit: (Place) -> Void
    var footer: AnyView?

    init(places: [Place], region: Region, trip: TripInfo?, location: CLLocation?,
         onOpen: @escaping (Place) -> Void, onEdit: @escaping (Place) -> Void, footer: AnyView? = nil) {
        self.places = places
        self.region = region
        self.trip = trip
        self.location = location
        self.onOpen = onOpen
        self.onEdit = onEdit
        self.footer = footer
    }

    var body: some View {
        let now = AppClock.now
        let cityId = trip?.city(on: now, calendar: region.calendar)?.id
        VStack(spacing: 0) {
            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                if index > 0 { RowDivider() }
                PlaceRow(place: place, region: region, trip: trip, currentCityId: cityId, location: location, now: now)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen(place) }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onEdit(place)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Editar") { onEdit(place) }
            }
            if let footer {
                if !places.isEmpty { RowDivider() }
                footer
            }
        }
        .padding(.horizontal, 20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.must.line))
    }
}

/// Uma linha: nome + nome local, estado (reserva/aberto/fecha/fila/outra cidade), preço.
struct PlaceRow: View {
    @Environment(Services.self) private var services: Services?

    var place: Place
    var region: Region
    var trip: TripInfo?
    var currentCityId: String?
    var location: CLLocation?
    var now: Date

    private static let reservationGreen = Color(hex: 0x0B7A3E)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if place.isDone { KanjiSeal(done: true, size: 26, look: .soft) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(place.name).mustPlace().lineLimit(1)
                    if let local = place.nameLocal, !local.isEmpty {
                        Text(local).font(.must.kanji(12, bold: false)).foregroundStyle(Color.must.secondary).lineLimit(1)
                    }
                }
                metaLine
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let price = place.price, !place.isDone {
                    Text(region.money(price)).font(.must.mono(14)).foregroundStyle(Color.must.ink)
                }
                if let label = place.priceLabel {
                    Text(label).font(.must.mono(13)).foregroundStyle(Color.must.secondary)
                }
            }
        }
        .padding(.vertical, 16)
        .opacity(place.isDone ? 0.5 : 1)
    }

    @ViewBuilder private var metaLine: some View {
        let parts = metaParts
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if case .open = state, !place.isDone, !isOtherCity, !hasReservationToday {
                Circle().fill(Color.must.green).frame(width: 8, height: 8).padding(.trailing, 5)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            let lead = Text(parts.lead).foregroundStyle(parts.leadColor).fontWeight(parts.leadBold ? .semibold : .regular)
            let rest = Text(parts.rest.isEmpty ? "" : (parts.lead.isEmpty ? "" : " · ") + parts.rest.joined(separator: " · "))
                .foregroundStyle(Color.must.secondary)
            Text("\(lead)\(rest)")
                .font(.must.archivo(13))
                .lineLimit(2)
            if place.saveForEnd && !place.isDone {
                Tag("fica pro fim").padding(.leading, 6)
            }
        }
    }

    private var state: OpenState { place.openState(at: now, timeZone: region.timeZone) }
    private var isOtherCity: Bool { currentCityId != nil && place.cityId != currentCityId && cityName(place.cityId) != cityName(currentCityId) }
    private var hasReservationToday: Bool { place.hasReservation(on: now, calendar: region.calendar) }

    private func cityName(_ id: String?) -> String? { id.flatMap { trip?.city(id: $0)?.name } }

    private var metaParts: (lead: String, leadColor: Color, leadBold: Bool, rest: [String]) {
        var rest: [String] = []
        if let area = place.area { rest.append(area) }

        if let done = place.done {
            var r = [region.shortDay(done.at)]
            if let area = place.area { r.append(area) }
            if let spent = done.spent, spent > 0 { r.append(region.money(spent)) }
            return ("feito", Color.must.secondary, false, r)
        }

        if !isOtherCity, let d = place.distance(from: location) { rest.append(Walk.shortText(d)) }
        if let q = place.queueMinutes, q > 0 { rest.append(q >= 60 ? "fila \(q / 60)h" : "fila \(q) min") }

        if let reservation = place.reservation, reservation.at >= region.calendar.startOfDay(for: now) {
            let time = region.timeString(reservation.at)
            if hasReservationToday { return ("hoje \(time) · reserva", Self.reservationGreen, true, rest) }
            let day = region.shortDay(reservation.at)
            return ("\(day) \(time) · reserva", Color.must.ink, true, rest)
        }
        if isOtherCity {
            return ("outra cidade", Color.must.secondary, false, [cityName(place.cityId) ?? place.cityId] + rest)
        }
        // photo: "golden 15:48 · 12 min"; art: "até 30 nov · ¥1.400"; sport: "23° agora · UV 4".
        switch place.kind {
        case .photo:
            return (KindLines.photoMeta(place, region: region, now: now, location: location), Color.must.ink, false,
                    place.area.map { [$0] } ?? [])
        case .art:
            if let line = KindLines.artMeta(place, region: region, now: now) {
                let urgent = (place.extra?.art?.daysLeft(from: now, calendar: region.calendar)).map { (0...7).contains($0) } ?? false
                return (line, urgent ? MustColor.coffee.text : Color.must.ink, urgent, rest)
            }
        case .sport:
            let weather = services?.sync.weather(on: now, region: region, trip: trip)
            if let line = KindLines.sportMeta(place, weather: weather, now: now) { return (line, Color.must.ink, false, rest) }
        case .place:
            break
        }
        switch state {
        case .open(let until):
            return (until.map { "aberto até \($0)" } ?? "aberto", Color.must.ink, false, rest)
        case .closed(let day, let time):
            let opens = time.map { t in day.map { "abre \($0) \(t)" } ?? "abre \(t)" } ?? "fechado"
            return (opens, Color.must.ink, false, rest)
        case .unknown:
            return ("sem horário", Color.must.secondary, false, rest)
        }
    }
}
