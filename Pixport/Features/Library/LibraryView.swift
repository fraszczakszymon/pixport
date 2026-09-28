import PixportKit
import Photos
import PhotosUI
import SwiftUI

/// Ekran startowy: siatka biblioteki zdjęć.
///
/// Aplikacja otwiera się prosto tutaj — bez ekranu głównego, bez kafli, bez presetów.
/// Najkrótsza możliwa droga od uruchomienia do roboty.
struct LibraryView: View {
    @Environment(PhotoLibraryModel.self) private var library
    @State private var showsAppSettings = false

    private let spacing: CGFloat = 2

    var body: some View {
        @Bindable var library = library

        NavigationStack {
            Group {
                switch library.access {
                case .denied:
                    AccessDeniedView()
                case .undetermined:
                    ProgressView()
                case .authorized, .limited:
                    content
                }
            }
            .navigationTitle(PixportConfig.appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showsAppSettings) {
                AppSettingsView()
            }
            // Pasek jest w układzie ZAWSZE, gdy mamy dostęp do biblioteki — także przy
            // pustym zaznaczeniu. Pokazywanie go dopiero po zaznaczeniu wyglądało zwinniej,
            // ale zmieniało wysokość obszaru przewijania w najgorszym możliwym momencie:
            // tuż po tapnięciu zdjęcia z dolnego rzędu pasek wyrastał dokładnie nad nim
            // i zasłaniał resztę tego rzędu. Stała wysokość znaczy zero przeskoków.
            .safeAreaInset(edge: .bottom) {
                if library.access == .authorized || library.access == .limited {
                    SelectionBar()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if library.access == .limited {
                LimitedAccessBar()
            }

            if library.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if library.visibleAssets.isEmpty {
                EmptyLibraryView()
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let columns = 4
            let side = (proxy.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                    spacing: spacing
                ) {
                    // Puste komórki na początku, żeby DOLNY rząd był zawsze pełny.
                    //
                    // Siatka wypełnia się od góry, więc przy 4 kolumnach i liczbie zdjęć
                    // niepodzielnej przez 4 niepełny rząd wypadał na końcu — czyli tam,
                    // gdzie są najnowsze zdjęcia i gdzie widok się otwiera. Wyglądało to
                    // jak urwana rolka. Poszarzały brzeg należy się drugiemu końcowi:
                    // najstarszym zdjęciom, do których i tak trzeba przewijać.
                    ForEach(0..<leadingGaps(count: library.visibleAssets.count, columns: columns), id: \.self) { _ in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                    ForEach(library.visibleAssets, id: \.localIdentifier) { asset in
                        PhotoCell(
                            asset: asset,
                            side: side,
                            isSelected: library.selection.contains(asset.localIdentifier),
                            onToggle: { library.toggle(asset) }
                        )
                    }
                }
            }
            // Widok otwiera się na dole, przy najnowszych zdjęciach, i trzyma się tej
            // krawędzi, gdy zmieni się wysokość zawartości — na przykład gdy przybędzie
            // nowe zdjęcie.
            //
            // Role są wskazane celowo. Samo `.defaultScrollAnchor(.bottom)` obejmuje
            // również `.alignment`, a wtedy biblioteka z kilkoma zdjęciami przykleja się
            // do dolnej krawędzi ekranu z pustą przestrzenią nad sobą. Pozycja startowa
            // i reakcja na zmianę wysokości — tak; wyrównanie krótkiej zawartości — nie.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
        }
    }

    /// Ile pustych komórek dołożyć na początku, żeby ostatni rząd wyszedł pełny.
    private func leadingGaps(count: Int, columns: Int) -> Int {
        let remainder = count % columns
        return remainder == 0 ? 0 : columns - remainder
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showsAppSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(L.s("library.appSettings"))
        }
        // Bez "zaznacz wszystkie": przy rolce liczonej w tysiącach zdjęć ten przycisk
        // nie jest wygodą, tylko pułapką — jedno tapnięcie wybiera kilkanaście gigabajtów.
        ToolbarItem(placement: .topBarTrailing) {
            if !library.selection.isEmpty {
                Button(L.s("library.deselect")) { library.clearSelection() }
            }
        }
    }
}

private struct PhotoCell: View {
    let asset: PHAsset
    let side: CGFloat
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        ThumbnailView(asset: asset, side: side)
            // Zaznaczenie przyciemnia zdjęcie, zamiast obrysowywać je ramką. Ramka
            // zjadała kilka procent kadru i przy gęstej siatce robiła z ekranu kratę;
            // przyciemnienie czyta się od razu, a zdjęcie zostaje całe.
            .overlay {
                ThumbnailView.shape
                    .fill(.black)
                    .opacity(isSelected ? 0.34 : 0)
            }
            // Ptaszek NAD przyciemnieniem, inaczej zgasłby razem ze zdjęciem.
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                    .padding(5)
                    .shadow(radius: 2)
            }
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .onTapGesture(perform: onToggle)
            // Przytrzymanie daje powiększony podgląd, tak jak w systemowych Zdjęciach —
            // przy kafelku wielkości kciuka nie da się inaczej rozpoznać, które ujęcie
            // jest tym ostrym. Pozycja w menu jest jedna, bo w tym miejscu istnieje
            // dokładnie jedna sensowna czynność.
            .contextMenu {
                Button(action: onToggle) {
                    Label(
                        isSelected ? L.s("library.preview.deselect") : L.s("library.preview.select"),
                        systemImage: isSelected ? "checkmark.circle" : "circle"
                    )
                }
            } preview: {
                PhotoPreview(asset: asset)
            }
    }
}

