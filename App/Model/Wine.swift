import Foundation
import SwiftData

/// Where a wine sits in the app.
enum WineStatus: String, Codable, CaseIterable {
    case cellar   // owned, not yet opened
    case tasted   // drunk, with Ian's score
}

/// Red, white and so on. Stored as text so new kinds never break old records.
enum WineStyle: String, Codable, CaseIterable, Identifiable {
    case red, white, rose, sparkling, orange, sweet, fortified, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: "Red"
        case .white: "White"
        case .rose: "Rosé"
        case .sparkling: "Sparkling"
        case .orange: "Orange"
        case .sweet: "Sweet"
        case .fortified: "Fortified"
        case .other: "Other"
        }
    }

    init(loose text: String?) {
        let t = (text ?? "").lowercased()
        if t.contains("ros") { self = .rose }
        else if t.contains("spark") || t.contains("champ") { self = .sparkling }
        else { self = WineStyle(rawValue: t) ?? .other }
    }
}

@Model
final class Wine {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var statusRaw: String = WineStatus.cellar.rawValue

    // What the wine is (filled in from the label, all editable).
    var producer: String = ""
    var name: String = ""
    var vintage: Int?
    var styleRaw: String = WineStyle.red.rawValue
    var grapes: [String] = []
    var country: String = ""
    var region: String = ""
    var subregion: String = ""
    var appellation: String = ""
    var classification: String = ""
    var abv: Double?
    var bottleSizeML: Int = 750

    // Ian's own details.
    var bottles: Int = 1
    var pricePaid: Double?
    var boughtFrom: String = ""
    var boughtOn: Date?
    var drankOn: Date?
    var myScore: Int?
    var notes: String = ""

    // Vinous.
    var vinousScore: String = ""
    var vinousCritic: String = ""
    var vinousDrinkWindow: String = ""
    var vinousNote: String = ""
    var vinousURL: String = ""
    var vinousVintage: String = ""
    var vinousCheckedAt: Date?

    // New York prices from the last check.
    var nycLow: Double?
    var nycHigh: Double?
    var nycTypical: Double?
    var nycOffersData: Data?
    var nycCheckedAt: Date?

    @Attribute(.externalStorage) var labelPhoto: Data?

    init(status: WineStatus = .cellar) {
        self.statusRaw = status.rawValue
    }

    var status: WineStatus {
        get { WineStatus(rawValue: statusRaw) ?? .cellar }
        set { statusRaw = newValue.rawValue }
    }

    var style: WineStyle {
        get { WineStyle(rawValue: styleRaw) ?? .other }
        set { styleRaw = newValue.rawValue }
    }

    var vintageText: String { vintage.map(String.init) ?? "NV" }

    /// "Clos des Ducs 1er Cru 2019", or the producer alone when there's no separate wine name.
    var title: String {
        let main = name.isEmpty ? producer : name
        return "\(main) \(vintageText)"
    }

    var subtitle: String { name.isEmpty ? "" : producer }

    /// "Volnay · Burgundy · Pinot Noir"
    var placeAndGrapes: String {
        let place = [appellation.isEmpty ? subregion : appellation, region].filter { !$0.isEmpty }
        var seen = Set<String>()
        let parts = (place + [grapes.joined(separator: ", ")]).filter { !$0.isEmpty && seen.insert($0).inserted }
        return parts.joined(separator: " · ")
    }

    var nycOffers: [StoreOffer] {
        get { nycOffersData.flatMap { try? JSONDecoder().decode([StoreOffer].self, from: $0) } ?? [] }
        set { nycOffersData = try? JSONEncoder().encode(newValue) }
    }

    /// The best single number for sorting by Vinous score ("92-94" sorts as 93).
    var vinousSortValue: Double? { Wine.scoreValue(vinousScore) }

    static func scoreValue(_ text: String) -> Double? {
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }.filter { $0 >= 50 && $0 <= 100 }
        guard !numbers.isEmpty else { return nil }
        return numbers.reduce(0, +) / Double(numbers.count)
    }

    /// Fills in the wine's identity from what Claude read, leaving Ian's own details alone.
    func apply(_ d: WineDetails) {
        producer = d.producer
        name = d.name
        vintage = d.vintage
        style = WineStyle(loose: d.style)
        grapes = d.grapes
        country = d.country
        region = d.region
        subregion = d.subregion
        appellation = d.appellation
        classification = d.classification
        abv = d.abv
        if let size = d.bottleSizeML, size > 0 { bottleSizeML = size }
    }

    var details: WineDetails {
        WineDetails(identified: true, producer: producer, name: name, vintage: vintage, style: styleRaw,
                    grapes: grapes, country: country, region: region, subregion: subregion,
                    appellation: appellation, classification: classification, abv: abv,
                    bottleSizeML: bottleSizeML, labelText: "")
    }

    func applyPrices(_ p: PriceReport) {
        nycLow = p.low
        nycHigh = p.high
        nycTypical = p.typical
        nycOffers = p.offers
        nycCheckedAt = Date()
    }

    func applyVinous(_ v: VinousReview) {
        vinousScore = v.score
        vinousCritic = v.critic
        vinousDrinkWindow = v.drinkWindow
        vinousNote = v.note
        vinousURL = v.url
        vinousVintage = v.vintage
        vinousCheckedAt = Date()
    }

    /// Forgets a Vinous score (for example when a fresh look-up finds it was for a different wine).
    func clearVinous() {
        vinousScore = ""
        vinousCritic = ""
        vinousDrinkWindow = ""
        vinousNote = ""
        vinousURL = ""
        vinousVintage = ""
        vinousCheckedAt = Date()
    }

    /// True when the Vinous score is for another vintage of this wine.
    var vinousIsOtherVintage: Bool {
        guard !vinousScore.isEmpty, !vinousVintage.isEmpty else { return false }
        return vinousVintage != vintageText
    }

    /// The Vinous score to show in lists: only when it's for this exact bottle.
    var listVinousScore: String { vinousIsOtherVintage ? "" : vinousScore }

    /// A copy for "opened one bottle of several": same wine, now in Tasted.
    func tastedCopy() -> Wine {
        let w = Wine(status: .tasted)
        w.apply(details)
        w.bottleSizeML = bottleSizeML
        w.bottles = 1
        w.pricePaid = pricePaid
        w.boughtFrom = boughtFrom
        w.boughtOn = boughtOn
        w.vinousScore = vinousScore
        w.vinousCritic = vinousCritic
        w.vinousDrinkWindow = vinousDrinkWindow
        w.vinousNote = vinousNote
        w.vinousURL = vinousURL
        w.vinousVintage = vinousVintage
        w.vinousCheckedAt = vinousCheckedAt
        w.nycLow = nycLow
        w.nycHigh = nycHigh
        w.nycTypical = nycTypical
        w.nycOffersData = nycOffersData
        w.nycCheckedAt = nycCheckedAt
        w.labelPhoto = labelPhoto
        return w
    }
}
