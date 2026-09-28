import Foundation

/// Dostęp do napisów z katalogu `Localizable.xcstrings`.
///
/// Klucze są jawne (`library.title`), a nie zdaniami po polsku użytymi jako klucz.
/// Powód: aplikacja żyje w dwóch językach i w dwóch targetach (aplikacja i rozszerzenie),
/// a poprawka literówki w polskim tekście nie może cicho rozwalić angielskiego tłumaczenia.
enum L {
    static func s(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    /// - Important: `locale` jest tu konieczne, nie kosmetyczne. Bez niego `String(format:)`
    ///   **nie rozwija** podstawień liczby mnogiej, które katalog napisów kompiluje do
    ///   postaci `%#@…@` — dostalibyśmy na ekranie surowy token zamiast tekstu.
    ///   Przy okazji liczby dostają separator tysięcy właściwy dla języka.
    static func f(_ key: String.LocalizationValue, _ arguments: any CVarArg...) -> String {
        String(format: String(localized: key), locale: .current, arguments: arguments)
    }

    /// „1 zdjęcie" / „2 zdjęcia" / „5 zdjęć" — fraza odmieniana przez liczbę.
    ///
    /// Wydzielona, bo powtarza się w sześciu miejscach, a polski ma cztery kategorie
    /// liczby mnogiej. Zdania, w których tylko rzeczownik się odmienia, składają ją
    /// z niezmiennym nośnikiem („Zapisano %@ w bibliotece"). Tam, gdzie odmienia się też
    /// czasownik, cały komunikat ma własne warianty — składanie by tego nie udźwignęło.
    static func photos(_ count: Int) -> String {
        f("common.photoCount", count)
    }
}
