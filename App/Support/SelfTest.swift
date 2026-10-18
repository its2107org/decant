import Foundation
import SwiftData

/// Checks run on the build machine (started with -DecantSelfTest). They cover the parts that
/// don't need Claude: reading Claude's answers, price maths, links and saving wines.
@MainActor
enum SelfTest {
    static func runIfRequested(container: ModelContainer) async {
        guard ProcessInfo.processInfo.arguments.contains("-DecantSelfTest") else { return }
        var results: [[String: Any]] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            results.append(["check": name, "ok": ok, "detail": detail])
        }

        // 1. A label answer in Claude's fixed shape decodes into a wine record.
        let labelJSON = """
        {"identified":true,"producer":"Ridge Vineyards","name":"Monte Bello","vintage":2018,"style":"red",
         "grapes":["Cabernet Sauvignon","Merlot"],"country":"USA","region":"California","subregion":"",
         "appellation":"Santa Cruz Mountains","classification":"","abv":13.4,"bottleSizeML":null,"labelText":"RIDGE"}
        """
        let details = try? JSONDecoder().decode(WineDetails.self, from: Data(labelJSON.utf8))
        check("label answer decodes", details?.producer == "Ridge Vineyards" && details?.vintage == 2018 && details?.bottleSizeML == nil)
        check("search name", details?.searchName == "Ridge Vineyards Monte Bello 2018", details?.searchName ?? "")

        // 2. The JSON at the end of a searched answer is found, even after text with braces in it.
        let searched = """
        I checked several shops {including Astor}. Here is what I found.
        {"offers":[{"store":"Astor Wines","price":249.99,"vintage":"2018","bottleSize":"750ml","url":"https://www.astorwines.com/x"},
        {"store":"Flatiron Wines","price":0,"vintage":"2018","bottleSize":"750ml","url":""},
        {"store":"Morrell","price":265,"vintage":"2017","bottleSize":"750ml","url":"https://morrellwine.com/y"},
        {"store":"Sherry-Lehmann","price":275,"vintage":"2018","bottleSize":"750ml","url":"https://sherry-lehmann.com/z"}],
        "low":null,"high":null,"typical":null,"note":"Note with a brace } inside."}
        """
        let data = Claude.lastJSONObject(in: searched)
        let raw = data.flatMap { try? JSONDecoder().decode(PriceReport.self, from: $0) }
        check("price answer found and decodes", raw?.offers.count == 4)
        if let raw {
            let report = PriceChecker.tidy(raw, vintage: 2018)
            check("tidy drops zero prices", report.offers.count == 3)
            check("tidy fills range from exact vintage", report.low == 249.99 && report.high == 275, "\(report.low ?? -1)–\(report.high ?? -1)")
            check("verdict good", report.verdict(for: 240) == .good)
            check("verdict high", report.verdict(for: 330) == .high)
        }

        // 3. Scores and links.
        check("score range sorts as middle", Wine.scoreValue("92-94") == 93)
        check("plain score", Wine.scoreValue("96+") == 96)
        if let details {
            let ws = PriceChecker.wineSearcherURL(details)?.absoluteString ?? ""
            check("wine-searcher link", ws == "https://www.wine-searcher.com/find/ridge+vineyards+monte+bello/2018/usa-ny", ws)
            check("vivino link", PriceChecker.vivinoURL(details)?.absoluteString.contains("vivino.com/search/wines?q=Ridge") == true)
        }

        // 3b. Vinous scores for another vintage are flagged and kept out of the list.
        if let details {
            var review = VinousReview(found: true, signedIn: true, score: "91", critic: "Josh Raynolds",
                                      drinkWindow: "", note: "", url: "", vintage: "2016", pageWine: "")
            check("other vintage spotted", !review.isSameVintage(as: details))
            review.vintage = "2018"
            check("same vintage accepted", review.isSameVintage(as: details))
            let w = Wine(status: .cellar)
            w.apply(details)
            w.applyVinous(VinousReview(found: true, signedIn: true, score: "91", critic: "", drinkWindow: "",
                                       note: "", url: "", vintage: "2016", pageWine: ""))
            check("other vintage kept out of list", w.vinousIsOtherVintage && w.listVinousScore.isEmpty)
            w.clearVinous()
            check("wrong match cleared", w.vinousScore.isEmpty && w.vinousCheckedAt != nil)
            check("description names the wine", details.fullDescription.contains("Santa Cruz Mountains"))
        }

