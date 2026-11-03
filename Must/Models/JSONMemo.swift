import Foundation

/// Cache do JSON já decodificado de um atributo `Data` de um `@Model` (prompt 18 · A.1).
///
/// Os campos `hoursData`, `extraData`, `ticketsData`, `citiesData`… são lidos dezenas de vezes por redesenho
/// (Início, Mapa, Lista). Sem cache, cada leitura roda o `JSONDecoder` de novo.
///
/// A invalidação não depende de quem escreveu: a cada leitura comparamos os bytes de origem com os que
/// geraram o valor guardado. Se o SwiftData trocou o `Data` por sync, merge ou importação (sem passar pelo
/// setter computado), a comparação falha e decodificamos de novo. Nada é persistido; o schema não muda.
///
/// Classe de propósito: fica como `let`/referência dentro do `@Model`, então ler o cache não escreve numa
/// propriedade observada (não dispara redesenho no meio de um `body`).
final class JSONMemo<Value> {
    private var source: Data?
    private var value: Value?
    private var isFilled = false

    init() {}

    /// Valor decodificado de `data` (ou o guardado, se `data` não mudou desde a última vez).
    func value(from data: Data?, decode: (Data) -> Value?) -> Value? {
        if isFilled, source == data { return value }
        let decoded = data.flatMap(decode)
        misses += 1
        source = data
        value = decoded
        isFilled = true
        return decoded
    }

    /// Setter do modelo: já sabe o valor e o `Data` que acabou de gravar, então não precisa decodificar.
    func store(_ value: Value?, source data: Data?) {
        source = data
        self.value = value
        isFilled = true
    }

    /// Número de decodificações feitas por este cache (só pros testes de desempenho).
    private(set) var misses = 0
}
