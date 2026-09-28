import Foundation
import PixportKit
import Photos

/// Zapis gotowych plików z powrotem do biblioteki zdjęć, do albumu „Pixport".
///
/// **iOS nie pozwala zapisać zdjęcia wyłącznie do albumu.** Każdy nowy zasób trafia do
/// biblioteki i pojawia się w „Ostatnich"; album jest dodatkową etykietą wskazującą na
/// ten sam zasób, a nie osobnym katalogiem. Własny album daje więc porządek i szybki
/// dostęp do tego, co wyprodukowała aplikacja — ale nie chowa zdjęć przed rolką.
enum PhotoSaver {

    /// Nazwa albumu nie jest tłumaczona: to nazwa własna aplikacji, a album raz założony
    /// zostaje w bibliotece na stałe. Przetłumaczenie jej oznaczałoby, że zmiana języka
    /// systemu tworzy drugi album i rozbija zbiór na dwa.
    static let albumTitle = "Pixport"

    enum Outcome: Sendable {
        case savedToAlbum(count: Int)
        /// Zdjęcia zapisane, ale bez albumu — przy ograniczonym dostępie do biblioteki
        /// nie da się albumów odczytywać ani zakładać.
        case savedToLibrary(count: Int)
    }

    enum SaveError: LocalizedError {
        case denied
        case nothingToSave
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: L.s("result.savePhotos.denied")
            case .nothingToSave: L.s("result.savePhotos.nothing")
            case .failed(let message): message
            }
        }
    }

    @discardableResult
    static func save(_ files: [ProcessedFile]) async throws -> Outcome {
        // Archiwum ZIP nie jest zdjęciem — biblioteka go nie przyjmie.
        let images = files.filter { $0.url.pathExtension.lowercased() != "zip" }
        guard !images.isEmpty else { throw SaveError.nothingToSave }

        // `.readWrite`, nie `.addOnly`: żeby wrzucić zdjęcia do własnego albumu, trzeba go
        // najpierw odnaleźć albo założyć, a jedno i drugie wymaga odczytu biblioteki.
        // W praktyce zgoda i tak już jest — ekran wyboru zdjęć prosi o nią wcześniej.
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw SaveError.denied }

        // Tryb ograniczony nie widzi albumów i nie pozwala ich tworzyć. Zamiast przerywać
        // zapis, robimy to, co się da: zdjęcia lądują w bibliotece bez albumu.
        let album = status == .authorized ? await findOrCreateAlbum() : nil

        do {
            try await PHPhotoLibrary.shared().performChanges {
                var placeholders: [PHObjectPlaceholder] = []
                for file in images {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: file.url, options: nil)
                    if let placeholder = request.placeholderForCreatedAsset {
                        placeholders.append(placeholder)
                    }
                }
                if let album, !placeholders.isEmpty,
                   let change = PHAssetCollectionChangeRequest(for: album) {
                    change.addAssets(placeholders as NSFastEnumeration)
                }
            }
        } catch {
            throw SaveError.failed(error.localizedDescription)
        }

        return album == nil ? .savedToLibrary(count: images.count) : .savedToAlbum(count: images.count)
    }

    // MARK: - Album

    private static func existingAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle = %@", albumTitle)
        return PHAssetCollection
            .fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
            .firstObject
    }

    /// Zwraca album, tworząc go przy pierwszym zapisie.
    ///
    /// - Returns: `nil`, gdy albumu nie udało się założyć. To nie jest powód, żeby nie
    ///   zapisać zdjęć — brak albumu jest niewygodą, utrata gotowej paczki byłaby stratą.
    private static func findOrCreateAlbum() async -> PHAssetCollection? {
        if let existing = existingAlbum() { return existing }

        let box = IdentifierBox()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                    withTitle: albumTitle
                )
                box.value = request.placeholderForCreatedAssetCollection.localIdentifier
            }
        } catch {
            return nil
        }

        guard let identifier = box.value else { return nil }
        return PHAssetCollection
            .fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil)
            .firstObject
    }
}

/// Przenosi identyfikator z domknięcia `performChanges` na zewnątrz.
///
/// Blok zmian jest `@Sendable` i wykonuje się na kolejce PhotoKit, więc zwykła zmienna
/// lokalna nie przejdzie kontroli współbieżności Swift 6. Zapis następuje raz, przed
/// zakończeniem `await`, a odczyt po nim — wyścigu tu nie ma.
private final class IdentifierBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String?

    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}
