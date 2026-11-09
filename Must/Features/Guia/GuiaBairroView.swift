import SwiftData
import SwiftUI

/// Guia do dia (rota `.guia(date:)`, prompt 18 · C.16): abre os Bairros (V9) com o bairro do dia aceito dessa data já aberto
/// (foco do Montar, ou o bairro principal do motor do dia). O texto, os vizinhos e os Musts do bairro moram na página dele.
/// O cálculo de paradas e deslocamentos do v5 continua em `GuideModel` (avisos e testes).
struct GuiaBairroView: View {
    /// Meia-noite do dia do guia.
    var date: Date

    @Environment(RegionStore.self) private var store
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context
    @Query private var days: [PlannedDay]

    var body: some View {
        BairrosV9View(initialArea: area)
    }

    private var area: String? {
        let day = days.first { $0.date == date && $0.accepted }
        if let focus = day?.focusAreaId { return focus }
        if let main = dayEngine.plan(for: date, region: store.region, context: context)?.area { return main }
        guard let day else { return nil }
        let areas = AreaCatalog.areas(for: store.region)
        let assigner = AreaAssigner(areas: areas)
        var counts: [String: Int] = [:]
        for stop in day.orderedStops {
            guard let p = stop.place, let id = assigner.areaId(name: p.area, cityId: p.cityId, lat: p.lat, lng: p.lng) else { continue }
            counts[id, default: 0] += 1
        }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
    }
}
