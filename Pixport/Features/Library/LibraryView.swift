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
    /// Podczas przewijania pasek zwija się do samej liczby i ikony — tak jak w Zdjęciach.
    @State private var isScrolling = false

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
                    SelectionBar(isCompact: isScrolling)
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
            .onScrollPhaseChange { _, phase in
                isScrolling = phase.isScrolling
            }
        }
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
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                    .padding(5)
                    .shadow(radius: 2)
            }
            .overlay {
                if isSelected {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
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

/// Pływający pasek zaznaczenia u dołu.
///
/// Dwie osobne kapsuły w stylu iOS 26, nie jeden pasek przez całą szerokość: po lewej
/// podsumowanie, po prawej przejście dalej. Zawartość przewija się pod nimi, bo
/// `glassEffect` jest półprzezroczysty — stąd warto, żeby było co pokazać.
///
/// **Wysokość jest stała**, także przy pustym zaznaczeniu i przy zwinięciu. Kapsuły
/// zmieniają rozmiar w środku zarezerwowanego pasa, więc obszar przewijania nigdy nie
/// drgnie — a to był powód, dla którego dolny rząd zdjęć potrafił zniknąć pod przyciskiem
/// dokładnie w chwili, gdy użytkownik go tapnął.
private struct SelectionBar: View {
    @Environment(PhotoLibraryModel.self) private var library

    /// Przewijanie zwija kapsuły do samej liczby i samej ikony.
    let isCompact: Bool

    @Namespace private var glass

    static let height: CGFloat = 72

    private var count: Int { library.selection.count }

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 12) {
                if count > 0 {
                    summary
                    Spacer(minLength: 0)
                    next
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: Self.height)
        .animation(.snappy(duration: 0.25), value: isCompact)
        .animation(.snappy(duration: 0.25), value: count)
    }

    private var summary: some View {
        Text(
            isCompact
                ? "\(count)"
                : L.f(
                    "library.selection.summary",
                    count,
                    ByteFormatting.string(library.selectionByteCount)
                )
        )
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
        .padding(.horizontal, isCompact ? 16 : 20)
        .padding(.vertical, isCompact ? 10 : 14)
        .glassEffect(.regular, in: .capsule)
        .glassEffectID("summary", in: glass)
    }

    private var next: some View {
        NavigationLink {
            SettingsView(photos: library.selectedPhotos())
        } label: {
            if isCompact {
                Image(systemName: "arrow.right")
                    .font(.headline)
            } else {
                HStack(spacing: 6) {
                    Text(L.s("library.next"))
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
            }
        }
        .buttonStyle(.glassProminent)
        .controlSize(isCompact ? .regular : .large)
        .glassEffectID("next", in: glass)
        .accessibilityLabel(L.s("library.next"))
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
