import PhotosUI
import SwiftData
import SwiftUI

enum WineSort: String, CaseIterable, Identifiable {
    case recent, myScore, vinous, vintage, price, producer, grape, region, country, style

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: "Most recent"
        case .myScore: "My score"
        case .vinous: "Vinous score"
        case .vintage: "Vintage"
        case .price: "Price"
        case .producer: "Producer"
        case .grape: "Grape"
        case .region: "Region"
        case .country: "Country"
        case .style: "Red, white…"
        }
    }

    var icon: String {
        switch self {
        case .recent: "clock"
        case .myScore: "star"
        case .vinous: "rosette"
        case .vintage: "calendar"
        case .price: "dollarsign"
        case .producer: "house"
        case .grape: "leaf"
        case .region: "map"
        case .country: "globe"
        case .style: "drop"
        }
    }

    /// Sorts that show the list in titled groups.
    var groups: Bool { [.grape, .region, .country, .style].contains(self) }

    static func options(for status: WineStatus) -> [WineSort] {
        status == .tasted ? allCases : allCases.filter { $0 != .myScore }
    }
}

struct WineListView: View {
    let status: WineStatus

    @Query(sort: \Wine.createdAt, order: .reverse) private var allWines: [Wine]
    @Environment(\.modelContext) private var context
    @State private var app = AppState.shared
    @State private var search = ""
    @State private var styleFilter: WineStyle?
    @State private var sort: WineSort = .recent
    @State private var adding: AddSource?
    @State private var libraryItem: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var path: [Wine] = []

    private var title: String { status == .cellar ? "Cellar" : "Tasted" }

