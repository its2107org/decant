import SwiftUI

/// Every field of a wine, editable. Used when adding a wine and from the Edit button.
struct WineEditor: View {
    @Bindable var wine: Wine

    var body: some View {
        Form {
            if let data = wine.labelPhoto, let image = UIImage(data: data) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Wine") {
                LabeledTextField("Producer", text: $wine.producer)
                LabeledTextField("Wine", text: $wine.name)
                LabeledContent("Vintage") {
                    TextField("NV", value: $wine.vintage, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Type", selection: Binding(get: { wine.style }, set: { wine.style = $0 })) {
                    ForEach(WineStyle.allCases) { Text($0.label).tag($0) }
                }
                LabeledTextField("Grapes", text: Binding(
                    get: { wine.grapes.joined(separator: ", ") },
                    set: { wine.grapes = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
            }

            Section("Where it's from") {
                LabeledTextField("Country", text: $wine.country)
                LabeledTextField("Region", text: $wine.region)
                LabeledTextField("Sub-region", text: $wine.subregion)
                LabeledTextField("Appellation", text: $wine.appellation)
                LabeledTextField("Classification", text: $wine.classification)
            }

            if wine.status == .tasted {
                Section("Your score") {
                    ScoreEditor(score: $wine.myScore)
                    DatePicker("Drunk on", selection: Binding(get: { wine.drankOn ?? Date() }, set: { wine.drankOn = $0 }),
                               displayedComponents: .date)
                }
            }

            Section("Bought") {
                if wine.status == .cellar {
                    Stepper("Bottles: \(wine.bottles)", value: $wine.bottles, in: 1...240)
                }
                LabeledContent("Price paid") {
                    TextField("$", value: $wine.pricePaid, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledTextField("From", text: $wine.boughtFrom)
            }

            Section("Bottle") {
                LabeledContent("Alcohol") {
                    TextField("%", value: $wine.abv, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Size", selection: $wine.bottleSizeML) {
                    ForEach([375, 500, 750, 1500, 3000], id: \.self) { size in
                        Text(Self.sizeLabel(size)).tag(size)
                    }
                }
            }

            Section("Notes") {
                TextField("Notes", text: $wine.notes, axis: .vertical)
                    .lineLimit(3...10)
            }
        }
    }
}

extension WineEditor {
    static func sizeLabel(_ ml: Int) -> String {
        ml >= 1000 ? String(format: "%g litres", Double(ml) / 1000) : "\(ml)ml"
    }
}

struct LabeledTextField: View {
    let label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: $text)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Ian's score out of 100, with a big number and a slider.
struct ScoreEditor: View {
    @Binding var score: Int?

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ 100").foregroundStyle(.secondary)
                Spacer()
                if score != nil {
                    Button("Clear") { score = nil }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }
            }
            Slider(value: Binding(get: { Double(score ?? 90) }, set: { score = Int($0.rounded()) }),
                   in: 70...100, step: 1) {
                Text("Score")
            } minimumValueLabel: {
                Text("70").font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("100").font(.caption).foregroundStyle(.secondary)
            }
            .sensoryFeedback(.selection, trigger: score)
        }
        .padding(.vertical, 4)
    }
}
