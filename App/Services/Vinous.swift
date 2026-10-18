import Foundation
import WebKit

/// Looks wines up on Vinous using Ian's own signed-in Vinous account.
///
/// Vinous has no public way for apps to read scores, so Decant does what Ian would do by hand:
/// it opens the wine's Vinous page in a hidden browser that shares his Vinous sign-in, reads the
/// page, and picks out the score. One wine at a time, only when he asks.
@MainActor
enum Vinous {
    static let signInURL = URL(string: "https://vinous.com/users/sign_in")!
    static let searchURL = URL(string: "https://vinous.com/wines")!

    private static let signedInKey = "vinousSignedIn"

    static var rememberedSignIn: Bool {
        get { UserDefaults.standard.bool(forKey: signedInKey) }
        set { UserDefaults.standard.set(newValue, forKey: signedInKey) }
    }

    /// True if the page on show offers to sign out (so Ian is signed in).
    static func pageShowsSignedIn(_ webView: WKWebView) async -> Bool {
        guard webView.url?.host()?.contains("vinous.com") == true else { return false }
        let text = ((try? await webView.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String) ?? ""
        let lower = text.lowercased()
        return ["sign out", "log out", "logout", "my account"].contains { lower.contains($0) }
    }

    static func signOut() async {
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                               for: records.filter { $0.displayName.contains("vinous") })
        rememberedSignIn = false
    }

    // MARK: - Lookup

    static func lookup(_ wine: WineDetails) async throws -> VinousReview {
        let notFound = VinousReview(found: false, signedIn: rememberedSignIn, score: "", critic: "",
                                    drinkWindow: "", note: "", url: "")
        guard let page = try await findPage(wine) else { return notFound }
        let text = try await PageReader.text(of: page)
        var review = try await extract(from: text, wine: wine, trustPage: false)
        review.url = page.absoluteString
        rememberedSignIn = review.signedIn
        return review
    }

    private static let matchingRules = """
    Matching rules (strict):
    - Same producer AND the same wine: the same cuvée, vineyard, appellation or AVA designation and colour.
    - A producer's other wines are different wines, even with the same grape. For example "Willamette Valley Pinot Noir" and "Pinot Noir Eola-Amity Hills Cuvée" are different wines; so are a "Reserve", a single-vineyard bottling, a second wine or a different appellation.
    - Different vintages of the same wine count as the same wine.
    """

    /// Reads the score from a Vinous page's text. With `trustPage`, Ian chose the page himself,
    /// so any score on it is used.
    static func extract(from text: String, wine: WineDetails, trustPage: Bool) async throws -> VinousReview {
        let system = """
        You read the text of a Vinous (vinous.com) wine page for a subscriber and pull out the review.
        - pageWine: the wine's name as the page shows it, with its vintage.
        - sameWine: true only if the page is for the wine described. \(matchingRules)
        - signedIn: false if the page asks to sign in or subscribe instead of showing reviews.
        - vintage: the vintage of the review you report, e.g. "2022" or "NV".
        - score: as printed, e.g. "94" or "92-94". Use the review of the described vintage if there is one, otherwise the most recent review on the page. Empty if none.
        - critic: the reviewer's name. drinkWindow: as printed, e.g. "2025-2040". Empty if missing.
        - note: the first two sentences of that tasting note, word for word. Empty if missing.
        """
        let prompt = "The wine:\n\(wine.fullDescription)\n\nPage text:\n\(String(text.prefix(40_000)))"
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "pageWine": ["type": "string"],
                "sameWine": ["type": "boolean"],
                "signedIn": ["type": "boolean"],
                "vintage": ["type": "string"],
                "score": ["type": "string"],
                "critic": ["type": "string"],
                "drinkWindow": ["type": "string"],
                "note": ["type": "string"]
            ],
            "required": ["pageWine", "sameWine", "signedIn", "vintage", "score", "critic", "drinkWindow", "note"],
            "additionalProperties": false
        ]
        struct Extracted: Decodable {
            var pageWine: String, sameWine: Bool, signedIn: Bool, vintage: String
            var score: String, critic: String, drinkWindow: String, note: String
        }
        let e = try await Claude.structured(Extracted.self, model: Claude.sonnet, system: system,
                                            content: [["type": "text", "text": prompt]], schema: schema,
                                            effort: "low", maxTokens: 6000)
        let usable = !e.score.isEmpty && (e.sameWine || trustPage)
        return VinousReview(found: usable, signedIn: e.signedIn, score: usable ? e.score : "",
                            critic: usable ? e.critic : "", drinkWindow: usable ? e.drinkWindow : "",
                            note: usable ? e.note : "", url: "", vintage: e.vintage, pageWine: e.pageWine)
    }

    /// Finds the wine's own page on Vinous with a web search limited to vinous.com.
    static func findPage(_ wine: WineDetails) async throws -> URL? {
        struct Found: Decodable { var url: String }
        let system = """
        Find the Vinous (vinous.com) wine page for the wine described. Wine pages look like https://vinous.com/wines/<name>.
        \(matchingRules)
        Prefer the page for the exact vintage. If that vintage has no page, use the most recent vintage of the same wine.
        If Vinous has no page for this exact wine, return an empty url; never return a different wine from the same producer.
        Finish your answer with only this JSON object: {"url":""}
        """
        let found = try await Claude.searchThenAnswer(Found.self, system: system,
                                                      prompt: "The wine:\n\(wine.fullDescription)",
                                                      allowedDomains: ["vinous.com"], maxSearches: 4)
        guard let url = URL(string: found.url), url.host()?.contains("vinous.com") == true,
              url.path().hasPrefix("/wines/") else { return nil }
        return url
    }
}

/// A hidden browser that opens a page with Ian's sign-ins and returns its text once it has loaded.
@MainActor
enum PageReader {
    static func text(of url: URL, timeout: Double = 25) async throws -> String {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 2000), configuration: config)
        webView.load(URLRequest(url: url))
        return try await settledText(of: webView, timeout: timeout)
    }

    /// Waits until the page has finished filling itself in, then returns its visible text.
    static func settledText(of webView: WKWebView, timeout: Double = 25) async throws -> String {
        let start = Date()
        var lastLength = -1
        var steady = 0
        var text = ""
        while Date().timeIntervalSince(start) < timeout {
            try await Task.sleep(for: .seconds(1))
            let ready = (try? await webView.evaluateJavaScript("document.readyState")) as? String
            text = ((try? await webView.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String) ?? ""
            let stillLoading = text.contains("Loading...") || text.contains("Loading…")
            if ready == "complete", !stillLoading, text.count == lastLength, text.count > 200 {
                steady += 1
                if steady >= 2 { return text }
            } else {
                steady = 0
            }
            lastLength = text.count
        }
        return text
    }
}
