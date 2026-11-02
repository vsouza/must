import SwiftUI

/// Card do próximo voo (`design/screens/Voos.png`): preto, girado; rota, horários, status, assento, franquia, portão e saída.
struct FlightCardView: View {
    let flight: Flight
    let region: Region
    let now: Date

    private var amber: Color { Color(hex: 0xFFB020) }

    var body: some View {
        if let first = flight.legs.first, let last = flight.legs.last {
            card(first: first, last: last)
        }
    }

    private func card(first: FlightSegment, last: FlightSegment) -> some View {
        let fromZone = FlightFormat.zone(first.from, fallback: region.timeZone)
        let toZone = FlightFormat.zone(last.to, fallback: region.timeZone)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline(first: first, zone: fromZone))
                        .font(.must.mono(12)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                    if !flight.pnr.isEmpty {
                        Text("PNR \(flight.pnr)").font(.must.mono(12, .semibold)).foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 8)
                statusPill(first.status)
            }

            HStack(alignment: .top, spacing: 8) {
                endpoint(code: first.from, time: FlightFormat.time(first.departsNow, zone: fromZone),
                         sub: terminalLine(first), day: nil, alignment: .leading)
                Spacer(minLength: 4)
                middle(first: first, last: last)
                Spacer(minLength: 4)
                endpoint(code: last.to, time: last.landsArrivalTime.map { FlightFormat.time($0, zone: toZone) } ?? "—",
                         sub: nil, day: last.landsArrivalTime.map { FlightFormat.day($0, zone: toZone) }, alignment: .trailing)
            }

            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(chips(first: first, last: last), id: \.self) { chip in
                    Text(chip).font(.must.archivo(14)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0x121316)))
        .rotationEffect(.degrees(-1.2))
        .padding(.top, 22)
        .padding(.horizontal, 4)
    }

    private func headline(first: FlightSegment, zone: TimeZone) -> String {
        let carrier = FlightRules.carrierName(first.carrierCode)
        let number = first.number.uppercased()
        return ["\(FlightFormat.dayUpper(first.departsNow, zone: zone))", carrier, number].joined(separator: " · ")
    }

    private func terminalLine(_ segment: FlightSegment) -> String? {
        segment.terminal.map { "terminal \($0)" }
    }

    private func endpoint(code: String, time: String, sub: String?, day: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(code.isEmpty ? "?" : code).font(.must.archivo(34, .semibold)).foregroundStyle(.white)
            Text(time).font(.must.mono(13)).foregroundStyle(.white.opacity(0.75))
            if let sub { Text(sub).font(.must.mono(12)).foregroundStyle(.white.opacity(0.55)) }
            if let day { Text(day).font(.must.mono(12)).foregroundStyle(.white.opacity(0.55)) }
        }
    }

    /// Linha do meio: duração total e, com conexão, a escala.
    private func middle(first: FlightSegment, last: FlightSegment) -> some View {
        let connections = flight.legs.count - 1
        var lines: [String] = []
        if let arrives = last.revisedArrives ?? last.arrives {
            lines.append(duration(from: first.departsNow, to: arrives))
        }
        if connections > 0 {
            lines.append("\(connections) \(connections == 1 ? "conexão" : "conexões")")
            let via = flight.legs.dropLast().map(\.to).joined(separator: ", ")
            if !via.isEmpty { lines.append("via \(via)") }
        }
        return VStack(spacing: 6) {
            Text(lines.joined(separator: " · ")).font(.must.mono(12)).foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 0) {
                Circle().fill(Color.must.green).frame(width: 8, height: 8)
                Rectangle().fill(.white.opacity(0.35)).frame(height: 1)
                ForEach(0..<max(0, connections), id: \.self) { _ in
                    Circle().fill(.white).frame(width: 7, height: 7)
                    Rectangle().fill(.white.opacity(0.35)).frame(height: 1)
                }
                Circle().fill(.white).frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func duration(from start: Date, to end: Date) -> String {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        guard minutes > 0 else { return "" }
        return "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
    }

    private func statusPill(_ status: FlightStatus) -> some View {
        Text(status.label)
            .font(.must.archivo(13, .semibold))
            .foregroundStyle(status.isAlert ? Color(hex: 0x4A2E00) : Color.must.greenText)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(status.isAlert ? amber : Color.must.green))
    }

    /// Assento, franquia, portão (ou a contagem até a partida) e a saída pro aeroporto.
    private func chips(first: FlightSegment, last: FlightSegment) -> [String] {
        var out: [String] = []
        if let seat = first.seat { out.append("assento \(seat)") }
        if let checked = flight.checkedKg {
            out.append("mala \(checked) kg" + (flight.cabinKg.map { " + mão \($0) kg" } ?? ""))
        }
        if let gate = first.gate {
            out.append("portão \(gate)")
        } else {
            let days = WalletRules.daysBetween(now, first.departsNow, region: region)
            if days >= 0 { out.append(days == 0 ? "portão hoje" : "portão em \(days) \(days == 1 ? "dia" : "dias")") }
        }
        let leave = FlightRules.leaveForAirport(departs: first.departsNow, international: FlightRules.isInternational(first))
        out.append("saia às \(FlightFormat.time(leave, zone: FlightFormat.zone(first.from, fallback: region.timeZone))) pro aeroporto")
        return out
    }
}

private extension FlightSegment {
    /// Chegada que vale, só se o e-mail ou a API trouxeram a hora (sem estimativa na tela).
    var landsArrivalTime: Date? { revisedArrives ?? arrives }
}
