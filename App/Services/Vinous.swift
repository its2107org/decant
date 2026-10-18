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
        guard let page = try await findPage(wine) else {
            return VinousReview(found: false, signedIn: rememberedSignIn, score: "", critic: "",
                                drinkWindow: "", note: "", url: "")
        }
        let text = try await PageReader.text(of: page)
        var review = try await extract(from: text, wine: wine)
        review.url = page.absoluteString
        rememberedSignIn = review.signedIn
        return review
    }

    /// Reads the score from text Ian already has open in the Vinous browser.
    static func extract(from text: String, wine: WineDetails) async throws -> VinousReview {
        let system = """
        You read the text of a Vinous (vinous.com) wine page for a subscriber and pull out the review.
        - found: true if the page has a Vinous score for this wine (the same wine; the vintage should match if one is given).
        - signedIn: false if the page asks to sign in or subscribe instead of showing reviews.
        - score: as printed, e.g. "94" or "92-94". If there are several reviews, use the most recent.
        - critic: the reviewer's name. drinkWindow: as printed, e.g. "2025-2040". Empty if missing.
        - note: the first two sentences of that tasting note, word for word. Empty if missing.
        """
        let prompt = "Wine: \(wine.searchName)\n\nPage text:\n\(String(text.prefix(40_000)))"
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "found": ["type": "boolean"],
                "signedIn": ["type": "boolean"],
                "score": ["type": "string"],
                "critic": ["type": "string"],
                "drinkWindow": ["type": "string"],
                "note": ["type": "string"]
            ],
            "required": ["found", "signedIn", "score", "critic", "drinkWindow", "note"],
            "additionalProperties": false
        ]
        struct Extracted: Decodable {
            var found: Bool, signedIn: Bool, score: String, critic: String, drinkWindow: String, note: String
        }
        let e = try await Claude.structured(Extracted.self, model: Claude.haiku, system: system,
                                            content: [["type": "text", "text": prompt]], schema: schema,
                                            effort: "low", maxTokens: 4000)
        return VinousReview(found: e.found && !e.score.isEmpty, signedIn: e.signedIn, score: e.score,
                            critic: e.critic, drinkWindow: e.drinkWindow, note: e.note, url: "")
    }

    /// Finds the wine's own page on Vinous with a web search limited to vinous.com.
    static func findPage(_ wine: WineDetails) async throws -> URL? {
        struct Found: Decodable { var url: String }
        let system = """
        Find the Vinous (vinous.com) wine page for the given wine. Wine pages look like https://vinous.com/wines/<name>.
        Prefer the exact vintage; if that vintage has no page, use the closest vintage of the same wine.
        Finish your answer with only this JSON object: {"url":""} (empty if there is no page for this wine).
        """
        let found = try await Claude.searchThenAnswer(Found.self, system: system,
                                                      prompt: "Wine: \(wine.searchName)",
                                                      allowedDomains: ["vinous.com"], maxSearches: 3)
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
