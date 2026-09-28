import PixportKit
import SwiftUI

/// Krok drugi: wszystkie ustawienia naraz.
///
/// Świadomie bez presetów i bez chowania opcji pod „Dostosuj" — użytkownik widzi
/// komplet decyzji na jednym ekranie, a wartości domyślne to te z ostatniego użycia.
struct SettingsView: View {
    let photos: [any SourcePhoto]

    @Environment(SettingsStore.self) private var store
    @State private var estimate = EstimateModel()
    @State private var customLongEdge = ""
    /// Czy użytkownik jest w trybie własnej wartości.
    ///
    /// Musi być jawnym stanem, a nie wnioskiem z zapisanej liczby pikseli. Przy
    /// wnioskowaniu „Custom" nie miał jak się utrzymać: wybranie go zapisywało bieżącą
    /// wartość, a getter natychmiast rozpoznawał ją z powrotem jako preset i picker
    /// wracał do poprzedniej pozycji. Pole do wpisania nigdy się nie pokazywało.
    @State private var usesCustomLongEdge = false
    @FocusState private var focusedField: Field?

    /// Pola tekstowe ekranu. Jeden wspólny stan zamiast osobnego na pole, bo pas akcji
    /// musi wiedzieć, czy klawiatura jest otwarta — obojętnie przez które z nich.
    private enum Field {
        case longEdge
        case namePrefix
    }
    @State private var request: JobRequest?

    private var settings: ConversionSettings { store.settings }

    var body: some View {
        @Bindable var store = store

        Form {
            formatSection
            sizeSection
            metadataSection
            nameSection
            packagingSection
        }
        .navigationTitle(L.s("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Klawiatura numeryczna nie ma klawisza powrotu, więc bez tego przycisku
            // nie da się jej zamknąć i zasłania pół formularza.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L.s("common.done")) { focusedField = nil }
            }
        }
        // Pas akcji znika przy otwartej klawiaturze. Przycisk „Gotowe" z paska klawiatury
        // siada dokładnie w rogu, w którym stoi „Przetwórz" — dwa przyciski jeden na
        // drugim, oba klikalne. Chowanie pasa jest właściwsze niż przesuwanie go w bok:
        // przy otwartej klawiaturze i tak nie ma co przetwarzać, dopóki użytkownik pisze.
        .safeAreaInset(edge: .bottom) {
            if focusedField == nil {
                actionBar
            }
        }
        .animation(.easeInOut(duration: 0.2), value: focusedField)
        .navigationDestination(item: $request) { request in
            ProcessingScreen(request: request)
        }
        .onAppear {
            // Ustawienie zapisane wcześniej może nie trafiać w żaden próg — wtedy picker
            // pokazuje „Własna" i pole musi znać swoją wartość, zamiast świecić pustką
            // obok ustawienia, które realnie obowiązuje.
            if let pixels = settings.targetSize.pixels, !TargetSize.presetValues.contains(pixels) {
                customLongEdge = String(pixels)
                usesCustomLongEdge = true
            }
            refreshEstimate()
        }
        .onChange(of: settings) { _, _ in refreshEstimate() }
        .onDisappear { estimate.cancel() }
    }

    // MARK: - Sekcje

