import Foundation

/// Reading Vinous search results and matching them to a bottle. No network here, so it can be checked on the build machine.
enum VinousSearch {
    struct Entry: Equatable {
        var id: Int
        var producer: String
        var wine: String
        var vintage: Int
        var region: String
        var area: String = ""
        var country: String = ""
        var color: String
        var grapes: String
        var critic: String
        var score: String
        var drinkFrom: Int
        var drinkTo: Int
        var note: String
        var slug: String
        var reviewDate: String
        var articleDate: String = ""

        /// The same wine whatever the spelling, word order or accents: "Evesham Wood Vineyard · Pinot Noir Willamette Valley"
        /// and "Evesham Wood · Willamette Valley Pinot Noir" share a key.
        var key: String { VinousSearch.key(producer: producer, wine: wine) }

        var vintageText: String { vintage > 0 ? String(vintage) : "NV" }
        var title: String { "\(vintageText) \(wine)" }
        var url: URL? { URL(string: "https://vinous.com/wines/\(slug)") }
        var placeLine: String { [region, area, country].filter { !$0.isEmpty }.joined(separator: " · ") }
        var fullNote: String {
            note.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// The wine in Decant's own shape, for adding it to the Cellar or Tasted.
        var details: WineDetails {
            let grapeList = grapes.split(separator: ",").map {
                $0.replacingOccurrences(of: #"^\s*\d+(\.\d+)?\s*%\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            let place = region.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return WineDetails(identified: true, producer: producer, name: wine, vintage: vintage > 0 ? vintage : nil,
                               style: WineStyle(loose: color).rawValue, grapes: grapeList, country: country,
                               region: area.isEmpty ? (place.last ?? "") : area, subregion: place.count > 1 ? place.last ?? "" : "",
                               appellation: place.first ?? "", classification: "", abv: nil, bottleSizeML: nil, labelText: "")
        }

        var drinkWindow: String { drinkFrom > 0 && drinkTo > 0 ? "\(drinkFrom)-\(drinkTo)" : "" }

        func review(signedIn: Bool) -> VinousReview {
            let window = drinkWindow
            let year = vintageText
            return VinousReview(found: !score.isEmpty, signedIn: signedIn, score: score, critic: critic,
                                drinkWindow: window, note: score.isEmpty ? "" : VinousSearch.firstSentences(note),
                                url: url?.absoluteString ?? "", vintage: year, pageWine: title)
        }
    }

    /// Splits a typed search into words and a year: "evesham wood 2024" searches "evesham wood" in 2024.
    static func splitYear(_ text: String) -> (term: String, vintage: Int?) {
        guard let r = text.range(of: #"\b(19|20)\d\d\b"#, options: .regularExpression), let year = Int(text[r]) else {
            return (tidy(text), nil)
        }
        var rest = text
        rest.removeSubrange(r)
        return (tidy(rest), year)
    }

    static func entries(from data: Data) -> [Entry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wines = root["wines"] as? [[String: Any]] else { return [] }
        return wines.compactMap { hit in
            guard let s = hit["_source"] as? [String: Any], let id = int(s["id"]),
                  let slug = s["slug"] as? String, !slug.isEmpty else { return nil }
            let producer = (s["producer"] as? [String: Any])?["producer_name"] as? String ?? ""
            let name = [s["wine_name"] as? String, s["wine_name_2"] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            var score = scoreText(s["score"])
            if score.isEmpty { score = scoreText(s["score_raw"]) }
            return Entry(id: id, producer: tidy(producer), wine: tidy(name), vintage: int(s["vintage"]) ?? 0,
                         region: s["region_1"] as? String ?? "", area: s["region_2"] as? String ?? "",
                         country: s["country"] as? String ?? "", color: s["color"] as? String ?? "",
                         grapes: s["grape_variety"] as? String ?? "", critic: s["author"] as? String ?? "",
                         score: score, drinkFrom: int(s["drinking_window_begin"]) ?? 0,
                         drinkTo: int(s["drinking_window_end"]) ?? 0, note: s["tasting_note"] as? String ?? "",
                         slug: slug, reviewDate: s["review_date"] as? String ?? "",
                         articleDate: s["article_date"] as? String ?? "")
        }
    }

    /// What to type into Vinous search, most specific first. Vinous only returns wines containing
    /// every word, so a stray label word (say "Tinto") would hide the wine; the shorter searches catch that.
    static func terms(for wine: WineDetails) -> [String] {
        let producerWords = Set(words(wine.producer))
        let nameExtra = wine.name.split(separator: " ").filter { !producerWords.contains(fold(String($0))) }.joined(separator: " ")
        let core = wine.producer.split(separator: " ").map(String.init)
            .filter { !genericProducerWords.contains(fold($0)) && !isInitial($0) }.joined(separator: " ")
        var out: [String] = []
        for term in [[wine.producer, nameExtra].joined(separator: " "), wine.producer, core, wine.name] {
            let t = tidy(term.replacingOccurrences(of: #"\b(18|19|20)\d\d\b"#, with: "", options: .regularExpression))
            if t.count >= 3, !out.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { out.append(t) }
        }
        return out
    }

    /// Results whose producer and wine name use exactly the bottle's words.
    static func exactMatches(_ entries: [Entry], wine: WineDetails) -> [Entry] {
        let bottle = key(producer: wine.producer, wine: wine.name)
        guard !bottle.isEmpty else { return [] }
        return entries.filter { $0.key == bottle }
    }

    /// All the reviews of one wine and vintage in one answer: every scored review listed newest first,
    /// with the average as the score.
    static func combined(_ entries: [Entry], signedIn: Bool) -> VinousReview? {
        guard let best = bestReview(entries) else { return nil }
        var review = best.review(signedIn: signedIn)
        var items: [VinousReviewItem] = []
        for e in entries.filter({ !$0.score.isEmpty }).sorted(by: { $0.reviewDate > $1.reviewDate }) {
            let item = VinousReviewItem(score: e.score, critic: e.critic, date: e.articleDate,
                                        drinkWindow: e.drinkWindow, note: e.fullNote)
            if !items.contains(where: { $0.score == item.score && $0.critic == item.critic && $0.date == item.date }) {
                items.append(item)
            }
        }
        if items.count > 1 {
            review.reviews = items
            review.score = VinousReview.average(items.map(\.score))
            review.critic = "Average of \(items.count) reviews"
        }
        return review
    }

    /// Search results gathered into one row per wine and vintage.
    static func grouped(_ entries: [Entry]) -> [[Entry]] {
        var groups: [[Entry]] = []
        for e in entries {
            if let i = groups.firstIndex(where: { $0[0].key == e.key && $0[0].vintage == e.vintage }) { groups[i].append(e) }
            else { groups.append([e]) }
        }
        return groups
    }

    /// Of several reviews of the same wine, the newest one with a score.
    static func bestReview(_ entries: [Entry]) -> Entry? {
        entries.max { a, b in
            if a.score.isEmpty != b.score.isEmpty { return a.score.isEmpty }
            return a.reviewDate < b.reviewDate
        }
    }

    // MARK: - Words

    static let genericProducerWords: Set<String> = [
        "domaine", "domaines", "chateau", "maison", "vineyard", "vineyards", "winery", "wines", "wine", "estate",
        "estates", "cellars", "bodegas", "bodega", "weingut", "tenuta", "cantina", "azienda", "agricola",
        "famille", "family", "vignobles"
    ]
    private static let fillerWords: Set<String> = [
        "de", "du", "des", "la", "le", "les", "l", "d", "di", "del", "della", "dei", "da", "do", "y", "e", "et",
        "and", "the", "von", "van", "am", "im"
    ]

    /// Producer words without "Domaine", "Vineyards" and the like, plus the wine's own words, in any order.
    /// Words of the producer's name repeated in the wine's name are left out, so "Château Margaux, Château Margaux"
    /// and "Château Margaux" with no wine name match.
    static func key(producer: String, wine: String) -> String {
        let all = words(producer)
        let p = all.filter { !genericProducerWords.contains($0) && !isInitial($0) }
        let w = words(wine).filter { !all.contains($0) }
        return Set(p + w).sorted().joined(separator: " ")
    }

    /// Lower-case, accent-free words, leaving out filler words and "Grand Vin".
    static func words(_ text: String) -> [String] {
        let t = fold(text).replacingOccurrences(of: "grand vin", with: " ")
        return t.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !fillerWords.contains($0) }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
    }

    private static func isInitial(_ word: String) -> Bool {
        word.filter(\.isLetter).count == 1 && word.count <= 2
    }

    static func tidy(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    /// "92", "92-94" or "96+"; empty for a missing or hidden score.
    static func scoreText(_ value: Any?) -> String {
        var text = ""
        if let n = value as? NSNumber {
            text = n.doubleValue == n.doubleValue.rounded() ? String(n.intValue) : n.stringValue
        } else if let s = value as? String {
            text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let digits = text.filter(\.isNumber)
        return digits.isEmpty || Int(digits) == 0 ? "" : text
    }

    static func firstSentences(_ text: String, count: Int = 2) -> String {
        let plain = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        var sentences: [String] = []
        plain.enumerateSubstrings(in: plain.startIndex..., options: .bySentences) { s, _, _, stop in
            if let s { sentences.append(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if sentences.count >= count { stop = true }
        }
        return sentences.joined(separator: " ")
    }
}

extension VinousSearch.Entry: Identifiable {}
