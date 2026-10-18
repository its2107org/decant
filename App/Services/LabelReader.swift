import UIKit

/// Turns a label photo (or a typed description) into a standard wine record.
enum LabelReader {
    private static let system = """
    You catalogue wines for a private collector's cellar app. Identify the exact wine and fill in a standard record.

    Rules:
    - producer: the house or estate as it's normally written (e.g. "Domaine Marquis d'Angerville", "Ridge Vineyards").
    - name: the specific wine or cuvée without the producer or vintage (e.g. "Volnay 1er Cru Clos des Ducs", "Monte Bello"). Empty if the wine has no separate name.
    - vintage: the year, or null for non-vintage.
    - style: one of red, white, rose, sparkling, orange, sweet, fortified, other.
    - grapes: the grape varieties in normal English spelling. If the label doesn't say, use what the appellation requires or what the producer is known to use (e.g. Barolo → Nebbiolo; red Burgundy → Pinot Noir).
    - country, region, subregion, appellation: from broad to narrow, in normal English usage (e.g. France / Burgundy / Côte de Beaune / Volnay; USA / California / Napa Valley / Oakville). Leave a field empty rather than guess.
    - classification: e.g. "Premier Cru", "Grand Cru", "DOCG", "Grosses Gewächs", "Second wine". Empty if none.
    - abv: alcohol percentage if shown, else null. bottleSizeML: 750 unless the label or photo shows otherwise.
    - labelText: the main words on the label, as printed.
    - identified: false only if you can't tell what wine this is at all.
    Use UK English spelling in anything descriptive.
    """

    static func read(photo: UIImage) async throws -> WineDetails {
        guard let jpeg = prepared(photo) else { throw ClaudeError.unreadable }
        let content: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
            ["type": "text", "text": "Identify this wine from its label."]
        ]
        return try await Claude.structured(WineDetails.self, model: Claude.sonnet, system: system,
                                           content: content, schema: schema)
    }

    static func read(description: String) async throws -> WineDetails {
        let content: [[String: Any]] = [["type": "text", "text": "Identify this wine: \(description)"]]
        return try await Claude.structured(WineDetails.self, model: Claude.sonnet, system: system,
                                           content: content, schema: schema)
    }

    /// Shrinks the photo to the size Claude reads best (about 1,500 pixels on the long side).
    static func prepared(_ image: UIImage) -> Data? {
        let longest: CGFloat = 1568
        let size = image.size
        let scale = min(1, longest / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    /// A smaller copy kept with the wine record.
    static func thumbnail(_ image: UIImage) -> Data? {
        let longest: CGFloat = 900
        let size = image.size
        let scale = min(1, longest / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }.jpegData(compressionQuality: 0.75)
    }

    static let schema: [String: Any] = {
        let text: [String: Any] = ["type": "string"]
        func nullable(_ type: String) -> [String: Any] { ["anyOf": [["type": type], ["type": "null"]]] }
        let properties: [String: Any] = [
            "identified": ["type": "boolean"],
            "producer": text,
            "name": text,
            "vintage": nullable("integer"),
            "style": ["type": "string", "enum": WineStyle.allCases.map(\.rawValue)],
            "grapes": ["type": "array", "items": text],
            "country": text,
            "region": text,
            "subregion": text,
            "appellation": text,
            "classification": text,
            "abv": nullable("number"),
            "bottleSizeML": nullable("integer"),
            "labelText": text
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": Array(properties.keys).sorted(),
            "additionalProperties": false
        ]
    }()
}
