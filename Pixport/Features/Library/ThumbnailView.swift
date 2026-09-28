import Photos
import SwiftUI

/// Miniatura zdjęcia w siatce.
///
/// Żądanie idzie przez wspólny `PHCachingImageManager` w dokładnie takim rozmiarze,
/// w jakim komórka jest rysowana. Proszenie o pełnowymiarowy obraz i skalowanie go
/// w SwiftUI byłoby najprostszą drogą do siatki, która klatkuje i zjada pamięć.
struct ThumbnailView: View {
    /// Ledwie zaznaczone zaokrąglenie, jak w systemowych Zdjęciach — na tyle małe, że
    /// przy dwupunktowej przerwie między kafelkami czyta się jako miękkość, a nie kształt.
    /// Przyciemnienie zaznaczonego kafelka musi używać tego samego promienia, inaczej
    /// w rogach wystaje prostokątny cień.
    static let cornerRadius: CGFloat = 6

    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    let asset: PHAsset
    let side: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        // Kwadrat wymusza tło, nie obraz. Nałożenie `aspectRatio` na sam obraz nic nie
        // daje — `scaledToFill` narzuca własny rozmiar naturalny i komórki rozjeżdżają
        // się na różne wysokości. Rozmiar dyktuje siatka, przycięcie następuje na końcu.
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(Self.shape)
            // Cały kwadrat pozostaje klikalny — zaokrąglone rogi nie mają wypadać
            // z obszaru trafienia.
            .contentShape(Rectangle())
        .task(id: asset.localIdentifier) {
            image = await ThumbnailLoader.shared.image(for: asset, side: side, scale: displayScale)
        }
    }
}

/// Wspólny dostawca miniatur.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let manager = PHCachingImageManager()

    /// `scale` przychodzi ze środowiska widoku, a nie z `UIScreen.main` — ten ostatni
    /// jest wycofany i w oknach na iPadzie potrafi zwrócić skalę innego ekranu.
    func image(for asset: PHAsset, side: CGFloat, scale: CGFloat) async -> UIImage? {
        await request(
            asset,
            targetSize: CGSize(width: side * scale, height: side * scale),
            contentMode: .aspectFill,
            resizeMode: .fast
        )
    }

    /// Większy kadr na podgląd po przytrzymaniu.
    ///
    /// `aspectFit` zamiast `aspectFill`, bo podgląd pokazuje całe zdjęcie, a nie wycinek,
    /// i `resizeMode` dokładny — przy tej wielkości rozmycie z trybu szybkiego byłoby widoczne.
    func preview(for asset: PHAsset, maxSide: CGFloat, scale: CGFloat) async -> UIImage? {
        await request(
            asset,
            targetSize: CGSize(width: maxSide * scale, height: maxSide * scale),
            contentMode: .aspectFit,
            resizeMode: .exact
        )
    }

    private func request(
        _ asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        resizeMode: PHImageRequestOptionsResizeMode
    ) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = resizeMode
        // Miniatury są w telefonie nawet dla zdjęć trzymanych w iCloud, więc siatka
        // przewija się bez sieci. Pobieranie po sieci zdarza się dopiero przy
        // faktycznym przetwarzaniu, gdzie jest widoczne i opisane.
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            let box = SingleImageResume(continuation)
            manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                // `opportunistic` woła handler dwa razy: najpierw wersją rozmytą,
                // potem ostrą. Czekamy na ostrą, chyba że to już koniec.
                if !isDegraded || info?[PHImageResultIsInCloudKey] as? Bool == true {
                    box.resume(with: image)
                }
            }
        }
    }
}

/// Powiększony podgląd pokazywany po przytrzymaniu kafelka.
///
/// Rozmiar bierze się z proporcji zdjęcia, więc panorama nie wyjdzie kwadratem,
/// a portret nie zostanie przycięty. `contextMenu` dopasowuje okienko do zawartości,
/// dlatego widok musi znać swoje wymiary od razu — zanim obrazek się wczyta.
struct PhotoPreview: View {
    let asset: PHAsset

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private static let maxSide: CGFloat = 320

    private var size: CGSize {
        let width = CGFloat(asset.pixelWidth)
        let height = CGFloat(asset.pixelHeight)
        guard width > 0, height > 0 else {
            return CGSize(width: Self.maxSide, height: Self.maxSide)
        }
        return width >= height
            ? CGSize(width: Self.maxSide, height: Self.maxSide * height / width)
            : CGSize(width: Self.maxSide * width / height, height: Self.maxSide)
    }

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: asset.localIdentifier) {
            image = await ThumbnailLoader.shared.preview(
                for: asset,
                maxSide: Self.maxSide,
                scale: displayScale
            )
        }
    }
}

private final class SingleImageResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?

    init(_ continuation: CheckedContinuation<UIImage?, Never>) {
        self.continuation = continuation
    }

    func resume(with image: UIImage?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: image)
    }
}
