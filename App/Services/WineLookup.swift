import SwiftUI
import UIKit

/// One wine being looked up: the label reading, New York prices and the Vinous score.
/// Used by the Scan tab and when adding a wine.
@MainActor
@Observable
final class WineLookup {
    enum Phase: Equatable {
        case reading
        case read
        case failed(String)
    }

    enum Step<Value: Equatable>: Equatable {
        case idle
        case working
        case done(Value)
        case failed(String)

        var value: Value? {
            switch self {
            case .done(let v): return v
            default: return nil
            }
        }
        var isWorking: Bool { self == .working }
    }

    var photo: UIImage?
    var typed: String?
    var phase: Phase = .reading
    var details: WineDetails?
    var prices: Step<PriceReport> = .idle
    var vinous: Step<VinousReview> = .idle

    init(photo: UIImage) { self.photo = photo }
    init(typed: String) { self.typed = typed }

    /// For screenshots and the self-check.
    init(details: WineDetails, prices: PriceReport?, vinous: VinousReview?) {
        self.details = details
        self.phase = .read
        if let prices { self.prices = .done(prices) }
        if let vinous { self.vinous = .done(vinous) }
    }

    func read() async {
        phase = .reading
        do {
            let result: WineDetails
            if let photo {
                result = try await LabelReader.read(photo: photo)
            } else {
                result = try await LabelReader.read(description: typed ?? "")
            }
            guard result.identified, !(result.producer.isEmpty && result.name.isEmpty) else {
                phase = .failed("Couldn't tell which wine this is. Try a sharper photo of the front label.")
                return
            }
            details = result
            phase = .read
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func checkPrices() async {
        guard let details else { return }
        prices = .working
        do {
            prices = .done(try await PriceChecker.check(details))
        } catch {
            prices = .failed(error.localizedDescription)
        }
    }

    func lookUpVinous() async {
        guard let details else { return }
        vinous = .working
        do {
            vinous = .done(try await Vinous.lookup(details))
        } catch {
            vinous = .failed(error.localizedDescription)
        }
    }

    /// Reads the label, then fetches prices and the Vinous score side by side.
    func runAll(prices wantPrices: Bool) async {
        await read()
        guard phase == .read else { return }
        await withTaskGroup(of: Void.self) { group in
            if wantPrices { group.addTask { await self.checkPrices() } }
            group.addTask { await self.lookUpVinous() }
        }
    }

    /// Makes a wine record from this lookup.
    func makeWine(status: WineStatus) -> Wine {
        let wine = Wine(status: status)
        if let details { wine.apply(details) }
        if let photo { wine.labelPhoto = LabelReader.thumbnail(photo) }
        if let p = prices.value { wine.applyPrices(p) }
        if let v = vinous.value, v.found { wine.applyVinous(v) }
        if status == .tasted { wine.drankOn = Date() }
        return wine
    }
}
