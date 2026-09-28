// Sprawdza, czy odmiana przez liczbę działa w zbudowanej aplikacji.
//
//   swift Tools/check-plurals.swift <ścieżka do Pixport.app>
//
// Po co osobne narzędzie: to jedyna klasa błędów w napisach, której nie złapie ani
// kompilator, ani przegląd katalogu. Wszystko może wyglądać poprawnie w JSON-ie,
// a na ekranie i tak pojawi się surowy token „%#@value@" albo „1 zdjęć" — wystarczy,
// że ktoś woła String(format:) bez podania `locale` (patrz L.f) albo doda klucz
// z liczbą, zapominając o wariantach.
//
// Skrypt odtwarza dokładnie ścieżkę z L.f i sprawdza polskie kategorie liczby mnogiej,
// łącznie z pułapkami: 12 to „wiele" mimo końcówki 2, a 22 to „kilka".

import Foundation

let app = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard !app.isEmpty else {
    print("użycie: swift Tools/check-plurals.swift <ścieżka do Pixport.app>")
    exit(2)
}

func format(_ bundle: Bundle, _ key: String, _ locale: Locale, _ args: CVarArg...) -> String {
    let template = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    return String(format: template, locale: locale, arguments: args)
}

var failures: [String] = []

func expect(_ actual: String, _ expected: String, _ what: String) {
    if actual == expected {
        print("  ✓ \(what): \(actual)")
    } else {
        print("  ✗ \(what): jest „\(actual)", terminator: "\u{201D}, oczekiwano „\(expected)\u{201D}\n")
        failures.append(what)
    }
}

for (lproj, localeID, expectations) in [
    ("pl", "pl_PL", [
        (1, "1 zdjęcie"),
        (2, "2 zdjęcia"),
        (5, "5 zdjęć"),
        (12, "12 zdjęć"),   // końcówka 2, ale kategoria „wiele"
        (22, "22 zdjęcia"), // końcówka 2 i kategoria „kilka"
        (25, "25 zdjęć"),
    ]),
    ("en", "en_US", [
        (1, "1 photo"),
        (2, "2 photos"),
        (5, "5 photos"),
    ]),
] {
    guard let bundle = Bundle(path: "\(app)/\(lproj).lproj") else {
        print("✗ brak \(lproj).lproj w \(app)")
        failures.append("\(lproj).lproj")
        continue
    }
    print("=== \(lproj) ===")
    let locale = Locale(identifier: localeID)
    for (count, expected) in expectations {
        expect(format(bundle, "common.photoCount", locale, count), expected, "\(count)")
    }

    // Token zostawiony bez rozwinięcia to objaw wołania String(format:) bez `locale`.
    for key in ["result.fileCount", "batch.header", "error.offline.message"] {
        let produced = format(bundle, key, locale, 3)
        if produced.contains("%#@") {
            print("  ✗ \(key): nierozwinięty token — brakuje `locale` w String(format:)")
            failures.append(key)
        }
    }
}

if failures.isEmpty {
    print("\nOdmiana przez liczbę działa.")
} else {
    print("\nBłędy: \(failures.joined(separator: ", "))")
    exit(1)
}
