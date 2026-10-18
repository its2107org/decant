import SwiftUI

/// A Vinous score with its critic and drinking window, or, when Vinous has several reviews
/// of the wine, their average followed by each review.
struct VinousScoreView: View {
    var score: String
    var critic: String
    var drinkWindow: String
    var note: String
    var reviews: [VinousReviewItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(score)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    if !critic.isEmpty { Text(critic).font(.subheadline.weight(.medium)) }
                    if reviews.count <= 1, !drinkWindow.isEmpty {
                        Text("Drink \(drinkWindow)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if reviews.count > 1 {
                ForEach(reviews, id: \.self) { item in
                    Divider()
                    VinousReviewRow(item: item)
                }
            } else if !note.isEmpty {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct VinousReviewRow: View {
    let item: VinousReviewItem
    var noteLines: Int? = 3

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.score)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(minWidth: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.critic.isEmpty ? "Vinous" : item.critic).font(.subheadline.weight(.medium))
                let detail = [item.date, item.drinkWindow.isEmpty ? "" : "Drink \(item.drinkWindow)"]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                if !item.note.isEmpty {
                    Text(item.note).font(.callout).foregroundStyle(.secondary).lineLimit(noteLines)
                }
            }
        }
    }
}
