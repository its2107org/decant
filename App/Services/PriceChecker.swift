import Foundation

/// Finds what New York City wine shops charge for a wine, using Claude's web search.
enum PriceChecker {
    private static let system = """
    You check retail wine prices for a shopper in Manhattan. Search the web for current prices of the given wine at wine shops in New York City (all five boroughs), using the shops' own websites and price listings such as Wine-Searcher.

    Shops worth checking include Astor Wines & Spirits, Sherry-Lehmann, Morrell & Company, Flatiron Wines, Chambers Street Wines, Union Square Wines, Crush Wine & Spirits, Garnet Wines, Mister Wright Fine Wines, 67 Wine, Acker, Burgundy Wine Company, Bottlerocket, Gotham Wines, Park Avenue Liquor Shop, PJ Wine and Best Cellars, but include any New York City shop you find.

    Rules:
    - Only include prices you actually saw in search results or on shop pages. Never estimate or invent a price.
    - Prices in US dollars for one bottle, before tax. Note the bottle size if it isn't 750ml.
    - Prefer the exact vintage. You may include other vintages, marked with their year.
    - Skip auction results and shops outside New York City.
    - "low", "high" and "typical" are for the exact vintage in 750ml where available, otherwise across what you found; "typical" is roughly the middle price. Use null if you found nothing.
    - "note" is one short plain sentence, e.g. "Only two shops list the 2019; other vintages are cheaper." Empty if nothing worth saying.

    Finish your answer with only this JSON object and nothing after it:
    {"offers":[{"store":"","price":0,"vintage":"","bottleSize":"750ml","url":""}],"low":null,"high":null,"typical":null,"note":""}
    """

    static func check(_ wine: WineDetails) async throws -> PriceReport {
        let prompt = "Find current New York City shop prices for: \(wine.searchName)" +
            (wine.appellation.isEmpty ? "" : " (\(wine.appellation), \(wine.country))")
        let report = try await Claude.searchThenAnswer(PriceReport.self, system: system, prompt: prompt,
                                                       maxSearches: 6, effort: "low")
        return tidy(report, vintage: wine.vintage)
    }

    /// Fills in missing figures from the offers and drops anything that isn't a real price.
    static func tidy(_ report: PriceReport, vintage: Int?) -> PriceReport {
        var r = report
        r.offers = r.offers.filter { $0.price > 0 && !$0.store.isEmpty }.sorted { $0.price < $1.price }
        let exact = r.offers.filter { offer in
            guard let vintage else { return true }
            return offer.vintage.isEmpty || offer.vintage.contains(String(vintage))
        }.filter { $0.bottleSize.isEmpty || $0.bottleSize.contains("750") }
        let pool = (exact.isEmpty ? r.offers : exact).map(\.price).sorted()
        if !pool.isEmpty {
            if r.low == nil { r.low = pool.first }
            if r.high == nil { r.high = pool.last }
            if r.typical == nil { r.typical = pool[pool.count / 2] }
        }
        return r
    }

    /// Wine-Searcher's page for this wine, set to New York.
    static func wineSearcherURL(_ wine: WineDetails) -> URL? {
        let name = wine.nameWithoutVintage
            .folding(options: .diacriticInsensitive, locale: .init(identifier: "en_GB"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "+")
        guard !name.isEmpty else { return nil }
        let vintage = wine.vintage.map(String.init) ?? "1"
        return URL(string: "https://www.wine-searcher.com/find/\(name)/\(vintage)/usa-ny")
    }

    /// Vivino's search for this wine (opens the Vivino app if it's installed).
    static func vivinoURL(_ wine: WineDetails) -> URL? {
        var c = URLComponents(string: "https://www.vivino.com/search/wines")
        c?.queryItems = [URLQueryItem(name: "q", value: wine.searchName)]
        return c?.url
    }
}
