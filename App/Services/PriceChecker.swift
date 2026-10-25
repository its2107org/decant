import Foundation

/// Finds what Ian's chosen New York wine shops charge for a wine.
///
/// Shops whose websites answer searches directly are asked directly, and Claude picks out the listings
/// that are this exact wine. The other shops on his list are checked with a web search limited to their sites.
enum PriceChecker {
    /// Shops whose own search gives exact, current prices.
    static let directShops: [(name: String, domain: String)] = [
        ("Chambers Street Wines", "chambersstwines.com"),
        ("Crush Wine & Spirits", "crushwineco.com"),
        ("67 Wine", "67wine.com"),
        ("PJ Wine", "pjwine.com"),
        ("Zachys", "zachys.com")
    ]

    /// The rest of Ian's list (agreed 25 Oct 2026). Their sites don't answer apps directly.
    static let searchedShops: [(name: String, domain: String)] = [
        ("Mister Wright Fine Wines", "misterwrightfinewines.com"),
        ("Astor Wines & Spirits", "astorwines.com"),
        ("Flatiron Wines", "flatiron-wines.com"),
        ("K&L Wine Merchants", "klwines.com"),
        ("Park Avenue Liquor Shop (K&L)", "parkaveliquor.com"),
        ("Sherry-Lehmann", "sherry-lehmann.com"),
        ("Morrell & Company", "morrellwine.com"),
        ("Union Square Wines", "unionsquarewines.com"),
        ("Garnet Wines", "garnetwine.com"),
        ("Acker", "ackerwines.com"),
        ("Gotham Wines", "gothamwines.com"),
        ("Italian Wine Merchants", "italianwinemerchants.com"),
        ("Bowery & Vine", "boweryandvine.com"),
        ("Discovery Wines", "discoverywines.com")
    ]

    /// A product a shop's own search returned.
    struct Listing: Equatable {
        var store: String
        var title: String
        var price: Double
        var url: String
    }

    static func check(_ wine: WineDetails) async throws -> PriceReport {
        async let listings = directListings(for: wine)
        async let searched = searchOtherShops(wine)
        let picked = (try? await pick(from: await listings, wine: wine)) ?? []
        var report: PriceReport
        do {
            report = try await searched
        } catch {
            // Without the searched shops, the direct ones are still worth showing.
            if picked.isEmpty { throw error }
            report = PriceReport(offers: [], low: nil, high: nil, typical: nil, note: "")
        }
        report.offers = merge(picked, report.offers)
        report.low = nil
        report.high = nil
        report.typical = nil
        return tidy(report, vintage: wine.vintage)
    }

    /// Puts both halves together, dropping a shop's second listing of the same bottle at the same price.
    static func merge(_ first: [StoreOffer], _ second: [StoreOffer]) -> [StoreOffer] {
        var out: [StoreOffer] = []
        for offer in first + second where !out.contains(where: {
            $0.store == offer.store && $0.price == offer.price && $0.vintage == offer.vintage && $0.bottleSize == offer.bottleSize
        }) {
            out.append(offer)
        }
        return out
    }

    // MARK: - Shops searched directly

