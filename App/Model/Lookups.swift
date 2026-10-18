import Foundation

/// A wine's identity in a standard shape, as read from a label (or typed in) by Claude.
struct WineDetails: Codable, Equatable {
    var identified: Bool
    var producer: String
    var name: String
    var vintage: Int?
    var style: String
    var grapes: [String]
    var country: String
    var region: String
    var subregion: String
    var appellation: String
    var classification: String
    var abv: Double?
    var bottleSizeML: Int?
    var labelText: String

    /// How the wine is searched for: "Domaine Marquis d'Angerville Volnay Clos des Ducs 1er Cru 2019".
    var searchName: String {
        var parts = [producer]
        if !name.isEmpty, !producer.localizedCaseInsensitiveContains(name) { parts.append(name) }
        if let vintage { parts.append(String(vintage)) }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var nameWithoutVintage: String {
        [producer, name].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// One shop's price for the wine.
struct StoreOffer: Codable, Equatable, Identifiable, Hashable {
    var store: String
    var price: Double
    var vintage: String
    var bottleSize: String
    var url: String

    var id: String { store + url + String(price) }
}

/// What a New York price check found.
struct PriceReport: Codable, Equatable {
    var offers: [StoreOffer]
    var low: Double?
    var high: Double?
    var typical: Double?
    var note: String

    enum Verdict: String {
        case good, fair, high

        var label: String {
            switch self {
            case .good: "Good price"
            case .fair: "Fair price"
            case .high: "On the high side"
            }
        }
    }

    /// Compares a shelf price with what New York shops charge.
    func verdict(for shelfPrice: Double) -> Verdict? {
        guard let typical, typical > 0 else { return nil }
        let floor = low ?? typical
        if shelfPrice <= max(floor, typical * 0.95) { return .good }
        if shelfPrice <= typical * 1.10 { return .fair }
        return .high
    }
}

/// A Vinous review as shown on Vinous to a signed-in subscriber.
struct VinousReview: Codable, Equatable {
    var found: Bool
    var signedIn: Bool
    var score: String
    var critic: String
    var drinkWindow: String
    var note: String
    var url: String
}
