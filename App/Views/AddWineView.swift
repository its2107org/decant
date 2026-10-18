import SwiftData
import SwiftUI

enum AddSource: Identifiable {
    case camera
    case photo(UIImage)
    case typed

    var id: String {
        switch self {
        case .camera: "camera"
        case .photo: "photo"
        case .typed: "typed"
        }
    }
}

/// Adds a wine to the Cellar or Tasted: photo or typed name → Claude reads it → check and save.
struct AddWineView: View {
    let source: AddSource
    let status: WineStatus

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var lookup: WineLookup?
    @State private var draft: Wine?
    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(status == .cellar ? "Add to Cellar" : "Add to Tasted")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    if let draft {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { save(draft) }
                                .disabled(draft.producer.isEmpty && draft.name.isEmpty)
                        }
                    }
                }
        }
        .onAppear {
            if case .photo(let image) = source, lookup == nil { start(WineLookup(photo: image)) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let draft {
            WineEditor(wine: draft)
        } else if let lookup {
            ReadingView(lookup: lookup, tryAgain: { start(lookup) }, startOver: { self.lookup = nil })
        } else if case .camera = source {
            CameraPicker(onPick: { start(WineLookup(photo: $0)) }, onCancel: { dismiss() })
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
        } else {
            typeIn
        }
    }

    private var typeIn: some View {
        Form {
            Section {
                TextField("e.g. 2019 d'Angerville Volnay Clos des Ducs", text: $typed, axis: .vertical)
                    .focused($typing)
                    .submitLabel(.search)
                    .onSubmit(lookUpTyped)
            } footer: {
                Text("Producer, wine and year is enough. Claude fills in the rest.")
            }
            Section {
                Button("Look it up", action: lookUpTyped)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).count < 3)
            }
        }
        .onAppear { typing = true }
    }

    private func lookUpTyped() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        start(WineLookup(typed: text))
    }

    private func start(_ newLookup: WineLookup) {
        lookup = newLookup
        Task {
            await newLookup.read()
            guard newLookup.phase == .read else { return }
            draft = newLookup.makeWine(status: status)
            // Look up the Vinous score in the background; it's added to the wine when it arrives.
            await newLookup.lookUpVinous()
            if let review = newLookup.vinous.value, review.found, let draft {
                draft.applyVinous(review)
            }
        }
    }

    private func save(_ wine: Wine) {
        if status == .tasted, wine.drankOn == nil { wine.drankOn = Date() }
        context.insert(wine)
        try? context.save()
        dismiss()
    }
}

/// The photo with a progress message while Claude reads it, or what went wrong.
struct ReadingView: View {
    let lookup: WineLookup
    var tryAgain: () -> Void
    var startOver: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if let photo = lookup.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .opacity(lookup.phase == .reading ? 0.6 : 1)
            }
            switch lookup.phase {
            case .reading:
                ProgressView {
                    Text(lookup.photo == nil ? "Looking it up…" : "Reading the label…")
                }
            case .failed(let message):
                VStack(spacing: 14) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .multilineTextAlignment(.center)
                    HStack {
                        Button("Try again", action: tryAgain)
                            .buttonStyle(.borderedProminent)
                        Button("Start over", action: startOver)
                            .buttonStyle(.bordered)
                    }
                }
            case .read:
                EmptyView()
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
