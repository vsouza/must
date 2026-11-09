import Testing
@testable import Must

/// Lugar V9: as ações visíveis (Ir · Encaixar hoje · Guardar · Dicas · Feito) e o estado de cada uma.
struct PlaceActionPlanTests {
    @Test func plainPlaceWithGPS() {
        let p = PlaceActionPlan.make(travelMinutes: 6, isAnchor: false, inDay: false, saveForEnd: false, isDone: false, tipsCount: 0)
        #expect(p.goTitle == "Ir · 6 min")
        #expect(p.fitTitle == "Encaixar hoje" && p.fitEnabled)
        #expect(p.saveTitle == "Guardar" && !p.saveIsOn)
        #expect(p.doneTitle == "Feito" && !p.doneIsUndo)
        #expect(p.tipsTitle == "Dicas")
    }

    @Test func withoutGPSIsJustIr() {
        #expect(PlaceActionPlan.make(travelMinutes: nil, isAnchor: false, inDay: false, saveForEnd: false, isDone: false, tipsCount: 0).goTitle == "Ir")
    }

    @Test func anchorSaysComoChegar() {
        #expect(PlaceActionPlan.make(travelMinutes: 9, isAnchor: true, inDay: true, saveForEnd: false, isDone: false, tipsCount: 0).goTitle == "Como chegar")
    }

    @Test func alreadyInDayDisablesFit() {
        let p = PlaceActionPlan.make(travelMinutes: 3, isAnchor: false, inDay: true, saveForEnd: true, isDone: true, tipsCount: 4)
        #expect(p.fitTitle == "Já está no dia" && !p.fitEnabled)
        #expect(p.saveTitle == "Guardado" && p.saveIsOn)
        #expect(p.doneTitle == "Desfazer feito" && p.doneIsUndo)
        #expect(p.tipsTitle == "4 dicas")
    }
}