    private var formatSection: some View {
        @Bindable var store = store

        return Section {
            Picker(L.s("settings.format"), selection: $store.settings.format) {
                Text(L.s("settings.format.jpg")).tag(ImageFormat.jpeg)
                Text(L.s("settings.format.png")).tag(ImageFormat.png)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(L.s("settings.section.format"))
        } footer: {
            // PNG jest bezstratny, więc zdjęcie z aparatu potrafi w nim zająć kilka razy
            // więcej niż oryginalny HEIC. Bez tego ostrzeżenia użytkownik wybiera PNG
            // „bo lepszy" i dostaje paczkę cięższą od tego, co miał na wejściu.
            Text(settings.format == .png ? L.s("settings.format.png.warning") : L.s("settings.format.jpg.hint"))
        }
    }

    private var sizeSection: some View {
        @Bindable var store = store

        return Section {
            Picker(L.s("settings.longEdge"), selection: longEdgeBinding) {
                ForEach(TargetSize.presets) { preset in
                    Text(preset.label).tag(LongEdgeChoice.preset(preset.pixels))
                }
                Text(L.s("settings.longEdge.original")).tag(LongEdgeChoice.original)
                Text(L.s("settings.longEdge.custom")).tag(LongEdgeChoice.custom)
            }

            if usesCustomLongEdge {
                HStack {
                    Text(L.s("settings.longEdge.customValue"))
                    Spacer()
                    TextField("2000", text: $customLongEdge)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .focused($focusedField, equals: .longEdge)
                        .onChange(of: customLongEdge) { _, value in
                            // Filtrujemy w locie: klawiatura numeryczna nie wpuszcza liter,
                            // ale wklejenie owszem.
                            let digits = value.filter(\.isNumber)
                            if digits != value { customLongEdge = digits }
                            if let number = Int(digits), number > 0 {
                                store.settings.targetSize = .longEdge(min(number, Self.maxLongEdge))
                            }
                        }
                    Text("px").foregroundStyle(.secondary)
                }
            }

            if settings.format.supportsQuality {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L.s("settings.quality"))
                        Spacer()
                        Text("\(Int(settings.quality * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $store.settings.quality, in: 0.3...1.0, step: 0.01)
                }
            }

            Toggle(L.s("settings.budget"), isOn: $store.settings.budget.isEnabled)
            if settings.budget.isEnabled {
                Stepper(
                    L.f("settings.budget.value", settings.budget.megabytes),
                    value: $store.settings.budget.megabytes,
                    in: 1...500
                )
            }

            Toggle(L.s("settings.srgb"), isOn: $store.settings.convertToSRGB)
        } header: {
            Text(L.s("settings.section.size"))
        } footer: {
            Text(sizeFooter)
        }
    }

    /// Stopka sekcji „Rozmiar" z jawnym pierwszeństwem komunikatów.
    ///
    /// Przy włączonym limicie nie ma sensu tłumaczyć, że szacunek jest zgrubny — tryb
    /// budżetowy w ogóle się na nim nie opiera, tylko mierzy wynik naprawdę.
    private var sizeFooter: String {
        if settings.budget.isEnabled { return L.s("settings.budget.footer") }
        if estimate.estimate?.isMeasured == false { return L.s("settings.estimate.roughFooter") }
        return L.s("settings.srgb.footer")
    }

    private var metadataSection: some View {
        @Bindable var store = store

        return Section {
            Toggle(L.s("settings.metadata.location"), isOn: $store.settings.metadata.keepLocation)
            Toggle(L.s("settings.metadata.dateTime"), isOn: $store.settings.metadata.keepDateTime)
            Toggle(L.s("settings.metadata.camera"), isOn: $store.settings.metadata.keepCameraInfo)
        } header: {
            Text(L.s("settings.section.metadata"))
        } footer: {
            Text(
                settings.metadata.keepLocation
                    ? L.s("settings.metadata.footer.withLocation")
                    : L.s("settings.metadata.footer.noLocation")
            )
        }
    }

