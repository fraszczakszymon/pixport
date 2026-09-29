import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Systemowy arkusz udostępniania.
///
/// **Reguła nienegocjowalna: przekazujemy `URL`-e plików z dysku, nigdy `UIImage`.**
/// Aplikacja, która dostaje obiekt obrazu, ma prawo osadzić go w treści wiadomości
/// i przekodować po swojemu — wtedy cała praca nad formatem, rozmiarem i metadanymi
/// idzie na marne. Plik na dysku Gmail dokłada jako **załącznik**, a nie wkleja w treść,
/// i to jest jedyna dźwignia, jaką nad tym mamy.
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    var onComplete: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items = urls.map(SharedFile.init(url:))
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            // Uwaga: `completed` mówi tylko tyle, że arkusz się zamknął bez anulowania.
            // Nie wiemy, czy wiadomość faktycznie poszła ani do kogo — dlatego
            // porcjowanie wysyłki jest sterowane ręcznie przez użytkownika.
            onComplete?(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Eksport do aplikacji Pliki — a przez nią do Dysku Google, iCloud Drive czy OneDrive.
///
/// Osobna droga obok arkusza udostępniania, bo „wrzuć na dysk" przez arkusz to trzy
/// dodatkowe tapnięcia, a jest to jeden z dwóch głównych celów tej aplikacji.
struct DocumentExporter: UIViewControllerRepresentable {
    let urls: [URL]
    var onComplete: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: ((Bool) -> Void)?
        init(onComplete: ((Bool) -> Void)?) { self.onComplete = onComplete }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete?(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete?(false)
        }
    }
}

/// Plik przekazywany do arkusza z **jawnie zadeklarowanym typem zawartości**.
///
/// Goły `URL` zostawia odbiorcy domyślanie się, czym jest zawartość. Aplikacje rozgałęziają
/// się na tej podstawie: systemowe Zdjęcia podają elementy zadeklarowane jako obrazy
/// i odbiorca wgrywa je pojedynczo, a „plik" bez typu bywa traktowany inną ścieżką —
/// u jednego z użytkowników Dysk Google pakował tak przekazane zdjęcia w archiwum,
/// choć pakowanie po naszej stronie było wyłączone.
///
/// `UIActivityItemSource` to jedyne miejsce, w którym możemy powiedzieć wprost
/// „to jest JPEG", zamiast liczyć, że ktoś poprawnie odczyta rozszerzenie.
/// **Nie jest to gwarancja** — o zachowaniu decyduje aplikacja odbierająca, do której
/// nie mamy dostępu. To najsilniejszy sygnał, jaki wolno nam wysłać.
final class SharedFile: NSObject, UIActivityItemSource {
    private let url: URL
    private let typeIdentifier: String

    init(url: URL) {
        self.url = url
        self.typeIdentifier = UTType(filenameExtension: url.pathExtension)?.identifier
            ?? UTType.data.identifier
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        url
    }

    /// Zawsze adres pliku, nigdy `UIImage` — obiekt obrazu aplikacja odbierająca ma prawo
    /// wkleić w treść wiadomości i przekodować po swojemu.
    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        typeIdentifier
    }
}

/// Opakowanie listy adresów, żeby dało się jej użyć w `sheet(item:)`.
///
/// Współdzielone przez aplikację i rozszerzenie — oba prezentują arkusz w ten sam sposób.
struct URLBox: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.path).joined() }
}
