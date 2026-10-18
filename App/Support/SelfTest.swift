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
