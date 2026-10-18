import PhotosUI
import SwiftData
import SwiftUI

/// In a shop: photograph a label, see what the wine is, what New York shops charge, and its Vinous score.
struct ScanView: View {
    @State private var app = AppState.shared
    @State private var lookup: WineLookup? = Demo.scanLookup
    @State private var showCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var showLibrary = false
    @AppStorage("autoPrices") private var autoPrices = true

    var body: some View {
        NavigationStack {
            Group {
                if let lookup {
                    ScanResultView(lookup: lookup) { scanAgain() }
                } else {
                    start
                }
            }
            .navigationTitle("Scan")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { app.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
                if lookup != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { scanAgain() } label: { Label("Scan another", systemImage: "camera") }
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(onPick: { image in
                    showCamera = false
                    begin(with: image)
                }, onCancel: {
                    showCamera = false
                })
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let image = await item.loadImage() { begin(with: image) }
                    libraryItem = nil
                }
            }
        }
    }

    private var start: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 168, height: 168)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 8) {
                Text("Check a bottle")
                    .font(.title2.weight(.bold))
                Text("New York prices and the Vinous score.")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                Button {
                    if CameraPicker.isAvailable { showCamera = true } else { showLibrary = true }
                } label: {
                    Label("Scan a label", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button {
                    showLibrary = true
                } label: {
                    Label("Choose a photo", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)
            if !KeyStore.hasClaudeKey && !Demo.isOn {
                Button("Add your Claude key in Settings first") { app.showSettings = true }
                    .font(.footnote)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func begin(with image: UIImage) {
        let newLookup = WineLookup(photo: image)
        lookup = newLookup
        Task { await newLookup.runAll(prices: autoPrices) }
    }

    private func scanAgain() {
        lookup = nil
        if CameraPicker.isAvailable { showCamera = true }
    }
}

struct ScanResultView: View {
    let lookup: WineLookup
    var scanAgain: () -> Void

    @Environment(\.modelContext) private var context
    @State private var app = AppState.shared
    @State private var shelfPrice: Double? = Demo.shelfPrice
    @State private var saved: WineStatus?
    @State private var vinousPage: VinousPage?
    @FocusState private var priceFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch lookup.phase {
                case .reading, .failed:
                    ReadingView(lookup: lookup, tryAgain: { Task { await lookup.runAll(prices: true) } }, startOver: scanAgain)
                        .frame(minHeight: 480)
                case .read:
                    if let details = lookup.details {
                        identity(details)
                        priceCard(details)
                        vinousCard(details)
                        saveButtons
                        links(details)
                    }
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .sheet(item: $vinousPage) { page in
            if let details = lookup.details {
                VinousBrowserSheet(start: page.url, wine: details) { review in
                    lookup.vinous = .done(review)
                }
            }
        }
    }

    private func identity(_ d: WineDetails) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let photo = lookup.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                WineThumb(photo: nil, style: WineStyle(loose: d.style), width: 84)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(d.name.isEmpty ? d.producer : d.name)
                    .font(.title3.weight(.bold))
                if !d.name.isEmpty {
                    Text(d.producer).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
                Text([d.vintage.map(String.init) ?? "NV", WineStyle(loose: d.style).label].joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Self.placeLine(d))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    static func placeLine(_ d: WineDetails) -> String {
        var seen = Set<String>()
        let parts = [d.appellation, d.region, d.country, d.grapes.joined(separator: ", ")]
        return parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: " · ")
    }

    private func priceCard(_ d: WineDetails) -> some View {
        Card(title: "Price check", systemImage: "storefront") {
            HStack {
                Text("Shelf price")
                Spacer()
                TextField("$0", value: $shelfPrice, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.weight(.semibold))
                    .focused($priceFocused)
                    .frame(maxWidth: 140)
            }
            switch lookup.prices {
            case .idle:
                Button {
                    Task { await lookup.checkPrices() }
                } label: {
                    Text("Check New York prices").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            case .working:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking New York shops…").foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(.red)
                Button("Try again") { Task { await lookup.checkPrices() } }
                    .buttonStyle(.bordered)
            case .done(let report):
                if let shelfPrice, shelfPrice > 0, let verdict = report.verdict(for: shelfPrice) {
                    VerdictPill(verdict: verdict)
                }
                if let typical = report.typical {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Money.text(typical))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("typical in NYC").foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.range(report.low, report.high)).foregroundStyle(.secondary)
                    }
                    OffersList(offers: report.offers)
                } else {
                    Text("No New York shop prices found for this wine.").foregroundStyle(.secondary)
                }
                if !report.note.isEmpty {
                    Footnote(text: report.note)
                }
            }
        }
    }

    private func vinousCard(_ d: WineDetails) -> some View {
        Card(title: "Vinous", systemImage: "rosette") {
            switch lookup.vinous {
            case .idle:
                Button("Look up") { Task { await lookup.lookUpVinous() } }
                    .buttonStyle(.bordered)
            case .working:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking it up on Vinous…").foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(.red)
            case .done(let review):
                if review.found {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(review.score)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            if !review.critic.isEmpty { Text(review.critic).font(.subheadline.weight(.medium)) }
                            if !review.drinkWindow.isEmpty {
                                Text("Drink \(review.drinkWindow)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !review.isSameVintage(as: d) {
                        Label("This score is for the \(review.vintage). Vinous hasn't reviewed the \(d.vintage.map(String.init) ?? "NV") yet.",
                              systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if !review.note.isEmpty {
                        Text(review.note).font(.callout).foregroundStyle(.secondary)
                    }
                } else if !review.signedIn || !Vinous.rememberedSignIn {
                    Text("Sign in to Vinous in Settings to see scores.").foregroundStyle(.secondary)
                    Button("Open Settings") { app.showSettings = true }.buttonStyle(.bordered)
                } else {
                    Text("Vinous hasn't reviewed this wine.").foregroundStyle(.secondary)
                }
            }
            if !lookup.vinous.isWorking {
                Button {
                    let url = lookup.vinous.value.flatMap { URL(string: $0.url) } ?? Vinous.searchURL
                    vinousPage = VinousPage(url: url)
                } label: {
                    Text("Open on Vinous")
                }
                .font(.subheadline)
            }
        }
    }

    private var saveButtons: some View {
        HStack(spacing: 12) {
            saveButton(.cellar, title: "Add to Cellar", icon: "square.stack.3d.up")
            saveButton(.tasted, title: "Drinking it", icon: "wineglass")
        }
    }

    private func saveButton(_ status: WineStatus, title: String, icon: String) -> some View {
        Button {
            let wine = lookup.makeWine(status: status)
            if let shelfPrice, shelfPrice > 0 { wine.pricePaid = shelfPrice }
            context.insert(wine)
            try? context.save()
            withAnimation { saved = status }
        } label: {
            Label(saved == status ? "Added" : title, systemImage: saved == status ? "checkmark" : icon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(status == .cellar ? Color.accentColor : Color.accentColor.opacity(0.8))
        .disabled(saved != nil)
        .sensoryFeedback(.success, trigger: saved)
    }

    private func links(_ d: WineDetails) -> some View {
        HStack(spacing: 12) {
            if let url = PriceChecker.wineSearcherURL(d) {
                Link(destination: url) {
                    Label("Wine-Searcher", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let url = PriceChecker.vivinoURL(d) {
                Link(destination: url) {
                    Label("Vivino", systemImage: "arrow.up.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
