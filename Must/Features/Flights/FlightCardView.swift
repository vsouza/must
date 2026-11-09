import SwiftUI

/// Card do próximo voo: rota, horários, status, assento, franquia, portão e saída pro aeroporto. Cartão do sistema
/// (sem fundo preto, sem giro); funciona no claro e no escuro.
struct FlightCardView: View {
    let flight: Flight
    let region: Region
    let now: Date

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
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(first: first, zone: fromZone)).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    if !flight.pnr.isEmpty {
                        Text("PNR \(flight.pnr)").font(.subheadline.weight(.semibold)).monospacedDigit()
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
                    Text(chip).font(.footnote.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(V9.fill, in: Capsule())
                }
            }
        }
        .v9Card(grouped: true)
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
            Text(code.isEmpty ? "?" : code).font(.largeTitle.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5)
            Text(time).font(.subheadline.weight(.semibold)).monospacedDigit()
            if let sub { Text(sub).font(.footnote).foregroundStyle(.secondary) }
            if let day { Text(day).font(.footnote).foregroundStyle(.secondary) }
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
            Text(lines.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Image(systemName: "airplane").foregroundStyle(.secondary).accessibilityHidden(true)
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
            .font(.footnote.weight(.semibold))
            .foregroundStyle(status.isAlert ? Color.red : Color.primary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((status.isAlert ? Color.red : V9.accent).opacity(0.15), in: Capsule())
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
        let zone = FlightFormat.zone(first.from, fallback: region.timeZone)
        let leave = FlightRules.leaveForAirport(departs: first.departsNow, international: FlightRules.isInternational(first))
        // "Saia às" só no dia do voo: com o voo em semanas, a hora de sair não diz nada.
        if FlightRules.leaveChipApplies(leave: leave, now: now, zone: zone) {
            out.append("saia às \(FlightFormat.time(leave, zone: zone)) pro aeroporto")
        }
        if let arrival = FlightRules.arrivalChip(last, fallback: region.timeZone) { out.append(arrival) }
        return out
    }
}

private extension FlightSegment {
    /// Chegada que vale, só se o e-mail ou a API trouxeram a hora (sem estimativa na tela).
    var landsArrivalTime: Date? { revisedArrives ?? arrives }
}
