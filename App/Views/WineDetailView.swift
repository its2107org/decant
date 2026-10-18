import SwiftData
import SwiftUI

struct WineDetailView: View {
    @Bindable var wine: Wine

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editing = false
    @State private var opening = false
    @State private var confirmDelete = false
    @State private var checkingPrices = false
    @State private var checkingVinous = false
    @State private var problem: String?
    @State private var vinousPage: VinousPage?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if wine.status == .cellar {
                    Button {
                        opening = true
                    } label: {
                        Label(wine.bottles > 1 ? "Opened a bottle" : "Opened it", systemImage: "wineglass")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    yourScore
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                vinousCard
                pricesCard
                detailsCard
                linksCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(wine.vintageText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if wine.status == .tasted {
                        Button { wine.status = .cellar } label: { Label("Move to Cellar", systemImage: "square.stack.3d.up") }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .confirmationDialog("Delete this wine?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(wine)
                dismiss()
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                WineEditor(wine: wine)
                    .navigationTitle("Edit")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } }
                    }
            }
        }
        .sheet(isPresented: $opening) {
            OpenBottleSheet(wine: wine) { dismiss() }
        }
        .sheet(item: $vinousPage) { page in
            VinousBrowserSheet(start: page.url, wine: wine.details) { review in
                wine.applyVinous(review)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            if let data = wine.labelPhoto, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            } else {
                WineThumb(photo: nil, style: wine.style, width: 80)
            }
            VStack(spacing: 4) {
                Text(wine.name.isEmpty ? wine.producer : wine.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                if !wine.subtitle.isEmpty {
                    Text(wine.producer).font(.headline).foregroundStyle(.secondary)
                }
                Text([wine.vintageText, wine.style.label, wine.placeAndGrapes].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if wine.status == .cellar {
                    Text("\(wine.bottles) bottle\(wine.bottles == 1 ? "" : "s") in your cellar")
                        .font(.subheadline.weight(.medium))
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var yourScore: some View {
        Card(title: "Your score", systemImage: "star") {
            ScoreEditor(score: $wine.myScore)
            if let date = wine.drankOn {
                Footnote(text: "Drunk \(date.formatted(date: .long, time: .omitted))")
            }
            TextField("Tasting notes", text: $wine.notes, axis: .vertical)
                .lineLimit(2...10)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var vinousCard: some View {
        Card(title: "Vinous", systemImage: "rosette") {
            if !wine.vinousScore.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(wine.vinousScore)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        if !wine.vinousCritic.isEmpty { Text(wine.vinousCritic).font(.subheadline.weight(.medium)) }
                        if !wine.vinousDrinkWindow.isEmpty {
                            Text("Drink \(wine.vinousDrinkWindow)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                if wine.vinousIsOtherVintage {
                    Label("This score is for the \(wine.vinousVintage). Vinous hasn't reviewed the \(wine.vintageText) yet.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if !wine.vinousNote.isEmpty {
                    Text(wine.vinousNote).font(.callout).foregroundStyle(.secondary)
                }
            } else if !checkingVinous {
                Text(wine.vinousCheckedAt == nil ? "Not looked up yet." : "Vinous hasn't reviewed this wine.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    Task { await lookUpVinous() }
                } label: {
                    if checkingVinous {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(wine.vinousCheckedAt == nil ? "Look up" : "Refresh").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(checkingVinous)
                Button {
                    vinousPage = VinousPage(url: URL(string: wine.vinousURL) ?? Vinous.searchURL)
                } label: {
                    Text("Open on Vinous").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var pricesCard: some View {
        Card(title: "New York prices", systemImage: "storefront") {
            if let typical = wine.nycTypical {
                HStack(alignment: .firstTextBaseline) {
                    Text(Money.text(typical))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("typical").foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.range(wine.nycLow, wine.nycHigh)).foregroundStyle(.secondary)
                }
                if let paid = wine.pricePaid {
                    Footnote(text: "You paid \(Money.text(paid)).")
                }
                OffersList(offers: wine.nycOffers)
            } else if !checkingPrices {
                Text(wine.nycCheckedAt == nil ? "Not checked yet." : "No New York prices found.")
                    .foregroundStyle(.secondary)
            }
            if let checked = wine.nycCheckedAt {
                Footnote(text: "Checked \(checked.formatted(.relative(presentation: .named)))")
            }
            Button {
                Task { await checkPrices() }
            } label: {
                if checkingPrices {
                    HStack(spacing: 8) { ProgressView(); Text("Checking shops…") }.frame(maxWidth: .infinity)
                } else {
                    Text(wine.nycCheckedAt == nil ? "Check prices" : "Check again").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(checkingPrices)
        }
    }

    private var detailsCard: some View {
        Card(title: "Details", systemImage: "list.bullet") {
            VStack(spacing: 0) {
                let rows: [(String, String)] = [
                    ("Producer", wine.producer),
                    ("Grapes", wine.grapes.joined(separator: ", ")),
                    ("Country", wine.country),
                    ("Region", wine.region),
                    ("Sub-region", wine.subregion),
                    ("Appellation", wine.appellation),
                    ("Classification", wine.classification),
                    ("Alcohol", wine.abv.map { String(format: "%g%%", $0) } ?? ""),
                    ("Bottle", WineEditor.sizeLabel(wine.bottleSizeML)),
                    ("Price paid", wine.pricePaid.map { Money.text($0) } ?? ""),
                    ("Bought from", wine.boughtFrom),
                    ("Added", wine.createdAt.formatted(date: .abbreviated, time: .omitted))
                ].filter { !$0.1.isEmpty }
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0).foregroundStyle(.secondary)
                        Spacer(minLength: 16)
                        Text(row.1).multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var linksCard: some View {
        HStack(spacing: 12) {
            if let url = PriceChecker.wineSearcherURL(wine.details) {
                Link(destination: url) {
                    Label("Wine-Searcher", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let url = PriceChecker.vivinoURL(wine.details) {
                Link(destination: url) {
                    Label("Vivino", systemImage: "arrow.up.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Actions

    private func checkPrices() async {
        checkingPrices = true
        problem = nil
        defer { checkingPrices = false }
        do {
            wine.applyPrices(try await PriceChecker.check(wine.details))
        } catch {
            problem = error.localizedDescription
        }
    }

    private func lookUpVinous() async {
        checkingVinous = true
        problem = nil
        defer { checkingVinous = false }
        do {
            let review = try await Vinous.lookup(wine.details)
            if review.found {
                wine.applyVinous(review)
            } else {
                wine.clearVinous()
                if !review.signedIn || !Vinous.rememberedSignIn {
                    problem = "Couldn't read a Vinous score. Check you're signed in to Vinous in Settings, or tap Open on Vinous."
                }
            }
        } catch {
            problem = error.localizedDescription
        }
    }
}

struct VinousPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// "Opened a bottle": score it and move it (or one of several bottles) to Tasted.
struct OpenBottleSheet: View {
    let wine: Wine
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var score: Int? = nil
    @State private var notes = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(wine.title).font(.headline)
                }
                Section("Your score") {
                    ScoreEditor(score: $score)
                    DatePicker("Drunk on", selection: $date, displayedComponents: .date)
                }
                Section("Notes") {
                    TextField("How was it?", text: $notes, axis: .vertical).lineLimit(3...10)
                }
                if wine.bottles > 1 {
                    Section {
                        EmptyView()
                    } footer: {
                        Text("\(wine.bottles - 1) bottle\(wine.bottles == 2 ? "" : "s") will stay in your cellar.")
                    }
                }
            }
            .navigationTitle("Opened it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
    }

    private func save() {
        let tasted: Wine
        if wine.bottles > 1 {
            wine.bottles -= 1
            tasted = wine.tastedCopy()
            context.insert(tasted)
        } else {
            tasted = wine
            wine.status = .tasted
        }
        tasted.myScore = score
        tasted.drankOn = date
        if !notes.isEmpty { tasted.notes = notes }
        try? context.save()
        dismiss()
        onDone()
    }
}