/// Pas zaznaczenia u dołu galerii.
///
/// Przy pustym zaznaczeniu kapsuł nie ma, ale zarezerwowana wysokość zostaje —
/// to ona, a nie widoczność kapsuł, chroni dolny rząd zdjęć przed zasłonięciem.
///
/// Kapsuły miały kiedyś zwijać się podczas przewijania do samej liczby i samej strzałki,
/// jak w systemowych Zdjęciach. Wycofane po sprawdzeniu na telefonie: faza przewijania
/// zmienia się przy każdym najlżejszym przesunięciu palcem, więc kapsuły pulsowały
/// zamiast spokojnie reagować.
private struct SelectionBar: View {
    @Environment(PhotoLibraryModel.self) private var library

    private var count: Int { library.selection.count }

    var body: some View {
        Group {
            if count > 0 {
                GlassActionBar {
                    Text(
                        L.f(
                            "library.selection.summary",
                            count,
                            ByteFormatting.string(library.selectionByteCount)
                        )
                    )
                } action: {
                    NavigationLink {
                        SettingsView(photos: library.selectedPhotos())
                    } label: {
                        GlassActionLabel(title: L.s("library.next"))
                    }
                }
            } else {
                Color.clear.frame(height: GlassBar.height)
            }
        }
        .animation(.snappy(duration: 0.25), value: count)
    }
}

private struct LimitedAccessBar: View {
    var body: some View {
        HStack {
            Image(systemName: "photo.badge.exclamationmark")
            Text(L.s("library.limited.message"))
                .font(.footnote)
            Spacer()
            Button(L.s("library.limited.action")) {
                PhotoAccessPresenter.presentLimitedPicker()
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}

private struct EmptyLibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label(L.s("library.empty.title"), systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(L.s("library.empty.message"))
        }
    }
}

private struct AccessDeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label(L.s("library.denied.title"), systemImage: "lock")
        } description: {
            Text(L.s("library.denied.message"))
        } actions: {
            Button(L.s("library.denied.action")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Otwiera systemowy edytor zaznaczenia w trybie ograniczonego dostępu.
enum PhotoAccessPresenter {
    @MainActor
    static func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController
        else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }
}