        // 3c. Vinous search: real answers from Vinous, matched to bottles.
        func bottle(_ producer: String, _ name: String, _ vintage: Int?) -> WineDetails {
            WineDetails(identified: true, producer: producer, name: name, vintage: vintage, style: "red", grapes: [],
                        country: "", region: "", subregion: "", appellation: "", classification: "", abv: nil,
                        bottleSizeML: nil, labelText: "")
        }
        let evesham = bottle("Evesham Wood", "Willamette Valley Pinot Noir", 2024)
        let eveshamResults = VinousSearch.entries(from: VinousFixtures.evesham2024)
        check("vinous results read", eveshamResults.count == 3, "\(eveshamResults.count)")
        let eveshamMatch = VinousSearch.exactMatches(eveshamResults, wine: evesham)
        check("evesham 2024 matched", eveshamMatch.count == 1 && eveshamMatch.first?.slug == "evesham-wood-2024-pinot-noir-willamette-valley",
              eveshamMatch.map(\.slug).joined(separator: ","))
        if let e = VinousSearch.bestReview(eveshamMatch) {
            let r = e.review(signedIn: false)
            check("evesham review details", r.critic == "Eric Guido" && r.drinkWindow == "2026-2030" && r.vintage == "2024"
                  && r.url == "https://vinous.com/wines/evesham-wood-2024-pinot-noir-willamette-valley" && !r.found,
                  "\(r.critic) \(r.drinkWindow) \(r.vintage) \(r.url) \(r.found)")
        } else {
            check("evesham review details", false)
        }
        check("evesham search terms", VinousSearch.terms(for: evesham) == ["Evesham Wood Willamette Valley Pinot Noir", "Evesham Wood", "Willamette Valley Pinot Noir"],
              VinousSearch.terms(for: evesham).joined(separator: " | "))
        check("other evesham wines not matched",
              VinousSearch.exactMatches(eveshamResults, wine: bottle("Evesham Wood", "Pinot Noir", 2024)).isEmpty)
        check("evesham vineyard is the same producer",
              VinousSearch.key(producer: "Evesham Wood Vineyard", wine: "Pinot Noir Willamette Valley") == eveshamMatch.first?.key)

        let ridge = VinousSearch.entries(from: VinousFixtures.ridge2018)
        let monteBello = VinousSearch.exactMatches(ridge, wine: bottle("Ridge", "Monte Bello", 2018))
        check("ridge monte bello, not the chardonnay", monteBello.count == 3 && !monteBello.contains { $0.wine.contains("Chardonnay") },
              monteBello.map(\.wine).joined(separator: ","))
        check("ridge full name matches too", VinousSearch.exactMatches(ridge, wine: bottle("Ridge Vineyards", "Monte Bello", 2018)).count == 3)

        let margaux = VinousSearch.key(producer: "Château Margaux", wine: "Château Margaux")
        check("margaux grand vin", VinousSearch.key(producer: "Chateau Margaux", wine: "") == margaux
              && VinousSearch.key(producer: "Château Margaux", wine: "Grand Vin") == margaux
              && VinousSearch.key(producer: "Château Margaux", wine: "Pavillon Rouge de Margaux") != margaux)

        let bollinger = VinousSearch.entries(from: VinousFixtures.bollingerNV)
        let special = VinousSearch.exactMatches(bollinger, wine: bottle("Bollinger", "Special Cuvée Brut", nil))
        check("bollinger NV spellings", special.count >= 5 && !special.contains { $0.wine.contains("007") } && special.allSatisfy { $0.vintage == 0 },
              special.map(\.wine).joined(separator: ","))
        check("NV review label", special.first?.review(signedIn: true).vintage == "NV")

        let lopez = bottle("R. López de Heredia", "Viña Tondonia Reserva", 2012)
        let lopezTerms = VinousSearch.terms(for: lopez)
        check("short search when a label word is missing", lopezTerms.contains("López de Heredia") && lopezTerms.first == "R. López de Heredia Viña Tondonia Reserva",
              lopezTerms.joined(separator: " | "))
        check("lopez left for Claude to decide", VinousSearch.exactMatches(VinousSearch.entries(from: VinousFixtures.lopez2012), wine: lopez).isEmpty)
        let leflaive = VinousSearch.entries(from: VinousFixtures.leflaive2019)
        check("leflaive left for Claude to decide",
              VinousSearch.exactMatches(leflaive, wine: bottle("Domaine Leflaive", "Puligny-Montrachet Les Pucelles 1er Cru", 2019)).isEmpty
              && leflaive.count >= 10)

