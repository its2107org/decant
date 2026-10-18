import Foundation
import WebKit

enum VinousError: LocalizedError {
    case searchFailed(Int)
    var errorDescription: String? {
        if case .searchFailed(let status) = self { return "Vinous search didn't answer (error \(status)). Try again shortly." }
        return nil
    }
}

/// Looks wines up on Vinous using Ian's own signed-in Vinous account.
///
/// Vinous has no public way for apps to read scores, so Decant does what Ian would do by hand:
/// it searches Vinous with his sign-in, picks the exact wine and vintage from the results, and
/// if the score isn't in the results it reads that wine's page in a hidden browser.
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

    /// Finds the wine with Vinous's own search (the same one behind the search box on vinous.com),
    /// keeps only reviews of the bottle's exact vintage, and picks the entry for this exact wine.
    static func lookup(_ wine: WineDetails) async throws -> VinousReview {
        let signedIn = await sessionIsSignedIn()
        let notFound = VinousReview(found: false, signedIn: signedIn || rememberedSignIn, score: "", critic: "",
                                    drinkWindow: "", note: "", url: searchURL(for: wine).absoluteString)
        let vintage = wine.vintage ?? 0
        var candidates: [VinousSearch.Entry] = []
        for term in VinousSearch.terms(for: wine) {
            let found = try await search(term: term, vintage: vintage)
            for entry in found where entry.vintage == vintage && !candidates.contains(where: { $0.id == entry.id }) {
                candidates.append(entry)
            }
            if !VinousSearch.exactMatches(candidates, wine: wine).isEmpty { break }
        }
        if signedIn { rememberedSignIn = true }
        guard !candidates.isEmpty else { return notFound }

        var chosen = VinousSearch.exactMatches(candidates, wine: wine)
        if chosen.isEmpty {
            chosen = try await pick(from: candidates, wine: wine)
        }
        guard let entry = VinousSearch.bestReview(chosen) else { return notFound }
        var review = entry.review(signedIn: signedIn || rememberedSignIn)
        if review.score.isEmpty, let page = URL(string: review.url) {
            // The search gave the right page but not the score; read the page itself with Ian's sign-in.
            let text = try await PageReader.text(of: page)
            var fromPage = try await extract(from: text, wine: wine, trustPage: true)
            if fromPage.signedIn { rememberedSignIn = true }
            if fromPage.found {
                fromPage.url = review.url
                if fromPage.drinkWindow.isEmpty { fromPage.drinkWindow = review.drinkWindow }
                if fromPage.critic.isEmpty { fromPage.critic = review.critic }
                fromPage.vintage = review.vintage
                fromPage.pageWine = review.pageWine
                return fromPage
            }
            review.signedIn = fromPage.signedIn
        }
        return review
    }

    /// Vinous's search page for this wine, for "Open on Vinous" when there's no review yet.
    static func searchURL(for wine: WineDetails) -> URL {
        var c = URLComponents(string: "https://vinous.com/wines")!
        c.queryItems = [URLQueryItem(name: "filters", value: ""),
                        URLQueryItem(name: "term", value: VinousSearch.terms(for: wine).first ?? wine.producer),
                        URLQueryItem(name: "page", value: "1")]
        return c.url ?? searchURL
    }

    private static func search(term: String, vintage: Int) async throws -> [VinousSearch.Entry] {
        let (data, status) = try await get("/api/v2/wines", [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "vintage", value: String(vintage)),
            URLQueryItem(name: "order", value: ""),
            URLQueryItem(name: "order_type", value: "desc"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "100")
        ])
        guard status == 200 else { throw VinousError.searchFailed(status) }
        return VinousSearch.entries(from: data)
    }

    private static func sessionIsSignedIn() async -> Bool {
        (try? await get("/api/v2/sessions/current", []))?.1 == 200
    }

    /// Calls Vinous with the sign-in Ian made in Decant's Vinous browser.
    private static func get(_ path: String, _ query: [URLQueryItem]) async throws -> (Data, Int) {
        var c = URLComponents(string: "https://vinous.com" + path)!
        if !query.isEmpty { c.queryItems = query }
        var request = URLRequest(url: c.url!, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            .filter { $0.domain.hasSuffix("vinous.com") }
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpShouldHandleCookies = false
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Asks Claude which search result is the bottle, when the names don't line up word for word.
    private static func pick(from candidates: [VinousSearch.Entry], wine: WineDetails) async throws -> [VinousSearch.Entry] {
        var groups: [[VinousSearch.Entry]] = []
        for entry in candidates {
            if let i = groups.firstIndex(where: { $0[0].key == entry.key }) { groups[i].append(entry) } else { groups.append([entry]) }
        }
        let list = groups.prefix(60).enumerated().map { i, group in
            let e = group[0]
            return "\(i). Producer: \(e.producer) | Wine: \(e.wine) | Region: \(e.region) | Colour: \(e.color) | Grapes: \(e.grapes)"
        }.joined(separator: "\n")
        let system = """
        You match a wine bottle to Vinous (vinous.com) search results. All results are already the right vintage.
        \(matchingRules)
        - Producer names may be written differently (e.g. "R. López de Heredia" and "Lopez de Heredia", or "Evesham Wood Vineyard" and "Evesham Wood"). Vinous sometimes adds a first name or "Vineyard" to the same producer, but separate houses sharing a family name are different producers (e.g. Domaine Leflaive and Maison Olivier Leflaive).
        - Word order and accents don't matter. Words such as "Tinto", "Grand Vin" or "Brut" on a label may be missing from Vinous's name.
        Answer with the number of the result that is this exact wine, or -1 if none is.
        """
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["choice": ["type": "integer"]],
            "required": ["choice"],
            "additionalProperties": false
        ]
        struct Choice: Decodable { var choice: Int }
        let answer = try await Claude.structured(Choice.self, model: Claude.sonnet, system: system,
                                                 content: [["type": "text", "text": "The bottle:\n\(wine.fullDescription)\n\nResults:\n\(list)"]],
                                                 schema: schema, effort: "low", maxTokens: 2000)
        guard groups.indices.contains(answer.choice), answer.choice < 60 else { return [] }
        return groups[answer.choice]
    }

    private static let matchingRules = """
    Matching rules (strict):
    - Same producer AND the same wine: the same cuvée, vineyard, appellation or AVA designation and colour.
    - A producer's other wines are different wines, even with the same grape. For example "Willamette Valley Pinot Noir" and "Pinot Noir Eola-Amity Hills Cuvée" are different wines; so are a "Reserve", a single-vineyard bottling, a second wine or a different appellation.
    - The vintage must match exactly. Another vintage of the same wine does not count.
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
        - If the page lists several wines, use only the one that is the wine described.
        - score: as printed, e.g. "94" or "92-94", from a review of exactly the described vintage. Empty if the page has no review of that vintage, or if the score is hidden (shown as "00" or behind "Subscriber Access Only").
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
        var review = VinousReview(found: false, signedIn: e.signedIn, score: "", critic: "", drinkWindow: "",
                                  note: "", url: "", vintage: e.vintage, pageWine: e.pageWine)
        let usable = !e.score.isEmpty && (trustPage || (e.sameWine && review.isSameVintage(as: wine)))
        if usable {
            review.found = true
            review.score = e.score
            review.critic = e.critic
            review.drinkWindow = e.drinkWindow
            review.note = e.note
        }
        return review
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
