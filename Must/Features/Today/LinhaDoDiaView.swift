import SwiftUI

/// 04 · Linha do dia (prompt 23 §2, `Dia.png`). Stub do contrato; agente C (por enquanto mostra o Hoje v5).
struct LinhaDoDiaView: View {
    var date: Date
    var body: some View { TodayView(date: date) }
}
