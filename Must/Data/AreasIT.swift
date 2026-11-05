import Foundation

/// Bairros de Roma (prompt 24 §1): sigla + nome latino (Centro Storico CEN, Trastevere TRA, Monti MON…), centroide,
/// vizinhos e tempos. A tabela é curada em `Must/Data/areas/roma.json` (mesmo formato de `tokyo.json`, no bundle) e
/// carregada uma vez por processo, como as outras.
enum AreasIT {
    /// Grupo de cidade dos bairros (o `cityId` dos lugares do `seed-it.json`).
    static let cityId = "roma"

    // TODO(v8:A): `AreaCatalog.all` (Areas.swift) ainda é `jp + bh`; somar `AreasIT.all` pra o solver por bairro
    // (`AreaFocusPlan`) e a tela Bairros acharem Roma. Os ids de Roma não colidem com os de Tóquio, Kyoto e BH.
    static let all: [Area] = AreaCatalog.load(["roma"])
}
