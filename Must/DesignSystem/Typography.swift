import SwiftUI

extension View {
    /// Título 30/600, tracking −.02em.
    func mustTitle() -> some View {
        font(.must.title).tracking(-0.6).foregroundStyle(Color.must.ink)
    }

    /// Nome de lista 20/600.
    func mustListName() -> some View {
        font(.must.listName).tracking(-0.2)
    }

    /// Nome de lugar 17/600.
    func mustPlace() -> some View {
        font(.must.place).foregroundStyle(Color.must.ink)
    }

    /// Corpo 15.
    func mustBody() -> some View {
        font(.must.body).foregroundStyle(Color.must.ink)
    }

    /// Meta 13, secundário.
    func mustMeta() -> some View {
        font(.must.meta).foregroundStyle(Color.must.secondary)
    }

    /// Voz do usuário, legendas (v5: Instrument Serif). v8: Schibsted Grotesk.
    func mustSerif(_ size: CGFloat = 19) -> some View {
        font(.must.serif(size))
    }

    /// Martian Mono com algarismos tabulares (horas, ¥/R$, códigos).
    func mustMono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> some View {
        font(.must.mono(size, weight))
    }

    /// Micro: mono 11 caixa alta, tracking .1em, secundário.
    func mustMicro() -> some View {
        font(.must.micro).textCase(.uppercase).tracking(1.1).foregroundStyle(Color.must.secondary)
    }

    /// v5: kanji em Zen Kaku. v8: sem kanji na interface — sai em Schibsted (o texto que vier é o que aparece).
    func mustKanji(_ size: CGFloat = 17) -> some View {
        font(.must.kanji(size))
    }
}