    private var wines: [Wine] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return allWines.filter { wine in
            guard wine.status == status else { return false }
            if let styleFilter, wine.style != styleFilter { return false }
            guard !q.isEmpty else { return true }
            let haystack = [wine.producer, wine.name, wine.vintageText, wine.country, wine.region, wine.subregion,
                            wine.appellation, wine.grapes.joined(separator: " "), wine.notes, wine.boughtFrom]
                .joined(separator: " ")
            return haystack.localizedStandardContains(q)
        }
    }

    private var sorted: [Wine] {
        func desc(_ a: Double?, _ b: Double?) -> Bool { (a ?? -1) > (b ?? -1) }
        switch sort {
        case .recent:
            return wines.sorted { ($0.drankOn ?? $0.createdAt) > ($1.drankOn ?? $1.createdAt) }
        case .myScore: return wines.sorted { desc($0.myScore.map(Double.init), $1.myScore.map(Double.init)) }
        case .vinous: return wines.sorted { desc($0.vinousSortValue, $1.vinousSortValue) }
        case .vintage: return wines.sorted { ($0.vintage ?? 0) > ($1.vintage ?? 0) }
        case .price: return wines.sorted { desc($0.pricePaid ?? $0.nycTypical, $1.pricePaid ?? $1.nycTypical) }
        case .producer, .grape, .region, .country, .style:
            return wines.sorted { $0.producer.localizedStandardCompare($1.producer) == .orderedAscending }
        }
    }

    private var sections: [(String, [Wine])] {
        let key: (Wine) -> [String] = { wine in
            switch sort {
            case .grape: return wine.grapes.isEmpty ? ["Unknown grape"] : wine.grapes
            case .region: return [[wine.region, wine.country].filter { !$0.isEmpty }.joined(separator: ", ")].map { $0.isEmpty ? "Unknown region" : $0 }
            case .country: return [wine.country.isEmpty ? "Unknown country" : wine.country]
            case .style: return [wine.style.label]
            default: return [""]
            }
        }
        var groups: [String: [Wine]] = [:]
        for wine in sorted { for k in key(wine) { groups[k, default: []].append(wine) } }
        return groups.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if wines.isEmpty && search.isEmpty && styleFilter == nil {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(title)
            .navigationDestination(for: Wine.self) { WineDetailView(wine: $0) }
            .searchable(text: $search, prompt: "Producer, grape, region…")
            .toolbar { toolbarItems }
            .sheet(item: $adding) { source in
                AddWineView(source: source, status: status)
            }
            .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
            .task {
                if Demo.openDetail, Demo.startTab == status.tab, let first = sorted.first { path = [first] }
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let image = await item.loadImage() { adding = .photo(image) }
                    libraryItem = nil
                }
            }
        }
    }

    // MARK: - Pieces

    private var list: some View {
        List {
            Section { summary }
            if sort.groups {
                ForEach(sections, id: \.0) { name, wines in
                    Section(name) {
                        ForEach(wines) { row($0) }
                    }
                }
            } else {
                Section {
                    ForEach(sorted) { row($0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if wines.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        let shown = wines
        if !shown.isEmpty {
            let bottles = shown.reduce(0) { $0 + max($1.bottles, 1) }
            let value = shown.reduce(0.0) { $0 + ($1.pricePaid ?? 0) * Double(max($1.bottles, 1)) }
            let parts: [String] = status == .cellar
                ? ["\(bottles) bottle\(bottles == 1 ? "" : "s")", value > 0 ? "\(Money.text(value)) paid" : ""]
                : ["\(shown.count) wine\(shown.count == 1 ? "" : "s")"]
            Text(parts.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        }
    }

    private func row(_ wine: Wine) -> some View {
        NavigationLink(value: wine) {
            WineRow(wine: wine)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                context.delete(wine)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(status == .cellar ? "No bottles yet" : "Nothing tasted yet",
                  systemImage: status == .cellar ? "square.stack.3d.up" : "wineglass")
        } description: {
            Text(status == .cellar
                 ? "Photograph a label to add a bottle you own."
                 : "Photograph a label to record a wine you've drunk.")
        } actions: {
            Button {
                adding = CameraPicker.isAvailable ? .camera : nil
                if !CameraPicker.isAvailable { showLibrary = true }
            } label: {
                Label("Scan a label", systemImage: "camera")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                app.showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(WineSort.options(for: status)) { option in
                        Label(option.label, systemImage: option.icon).tag(option)
                    }
                }
                Picker("Show", selection: $styleFilter) {
                    Text("All wines").tag(WineStyle?.none)
                    ForEach(WineStyle.allCases.filter { $0 != .other }) { style in
                        Text(style.label).tag(WineStyle?.some(style))
                    }
                }
            } label: {
                Label("Sort and filter", systemImage: styleFilter == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            }
            Menu {
                if CameraPicker.isAvailable {
                    Button { adding = .camera } label: { Label("Scan a label", systemImage: "camera") }
                }
                Button { showLibrary = true } label: { Label("Choose a photo", systemImage: "photo") }
                Button { adding = .typed } label: { Label("Type it in", systemImage: "keyboard") }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }
}

struct WineRow: View {
    let wine: Wine

    var body: some View {
        HStack(spacing: 12) {
            WineThumb(photo: wine.labelPhoto, style: wine.style)
            VStack(alignment: .leading, spacing: 2) {
                Text(wine.title)
                    .font(.headline)
                    .lineLimit(2)
                if !wine.subtitle.isEmpty {
                    Text(wine.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !wine.placeAndGrapes.isEmpty {
                    Text(wine.placeAndGrapes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                if wine.status == .tasted, let score = wine.myScore {
                    ScoreBadge(score: String(score), prominent: true)
                } else if !wine.vinousScore.isEmpty {
                    ScoreBadge(score: wine.vinousScore, prefix: "V")
                }
                if wine.status == .cellar, wine.bottles > 1 {
                    Text("×\(wine.bottles)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if wine.status == .tasted, let date = wine.drankOn {
                    Text(date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension WineStatus {
    var tab: AppTab { self == .cellar ? .cellar : .tasted }
}
