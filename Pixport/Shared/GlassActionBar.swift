import SwiftUI

/// Pas akcji u dołu ekranu: kapsuła z podsumowaniem po lewej, akcja po prawej.
///
/// Wspólny dla galerii i ustawień, żeby oba kroki wyglądały jak jedna aplikacja,
/// a nie jak dwie. Dwie osobne kapsuły w stylu iOS 26, nie jeden pas przez całą szerokość.
///
/// **Wysokość jest stała** (`GlassBar.height`). To nie kosmetyka: gdy pas zmieniał
/// wysokość wraz ze stanem, obszar przewijania drgał dokładnie w chwili tapnięcia
/// zdjęcia z dolnego rzędu i przycisk zasłaniał resztę tego rzędu.
struct GlassActionBar<Summary: View, Action: View>: View {

    /// Co jest pod kapsułami.
    enum Backdrop {
        /// Nic — kapsuły pływają, zawartość prześwituje pod nimi.
        /// Dobre nad siatką zdjęć: przewijające się kadry pod szkłem wyglądają żywo.
        case floating

        /// Nieprzezroczyste tło przez całą szerokość, aż do dolnej krawędzi ekranu.
        /// Konieczne nad formularzem: półprzezroczyste szkło kładło tekst na tekst
        /// i obie warstwy stawały się nieczytelne. Zdjęcia prześwitują ładnie, litery nie.
        case opaque
    }

    var backdrop: Backdrop = .floating
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
            .padding(.horizontal, GlassBar.sideMargin)
        }
        // Kapsuły przy dolnej krawędzi zarezerwowanego pasa, nie na jego środku.
        .frame(height: GlassBar.contentHeight, alignment: .bottom)
        // Oddech nad kapsułami. Bez niego zawartość kończyła się dokładnie na ich
        // krawędzi i pas wyglądał na doklejony do siatki, zamiast nad nią leżeć.
        .padding(.top, GlassBar.topMargin)
        .padding(.bottom, GlassBar.bottomMargin)
        .background {
            if backdrop == .opaque {
                Rectangle()
                    .fill(Color(uiColor: .systemGroupedBackground))
                    // Tło sięga samej krawędzi ekranu, żeby treść formularza nie
                    // wyglądała spod paska w obszarze wskaźnika ekranu głównego.
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

/// Odstępy pasa, odmierzone z systemowych Zdjęć.
enum GlassBar {
    /// Wysokość kapsuł — tyle, ile zajmuje przycisk w rozmiarze `.large`.
    static let contentHeight: CGFloat = 52

    /// Przerwa między zawartością ekranu a kapsułami.
    static let topMargin: CGFloat = 16
    /// Przesunięcie w dół względem granicy bezpiecznego obszaru — wartość UJEMNA.
    ///
    /// Granica bezpiecznego obszaru leży ok. 34 pt nad dolną krawędzią ekranu, więc pas
    /// oparty dokładnie na niej wyglądał na zawieszony wysoko: odstęp od dołu wychodził
    /// ponad trzy razy większy niż 16 pt od boków. Systemowe paski pływające w iOS 26
    /// wchodzą w ten margines i tak samo robimy tutaj, zostawiając wskaźnik ekranu
    /// głównego odsłonięty.
    static let bottomMargin: CGFloat = -16
    static let sideMargin: CGFloat = 24

    /// Miejsce rezerwowane u dołu ekranu, niezależnie od tego, czy kapsuły są widoczne.
    static var height: CGFloat { topMargin + contentHeight + bottomMargin }
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
