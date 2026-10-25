import PhotosUI
import SwiftUI
import UIKit

// MARK: - Formatting

enum Money {
    static func text(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(value.rounded() == value ? 0 : 2)))
    }

    static func range(_ low: Double?, _ high: Double?) -> String {
        guard let low, let high else { return Money.text(low ?? high) }
        return low == high ? Money.text(low) : "\(Money.text(low)) – \(Money.text(high))"
    }
}

extension WineStyle {
    var colour: Color {
        switch self {
        case .red: Color(red: 0.55, green: 0.11, blue: 0.23)
        case .white: Color(red: 0.93, green: 0.85, blue: 0.55)
        case .rose: Color(red: 0.95, green: 0.6, blue: 0.62)
        case .sparkling: Color(red: 0.9, green: 0.82, blue: 0.6)
        case .orange: Color(red: 0.88, green: 0.55, blue: 0.25)
        case .sweet: Color(red: 0.85, green: 0.65, blue: 0.2)
        case .fortified: Color(red: 0.42, green: 0.15, blue: 0.12)
        case .other: Color.gray
        }
    }
}

// MARK: - Pieces

/// The label photo, or a plain bottle in the wine's colour when there's no photo.
struct WineThumb: View {
    var photo: Data?
    var style: WineStyle
    var width: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    style.colour.opacity(0.18)
                    Image(systemName: "wineglass.fill")
                        .font(.system(size: width * 0.42))
                        .foregroundStyle(style.colour)
                }
            }
        }
        .frame(width: width, height: width * 1.3)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.08)))
    }
}

/// A score in a small capsule: "94", or "V 94" for Vinous.
struct ScoreBadge: View {
    var score: String
    var prefix: String?
    var prominent = false

    var body: some View {
        HStack(spacing: 3) {
            if let prefix {
                Text(prefix).font(.caption2.weight(.heavy)).opacity(0.75)
            }
            Text(score).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(prominent ? Color.white : Color.accentColor)
        .background(prominent ? Color.accentColor : Color.accentColor.opacity(0.12), in: Capsule())
    }
}

/// A rounded panel used on the detail and scan screens.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: systemImage ?? "")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct VerdictPill: View {
    var verdict: PriceReport.Verdict

    var colour: Color {
        switch verdict {
        case .good: .green
        case .fair: .orange
        case .high: .red
        }
    }

    var icon: String {
        switch verdict {
        case .good: "checkmark.circle.fill"
        case .fair: "equal.circle.fill"
        case .high: "exclamationmark.circle.fill"
        }
    }

    var body: some View {
        Label(verdict.label, systemImage: icon)
            .font(.headline)
            .foregroundStyle(colour)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(colour.opacity(0.14), in: Capsule())
    }
}

/// A list of New York shop prices with links.
struct OffersList: View {
    var offers: [StoreOffer]
    var limit = 15

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(offers.prefix(limit).enumerated()), id: \.element.id) { index, offer in
                if index > 0 { Divider() }
                let row = HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(offer.store).font(.subheadline.weight(.medium))
                        let extra = [offer.vintage, offer.bottleSize == "750ml" ? "" : offer.bottleSize].filter { !$0.isEmpty }
                        if !extra.isEmpty {
                            Text(extra.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(Money.text(offer.price)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    if URL(string: offer.url) != nil, !offer.url.isEmpty {
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                if let url = URL(string: offer.url), !offer.url.isEmpty {
                    Link(destination: url) { row }.buttonStyle(.plain)
                } else {
                    row
                }
            }
        }
    }
}

/// Small grey line of info, e.g. "Checked 2 Oct".
struct Footnote: View {
    var text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - Camera

/// The system camera, for photographing a label.
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) } else { parent.onCancel() }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

extension PhotosPickerItem {
    func loadImage() async -> UIImage? {
        guard let data = try? await loadTransferable(type: Data.self) else { return nil }
        return UIImage(data: data)
    }
}
