import SwiftUI

/// Tela provisória do prompt 01: valida as fontes do bundle.
struct ContentView: View {
    var lastOpenedURL: URL?

    private let green = Color(red: 0x22 / 255, green: 0xDD / 255, blue: 0x7E / 255)
    private let greenText = Color(red: 0x0B / 255, green: 0x2A / 255, blue: 0x18 / 255)
    private let ink = Color(red: 0x12 / 255, green: 0x13 / 255, blue: 0x16 / 255)
    private let secondary = Color(red: 0x7A / 255, green: 0x7F / 255, blue: 0x87 / 255)

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(green)
                    Text("済")
                        .font(.must.kanji(34))
                        .foregroundStyle(greenText)
                }
                .frame(width: 72, height: 72)

                Text("Must")
                    .font(.must.title)
                    .tracking(-0.6)
                    .foregroundStyle(ink)

                Text("o board vira o dia")
                    .font(.must.serif)
                    .foregroundStyle(secondary)

                Text("09:30 · R$ 200 · ¥ 15.000")
                    .font(.must.mono)
                    .foregroundStyle(ink)

                fontStatus
            }
            .padding(.horizontal, 22)
        }
    }

    @ViewBuilder private var fontStatus: some View {
        let missing = MustFontFamily.missing
        Text(missing.isEmpty ? "fontes ok" : "faltando: \(missing.joined(separator: ", "))")
            .font(.must.micro)
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(missing.isEmpty ? secondary : .red)
            .padding(.top, 24)

        if let lastOpenedURL {
            Text(lastOpenedURL.absoluteString)
                .font(.must.mono)
                .foregroundStyle(secondary)
                .lineLimit(2)
        }
    }
}

#Preview {
    ContentView()
}