    private var nameSection: some View {
        @Bindable var store = store

        return Section {
            TextField(L.s("settings.name.placeholder"), text: $store.settings.namePrefix)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .namePrefix)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
        } header: {
            Text(L.s("settings.section.name"))
        } footer: {
            Text(namePreview).monospaced()
        }
    }

    private var packagingSection: some View {
        @Bindable var store = store

        return Section {
            Toggle(L.s("settings.zip"), isOn: $store.settings.packaging.makeZip)
            if settings.packaging.makeZip {
                Toggle(L.s("settings.zip.split"), isOn: $store.settings.packaging.splitIntoParts)
                if settings.packaging.splitIntoParts {
                    Stepper(
                        L.f("settings.zip.partSize", settings.packaging.partMegabytes),
                        value: $store.settings.packaging.partMegabytes,
                        in: 1...500
                    )
                }
            }
        } header: {
            Text(L.s("settings.section.packaging"))
        } footer: {
            // ZIP nie zmniejsza paczki ze zdjęciami — one już są skompresowane.
            // Mówimy to wprost, bo inaczej użytkownik włącza pakowanie, licząc na
            // mniejszy rozmiar, i czuje się oszukany.
            Text(L.s("settings.zip.footer"))
        }
    }

    // MARK: - Pasek akcji

    private var actionBar: some View {
        // Nieprzezroczyste tło, w odróżnieniu od galerii. Nad siatką zdjęć szkło wygląda
        // dobrze, bo pod spodem przesuwają się kadry. Nad formularzem kładło tekst na
        // tekst i obie warstwy stawały się nieczytelne.
        GlassActionBar(backdrop: .opaque) {
            summaryContent
        } action: {
            Button {
                request = JobRequest(photos: photos, settings: settings)
            } label: {
                GlassActionLabel(title: L.s("settings.process"))
            }
            .disabled(photos.isEmpty)
        }
    }

    /// „47 zdjęć · ~14 MB", a w trakcie liczenia to samo z kręciołkiem obok.
    ///
    /// **Poprzednia wartość zostaje na ekranie, dopóki nie przyjdzie nowa.** Wcześniej
    /// liczba znikała na rzecz słowa „liczę…" i wracała po chwili — przy każdym ruchu
    /// suwaka jakości kapsuła migała i zmieniała szerokość. Teraz zmienia się tylko
    /// sama liczba, a kręciołek mówi, że jest odświeżana.
    ///
    /// Tylda jest celowa: rozmiar JPEG zależy od treści zdjęcia, więc przy mieszanym
    /// zaznaczeniu potrafi się rozjechać. Informacja, że szacunek jest wyjątkowo zgrubny
    /// (bo nie było czego zmierzyć), trafia do stopki sekcji „Rozmiar" — czyli tam, gdzie
    /// stoją ustawienia, z których ta liczba wynika.
    @ViewBuilder
    private var summaryContent: some View {
        HStack(spacing: 6) {
            Text(L.photos(photos.count))

            if let value = estimate.estimate {
                Text(verbatim: "·")
                    .foregroundStyle(.secondary)
                Text(L.f("settings.estimate.value", ByteFormatting.string(value.bytes)))
            }

            if estimate.isEstimating {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - Pomocnicze

    private var namePreview: String {
        let names = FileNamer.names(for: photos, prefix: settings.namePrefix, format: settings.format)
        guard let first = names.first else { return "" }
        guard names.count > 1, let last = names.last else { return first }
        return names.count == 2 ? "\(first), \(last)" : "\(first), … , \(last)"
    }

    private enum LongEdgeChoice: Hashable {
        case preset(Int)
        case original
        case custom
    }

    /// Górna granica własnej wartości. Powyżej tego i tak nie ma zdjęć, a pole bez
    /// ograniczenia zaprasza do wpisania liczby, przy której skalowanie zabija pamięć.
    private static let maxLongEdge = 20000

    private var longEdgeBinding: Binding<LongEdgeChoice> {
        Binding(
            get: {
                if usesCustomLongEdge { return .custom }
                switch settings.targetSize {
                case .original: return .original
                case .longEdge(let value):
                    return TargetSize.presetValues.contains(value) ? .preset(value) : .custom
                }
            },
            set: { choice in
                switch choice {
                case .original:
                    usesCustomLongEdge = false
                    store.settings.targetSize = .original
                case .preset(let value):
                    usesCustomLongEdge = false
                    store.settings.targetSize = .longEdge(value)
                case .custom:
                    usesCustomLongEdge = true
                    let current = settings.targetSize.pixels ?? 2000
                    customLongEdge = String(current)
                    store.settings.targetSize = .longEdge(current)
                    focusedField = .longEdge
                }
            }
        )
    }

    private func refreshEstimate() {
        estimate.schedule(photos: photos, settings: settings)
    }
}

/// Zamówienie przetwarzania — komplet tego, co potrzebne do uruchomienia przebiegu.
struct JobRequest: Identifiable, Hashable {
    let id = UUID()
    let photos: [any SourcePhoto]
    let settings: ConversionSettings

    static func == (lhs: JobRequest, rhs: JobRequest) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