    /// What to type into a shop's search box: the producer and wine, then the wine's own name on its own.
    static func queries(for wine: WineDetails) -> [String] {
        let fold = { (s: String) in
            s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en"))
                .replacingOccurrences(of: #"\b(18|19|20)\d\d\b"#, with: "", options: .regularExpression)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        var out: [String] = []
        for q in [fold(VinousSearch.terms(for: wine).first ?? wine.producer), fold(wine.name)] where q.count >= 3 {
            if !out.contains(where: { $0.caseInsensitiveCompare(q) == .orderedSame }) { out.append(q) }
        }
        return out
    }

    static func directListings(for wine: WineDetails) async -> [Listing] {
        let queries = queries(for: wine)
        return await withTaskGroup(of: [Listing].self) { group in
            for shop in directShops {
                for q in queries {
                    group.addTask { (try? await suggest(shop: shop, query: q)) ?? [] }
                }
            }
            var all: [Listing] = []
            for await found in group {
                for l in found where !all.contains(where: { $0.url == l.url }) { all.append(l) }
            }
            return all
        }
    }

    private static func suggest(shop: (name: String, domain: String), query: String) async throws -> [Listing] {
        var c = URLComponents(string: "https://\(shop.domain)/search/suggest.json")!
        c.queryItems = [URLQueryItem(name: "q", value: query),
                        URLQueryItem(name: "resources[type]", value: "product"),
                        URLQueryItem(name: "resources[limit]", value: "10")]
        var request = URLRequest(url: c.url!, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return listings(from: data, shop: shop)
    }

    /// Reads a shop's search answer, keeping products that are in stock.
    static func listings(from data: Data, shop: (name: String, domain: String)) -> [Listing] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = ((root["resources"] as? [String: Any])?["results"] as? [String: Any])?["products"] as? [[String: Any]]
        else { return [] }
        return products.compactMap { p in
            guard p["available"] as? Bool != false, let title = p["title"] as? String,
                  let price = Double("\(p["price"] ?? "")") ?? (p["price"] as? NSNumber)?.doubleValue, price > 0 else { return nil }
            var path = p["url"] as? String ?? ""
            if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
            let url = path.hasPrefix("http") ? path : "https://\(shop.domain)\(path)"
            return Listing(store: shop.name, title: title.replacingOccurrences(of: "\u{a0}", with: " "), price: price, url: url)
        }
    }

    /// Claude picks the shop listings that are this exact wine.
    private static func pick(from listings: [Listing], wine: WineDetails) async throws -> [StoreOffer] {
        guard !listings.isEmpty else { return [] }
        let list = listings.prefix(120).enumerated().map { i, l in "\(i). \(l.store): \(l.title) | $\(l.price)" }
            .joined(separator: "\n")
        let system = """
        You match a wine to listings from wine shops' own websites. Shop searches return many unrelated wines; keep only listings of exactly the wine described: the same producer and the same cuvée, vineyard or appellation, and colour. A producer's other wines don't count (for example a Reserva and a Gran Reserva, or a red and a white, are different wines). Any vintage of the right wine counts.
        For each match give its number, its vintage as shown ("NV" if it has none and is non-vintage, empty if not shown) and its bottle size ("750ml" unless the title says otherwise, e.g. "1.5L" or "375ml"). Leave out gift sets, packs and verticals.
        """
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["matches": ["type": "array", "items": [
                "type": "object",
                "properties": ["index": ["type": "integer"], "vintage": ["type": "string"], "bottleSize": ["type": "string"]],
                "required": ["index", "vintage", "bottleSize"],
                "additionalProperties": false
            ]]],
            "required": ["matches"],
            "additionalProperties": false
        ]
        struct Matches: Decodable {
            struct Match: Decodable { var index: Int; var vintage: String; var bottleSize: String }
            var matches: [Match]
        }
        let answer = try await Claude.structured(Matches.self, model: Claude.sonnet, system: system,
                                                 content: [["type": "text", "text": "The wine:\n\(wine.fullDescription)\n\nListings:\n\(list)"]],
                                                 schema: schema, effort: "low", maxTokens: 4000)
        return offers(from: answer.matches.map { ($0.index, $0.vintage, $0.bottleSize) }, listings: Array(listings.prefix(120)))
    }

    static func offers(from matches: [(index: Int, vintage: String, bottleSize: String)], listings: [Listing]) -> [StoreOffer] {
        matches.compactMap { m in
            guard listings.indices.contains(m.index) else { return nil }
            let l = listings[m.index]
            return StoreOffer(store: l.store, price: l.price, vintage: m.vintage,
                              bottleSize: m.bottleSize.isEmpty ? "750ml" : m.bottleSize, url: l.url)
        }
    }

    // MARK: - The other shops on the list

    private static func searchOtherShops(_ wine: WineDetails) async throws -> PriceReport {
        let names = searchedShops.map(\.name).joined(separator: ", ")
        let system = """
        You check retail wine prices for a shopper in Manhattan. Search these shops' websites for the given wine: \(names).

        Rules:
        - Only include prices you actually saw on these shops' pages or in search results from them. Never estimate or invent a price.
        - Only the exact wine: same producer and same cuvée, vineyard or appellation. Prefer the exact vintage; you may include other vintages, marked with their year.
        - Prices in US dollars for one bottle, before tax. Note the bottle size if it isn't 750ml.
        - "note" is one short plain sentence, e.g. "Only two shops list the 2019." Empty if nothing worth saying.

        Finish your answer with only this JSON object and nothing after it:
        {"offers":[{"store":"","price":0,"vintage":"","bottleSize":"750ml","url":""}],"low":null,"high":null,"typical":null,"note":""}
        """
        let prompt = "Find current prices at these shops for: \(wine.searchName)" +
            (wine.appellation.isEmpty ? "" : " (\(wine.appellation), \(wine.country))")
        return try await Claude.searchThenAnswer(PriceReport.self, system: system, prompt: prompt,
                                                 allowedDomains: searchedShops.map(\.domain), maxSearches: 5, effort: "low")
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