        check("vinous scores", VinousSearch.scoreText(NSNumber(value: 92)) == "92" && VinousSearch.scoreText("92-94") == "92-94"
              && VinousSearch.scoreText("00").isEmpty && VinousSearch.scoreText(NSNumber(value: 0)).isEmpty && VinousSearch.scoreText(nil).isEmpty)
        if let first = eveshamResults.first {
            var newer = first; newer.score = "93"; newer.reviewDate = "2026-08-01"
            var older = first; older.score = "91"; older.reviewDate = "2025-01-01"
            var unscored = first; unscored.score = ""; unscored.reviewDate = "2026-09-01"
            check("newest scored review", VinousSearch.bestReview([older, unscored, newer])?.score == "93")
        }
        check("vinous search page link", Vinous.searchURL(for: evesham).absoluteString.contains("term=Evesham%20Wood%20Willamette"),
              Vinous.searchURL(for: evesham).absoluteString)

        // 3d. Several reviews of one wine: all listed, average as the score. Search tab helpers.
        check("average of scores", VinousReview.average(["93", "91"]) == "92" && VinousReview.average(["96", "94-96"]) == "95.5"
              && VinousReview.average(["92+"]) == "92+" && VinousReview.average([]).isEmpty,
              VinousReview.average(["96", "94-96"]))
        if let first = eveshamResults.last {
            var a = first; a.score = "93"; a.critic = "Eric Guido"; a.reviewDate = "2026-07-14"; a.articleDate = "July 2026"
            var b = first; b.id += 1; b.score = "90"; b.critic = "Josh Raynolds"; b.reviewDate = "2025-03-01"; b.articleDate = "March 2025"
            let both = VinousSearch.combined([b, a], signedIn: true)
            check("all reviews listed with average", both?.reviews.count == 2 && both?.score == "91.5"
                  && both?.reviews.first?.critic == "Eric Guido" && both?.critic == "Average of 2 reviews",
                  "\(both?.score ?? "") \(both?.reviews.count ?? 0)")
            check("one review stays as it is", VinousSearch.combined([a], signedIn: true)?.score == "93"
                  && VinousSearch.combined([a], signedIn: true)?.reviews.isEmpty == true)
            check("same review twice counted once", VinousSearch.combined([a, a], signedIn: true)?.reviews.isEmpty == true)
            check("results grouped per wine", VinousSearch.grouped(eveshamResults + [b]).count == 3)
            let w = Wine(status: .cellar)
            w.apply(first.details)
            if let both { w.applyVinous(both) }
            check("reviews saved with the wine", w.vinousReviews.count == 2 && w.listVinousScore == "91.5" && w.producer == "Evesham Wood"
                  && w.vintage == 2024 && w.appellation == "Willamette Valley")
        }
        let page = Vinous.review(from: [VinousReviewItem(score: "94", critic: "A", date: "", drinkWindow: "", note: ""),
                                        VinousReviewItem(score: "00", critic: "B", date: "", drinkWindow: "", note: ""),
                                        VinousReviewItem(score: "92", critic: "C", date: "", drinkWindow: "", note: "")],
                                 pageWine: "", vintage: "2018", signedIn: true, usable: true)
        check("page reviews averaged, hidden score skipped", page.found && page.score == "93" && page.reviews.count == 2, page.score)
        check("year split from search", VinousSearch.splitYear("evesham wood 2024").term == "evesham wood"
              && VinousSearch.splitYear("evesham wood 2024").vintage == 2024 && VinousSearch.splitYear("monte bello").vintage == nil)
        if let monte = ridge.first {
            check("grapes without percentages", monte.details.grapes.first == "Cabernet Sauvignon", monte.details.grapes.joined(separator: ","))
        }

        // 4. The label schema is a valid structured-output schema shape.
        let required = LabelReader.schema["required"] as? [String] ?? []
        let properties = (LabelReader.schema["properties"] as? [String: Any])?.keys.sorted() ?? []
        check("schema lists every field as required", required.sorted() == properties)
        check("schema serialises", (try? JSONSerialization.data(withJSONObject: LabelReader.schema)) != nil)

        // 5. Saving: add to cellar, open one of two bottles, it appears in Tasted.
        let store = try? ModelContainer(for: Wine.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        if let store, let details {
            let context = store.mainContext
            let wine = Wine(status: .cellar)
            wine.apply(details)
            wine.bottles = 2
            context.insert(wine)
            let tasted = wine.tastedCopy()
            wine.bottles -= 1
            tasted.myScore = 95
            context.insert(tasted)
            try? context.save()
            let all = (try? context.fetch(FetchDescriptor<Wine>())) ?? []
            check("open a bottle", all.count == 2 && all.contains { $0.status == .tasted && $0.myScore == 95 }
                  && all.contains { $0.status == .cellar && $0.bottles == 1 })
        } else {
            check("open a bottle", false, "couldn't make a store")
        }

        let passed = results.allSatisfy { $0["ok"] as? Bool == true }
        let summary: [String: Any] = ["result": passed ? "all passed" : "failed", "checks": results]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("selftest.json")
        if let out = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: url)
        }
    }
}
