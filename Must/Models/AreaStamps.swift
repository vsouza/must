import Foundation

/// Coleção de selos de bairro na Viagem (prompt 18 · D.18). Um selo por bairro da tabela que tem ao menos um
/// must feito. Bairro sem nenhum must feito não aparece (nada de selo "pendente"). Função pura, na ordem da tabela.
enum AreaStamps {
    static func earned(areas: [Area], places: [AreaPlace]) -> [Area] {
        let index = AreaIndex.build(areas: areas, places: places, openIds: [])
        let doneIds = Set(places.filter(\.isDone).map(\.id))
        return areas.filter { area in
            index.entry(area.id)?.placeIds.contains(where: doneIds.contains) ?? false
        }
    }
}
