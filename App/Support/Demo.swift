import SwiftData
import SwiftUI

/// Pretend wines for the screenshots taken on the build machine. Only used when the app is
/// started with -DecantDemo; normal use never touches this.
@MainActor
enum Demo {
    private static let args = ProcessInfo.processInfo.arguments
    static let isOn = args.contains("-DecantDemo")
    static let openDetail = isOn && args.contains("-DecantDemoDetail")

    static var startTab: AppTab {
        if args.contains("-DecantDemoTasted") { return .tasted }
        if args.contains("-DecantDemoScan") || args.contains("-DecantDemoScanResult") { return .scan }
        return .cellar
    }

    static var startWithSettings: Bool { isOn && args.contains("-DecantDemoSettings") }

    static let scanLookup: WineLookup? = {
        guard isOn, args.contains("-DecantDemoScanResult") else { return nil }
        return WineLookup(details: angerville, prices: prices, vinous: vinous)
    }()

    static let shelfPrice: Double? = scanLookup == nil ? nil : 89

    static let angerville = WineDetails(
        identified: true, producer: "Domaine Marquis d'Angerville", name: "Volnay 1er Cru Clos des Ducs",
        vintage: 2019, style: "red", grapes: ["Pinot Noir"], country: "France", region: "Burgundy",
        subregion: "Côte de Beaune", appellation: "Volnay", classification: "Premier Cru", abv: 13.5,
        bottleSizeML: 750, labelText: "")

    static let prices = PriceReport(
        offers: [
            StoreOffer(store: "Chambers Street Wines", price: 165, vintage: "2019", bottleSize: "750ml", url: ""),
            StoreOffer(store: "Flatiron Wines", price: 179.99, vintage: "2019", bottleSize: "750ml", url: ""),
            StoreOffer(store: "Sherry-Lehmann", price: 189, vintage: "2019", bottleSize: "750ml", url: ""),
            StoreOffer(store: "Morrell & Company", price: 199, vintage: "2019", bottleSize: "750ml", url: "")
        ],
        low: 165, high: 199, typical: 184, note: "")

    static let vinous = VinousReview(
        found: true, signedIn: true, score: "96", critic: "Neal Martin", drinkWindow: "2027-2050",
        note: "The 2019 Volnay Clos des Ducs has a beautifully defined bouquet of red cherries, crushed strawberry and rose petals.",
        url: "")

    static func container() -> ModelContainer {
        let container = try! ModelContainer(for: Wine.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let day: TimeInterval = 86_400

        func wine(_ status: WineStatus, _ d: WineDetails, bottles: Int = 1, paid: Double? = nil, mine: Int? = nil,
                  vinous: String = "", critic: String = "", daysAgo: Double, typical: Double? = nil) {
            let w = Wine(status: status)
            w.apply(d)
            w.bottles = bottles
            w.pricePaid = paid
            w.myScore = mine
            w.vinousScore = vinous
            w.vinousCritic = critic
            w.createdAt = Date().addingTimeInterval(-daysAgo * day)
            if status == .tasted { w.drankOn = w.createdAt }
            w.nycTypical = typical
            context.insert(w)
        }

        func d(_ producer: String, _ name: String, _ vintage: Int?, _ style: String, _ grapes: [String],
               _ country: String, _ region: String, _ appellation: String) -> WineDetails {
            WineDetails(identified: true, producer: producer, name: name, vintage: vintage, style: style, grapes: grapes,
                        country: country, region: region, subregion: "", appellation: appellation, classification: "",
                        abv: nil, bottleSizeML: 750, labelText: "")
        }

        wine(.cellar, angerville, bottles: 3, paid: 172, vinous: "96", critic: "Neal Martin", daysAgo: 2)
        wine(.cellar, d("Ridge Vineyards", "Monte Bello", 2018, "red", ["Cabernet Sauvignon", "Merlot"], "USA", "California", "Santa Cruz Mountains"),
             bottles: 2, paid: 245, vinous: "97", critic: "Antonio Galloni", daysAgo: 9)
        wine(.cellar, d("G.D. Vajra", "Barolo Bricco delle Viole", 2017, "red", ["Nebbiolo"], "Italy", "Piedmont", "Barolo"),
             bottles: 6, paid: 89, vinous: "95", critic: "Antonio Galloni", daysAgo: 21)
        wine(.cellar, d("Domaine Huet", "Le Mont Sec", 2021, "white", ["Chenin Blanc"], "France", "Loire Valley", "Vouvray"),
             bottles: 2, paid: 52, vinous: "93", critic: "Rebecca Gibb", daysAgo: 30)
        wine(.cellar, d("Pierre Péters", "Cuvée de Réserve Blanc de Blancs", nil, "sparkling", ["Chardonnay"], "France", "Champagne", "Champagne"),
             bottles: 4, paid: 68, vinous: "92", critic: "Antonio Galloni", daysAgo: 45)

        wine(.tasted, d("Château Musar", "", 2016, "red", ["Cinsault", "Carignan", "Cabernet Sauvignon"], "Lebanon", "Bekaa Valley", ""),
             paid: 64, mine: 93, vinous: "94", critic: "Neal Martin", daysAgo: 1)
        wine(.tasted, d("Domaine Tempier", "Bandol Rosé", 2023, "rose", ["Mourvèdre", "Grenache", "Cinsault"], "France", "Provence", "Bandol"),
             paid: 48, mine: 90, vinous: "92", critic: "Josh Raynolds", daysAgo: 6)
        wine(.tasted, d("Bodegas López de Heredia", "Viña Tondonia Reserva", 2012, "red", ["Tempranillo", "Garnacha"], "Spain", "Rioja", "Rioja Alta"),
             paid: 70, mine: 95, vinous: "95", critic: "Josh Raynolds", daysAgo: 14)
        wine(.tasted, d("Dr. Loosen", "Wehlener Sonnenuhr Riesling Spätlese", 2020, "white", ["Riesling"], "Germany", "Mosel", "Wehlen"),
             paid: 36, mine: 91, vinous: "93", critic: "Stephan Reinhardt", daysAgo: 25)
        try? context.save()
        return container
    }
}
