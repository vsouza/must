import Foundation

/// Número digitado num campo (preço, saldo, minutos, graus) — rodada 23 · G.
/// `Double("nan")`, `Double("inf")` e 20 dígitos colados viram `Double` válido, e `Int(_:)` de um deles derruba o app
/// (o campo relê o valor a cada tecla). Tudo que vem de campo passa por aqui: só número finito e de tamanho humano.
enum NumberInput {
    /// Maior valor aceito (¥ 1 trilhão): acima disso é dedo escorregando, não preço.
    static let maxValue = 1e12
    /// Maior inteiro aceito (minutos, metros, pessoas, graus).
    static let maxInt = 1_000_000

    /// O valor, se finito e dentro de ±`maxValue`; senão nil.
    static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, abs(value) <= maxValue else { return nil }
        return value
    }

    /// `Double(texto)` seguro: aceita "12.5", recusa "nan", "inf" e números gigantes.
    static func double(_ text: String) -> Double? {
        finite(Double(text.trimmingCharacters(in: .whitespaces)))
    }

    /// Inteiro de um texto com dígitos ASCII (o resto é ignorado), limitado a `0...max`.
    static func int(_ text: String, max: Int = maxInt) -> Int? {
        let digits = String(text.filter { $0.isASCII && $0.isNumber }.prefix(12))
        guard let value = Int(digits) else { return nil }
        return Swift.min(value, max)
    }

    /// `Int(value.rounded())` sem trap: nil pra NaN, infinito ou fora de ±`maxValue`.
    static func rounded(_ value: Double?) -> Int? {
        finite(value).map { Int($0.rounded()) }
    }

    /// Texto inteiro de um valor ("24000"); vazio quando não dá.
    static func intText(_ value: Double?) -> String {
        rounded(value).map(String.init) ?? ""
    }
}
