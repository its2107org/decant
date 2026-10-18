import SwiftData
import SwiftUI

/// Search Vinous from inside Decant, signed in as Ian, and read the reviews here.
struct VinousSearchView: View {
    @State private var app = AppState.shared
    @State private var query = Demo.searchQuery
    @State private var groups: [[VinousSearch.Entry]] = Demo.searchResults
    @State private var searched = !Demo.searchResults.isEmpty
    @State private var searching = false
    @State private var problem: String?
    @State private var signedIn = Vinous.rememberedSignIn || Demo.isOn
    @State private var selected: VinousResult? = Demo.openSearchResult ? Demo.searchResults.last.map { VinousResult(entries: $0) } : nil

    var body: some View {
        NavigationStack {
            List {
                if !signedIn {
                    Section {
                        Button { app.showSettings = true } label: {
                            Label("Sign in to Vinous in Settings to see scores", systemImage: "person.crop.circle.badge.exclamationmark")
                        }
                    }
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                }
                ForEach(groups, id: \.first?.id) { group in
                    Button { selected = VinousResult(entries: group) } label: {
                        VinousResultRow(entries: group)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .overlay {
                if searching {
                    ProgressView("Searching Vinous…")
                } else if groups.isEmpty {
                    if searched {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ContentUnavailableView("Search Vinous", systemImage: "rosette",
                                               description: Text("Type a producer or wine. Add a year to narrow it down."))
                    }
                }
            }
            .navigationTitle("Vinous")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Producer, wine, year")
            .onSubmit(of: .search) { Task { await run() } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { app.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .sheet(item: $selected) { result in
                VinousResultSheet(entries: result.entries, signedIn: signedIn)
            }
            .onChange(of: app.showSettings) { _, showing in
                if !showing { signedIn = Vinous.rememberedSignIn }
            }
        }
    }

    private func run() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searching = true
        problem = nil
        defer { searching = false; searched = true }
        do {
            let answer = try await Vinous.searchWines(text)
            signedIn = answer.signedIn || Vinous.rememberedSignIn
            groups = VinousSearch.grouped(answer.entries)
        } catch {
            groups = []
            problem = error.localizedDescription
        }
    }
}

struct VinousResult: Identifiable {
    let entries: [VinousSearch.Entry]
    var id: Int { entries.first?.id ?? 0 }
}

struct VinousResultRow: View {
    let entries: [VinousSearch.Entry]

    var body: some View {
        let first = entries[0]
        let scores = entries.map(\.score).filter { !$0.isEmpty }
        HStack(alignment: .top, spacing: 12) {
            WineThumb(photo: nil, style: WineStyle(loose: first.color), width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(first.title).font(.body.weight(.semibold))
                Text(first.producer).font(.subheadline).foregroundStyle(.secondary)
                let more = [first.placeLine, Set(scores).count > 1 || entries.count > 1 ? "\(entries.count) reviews" : first.critic]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                if !more.isEmpty {
                    Text(more).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !scores.isEmpty {
                ScoreBadge(score: VinousReview.average(scores), prominent: true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One wine from the search: all its reviews, the full review on Vinous, and adding it to Decant.
struct VinousResultSheet: View {
    let entries: [VinousSearch.Entry]
    var signedIn: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var page: VinousPage?
    @State private var saved: WineStatus?

    private var first: VinousSearch.Entry { entries[0] }
    private var review: VinousReview? { VinousSearch.combined(entries, signedIn: signedIn) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(first.title).font(.title2.weight(.bold))
                        Text(first.producer).font(.headline).foregroundStyle(.secondary)
                        if !first.placeLine.isEmpty {
                            Text(first.placeLine).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Card(title: "Vinous", systemImage: "rosette") {
                        if let review, review.found {
                            if review.reviews.count > 1 {
                                VinousScoreView(score: review.score, critic: review.critic, drinkWindow: "",
                                                note: "", reviews: review.reviews)
                            } else if let item = singleItem {
                                VinousReviewRow(item: item, noteLines: nil)
                            }
                        } else {
                            Text(signedIn ? "Open the review on Vinous to read it." : "Sign in to Vinous in Settings to see scores.")
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            if let url = first.url { page = VinousPage(url: url) }
                        } label: {
                            Label("Read the full review", systemImage: "doc.text").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    HStack(spacing: 12) {
                        save(.cellar, title: "Add to Cellar", icon: "square.stack.3d.up")
                        save(.tasted, title: "Drinking it", icon: "wineglass")
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $page) { page in
                VinousBrowserSheet(start: page.url)
            }
        }
    }

    private var singleItem: VinousReviewItem? {
        guard let e = VinousSearch.bestReview(entries), !e.score.isEmpty else { return nil }
        return VinousReviewItem(score: e.score, critic: e.critic, date: e.articleDate, drinkWindow: e.drinkWindow, note: e.fullNote)
    }

    private func save(_ status: WineStatus, title: String, icon: String) -> some View {
        Button {
            let wine = Wine(status: status)
            wine.apply(first.details)
            if let review, review.found { wine.applyVinous(review) }
            if status == .tasted { wine.drankOn = Date() }
            context.insert(wine)
            try? context.save()
            withAnimation { saved = status }
            if review?.found != true {
                // The results had no score (for example when signed out); look it up properly.
                Task {
                    if let found = try? await Vinous.lookup(wine.details), found.found {
                        wine.applyVinous(found)
                        try? context.save()
                    }
                }
            }
        } label: {
            Label(saved == status ? "Added" : title, systemImage: saved == status ? "checkmark" : icon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(saved != nil)
        .sensoryFeedback(.success, trigger: saved)
    }
}
