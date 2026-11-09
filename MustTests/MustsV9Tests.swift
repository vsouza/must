import Testing
@testable import Must

/// Lógica pequena que nasceu na conversão da aba Musts pro V9.
@MainActor
struct MustsV9Tests {
    @Test func boardDistanceArredondaPertoEmMetrosELongeEmKm() {
        #expect(BoardDistance.text(347) == "350 m")
        #expect(BoardDistance.text(40) == "40 m")
        #expect(BoardDistance.text(2_400).hasSuffix("km"))
        #expect(BoardDistance.text(2_400).contains("2,4"))
    }

    @Test func listWishUsaOVerboDaLista() {
        #expect(ListWish.text(listId: "eat", name: "Must eat") == "comer")
        #expect(ListWish.text(listId: "drink", name: "Must drink") == "beber")
        #expect(ListWish.text(listId: "photo", name: "Must photo") == "ver")
        #expect(ListWish.text(listId: "kissaten", name: "Kissaten") == "kissaten")
    }

    @Test func estadoDaLinhaTemRotuloEmPortugues() {
        #expect(ListRowState.now.label == "agora")
        #expect(ListRowState.opensAt("17h").label == "abre 17h")
        #expect(ListRowState.none.label.isEmpty)
    }
}
