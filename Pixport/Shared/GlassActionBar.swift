import SwiftUI

/// Pas akcji u dołu ekranu: kapsuła z podsumowaniem po lewej, akcja po prawej.
///
/// Wspólny dla galerii i ustawień, żeby oba kroki wyglądały jak jedna aplikacja,
/// a nie jak dwie. Dwie osobne pływające kapsuły w stylu iOS 26, nie jeden pas przez
/// całą szerokość — zawartość przewija się pod nimi, bo szkło jest półprzezroczyste.
///
/// **Wysokość jest stała** (`GlassBar.height`). To nie kosmetyka: gdy pas zmieniał
/// wysokość wraz ze stanem, obszar przewijania drgał dokładnie w chwili tapnięcia
/// zdjęcia z dolnego rzędu i przycisk zasłaniał resztę tego rzędu.
struct GlassActionBar<Summary: View, Action: View>: View {
    @ViewBuilder var summary: () -> Summary
    @ViewBuilder var action: () -> Action

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 12) {
                summary()
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    // Przy czterocyfrowej liczbie zdjęć podsumowanie robi się długie,
                    // a kapsuła nie ma prawa wypchnąć przycisku poza ekran.
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .glassEffect(.regular, in: .capsule)

                Spacer(minLength: 0)

                action()
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: GlassBar.height)
    }
}

enum GlassBar {
    /// Miejsce rezerwowane u dołu ekranu, niezależnie od tego, czy kapsuły są widoczne.
    static let height: CGFloat = 72
}

/// Etykieta akcji: tekst ze strzałką, wspólna dla „Dalej" i „Przetwórz".
struct GlassActionLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "arrow.right")
        }
        .font(.headline)
    }
}
