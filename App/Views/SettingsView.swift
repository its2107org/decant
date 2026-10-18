import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyText = ""
    @State private var hasKey = KeyStore.hasClaudeKey
    @State private var keyStatus: String?
    @State private var testing = false
    @State private var vinousSignedIn = Vinous.rememberedSignIn
    @State private var showVinous = false
    @AppStorage("autoPrices") private var autoPrices = true

    var body: some View {
        NavigationStack {
            Form {
                claudeSection
                vinousSection
                Section {
                    Toggle("Check prices when scanning", isOn: $autoPrices)
                } footer: {
                    Text("Each price check costs about 15 cents. Turn this off to check only when you tap.")
                }
                if let problem = AppState.shared.storageProblem {
                    Section("Storage problem") {
                        Text(problem).font(.footnote)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showVinous, onDismiss: { vinousSignedIn = Vinous.rememberedSignIn }) {
                VinousBrowserSheet(start: Vinous.signInURL)
            }
        }
    }

    private var claudeSection: some View {
        Section {
            if hasKey {
                LabeledContent("Claude key") {
                    Label("Added", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("Test the key")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(testing)
                Button("Remove key", role: .destructive) {
                    KeyStore.claudeKey = nil
                    hasKey = false
                    keyStatus = nil
                }
            } else {
                SecureField("Paste your Claude key", text: $keyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save key") {
                    KeyStore.claudeKey = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    keyText = ""
                    hasKey = KeyStore.hasClaudeKey
                    Task { await test() }
                }
                .disabled(keyText.trimmingCharacters(in: .whitespaces).count < 20)
            }
            if let keyStatus {
                Text(keyStatus).font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent("Spent this month", value: Spend.thisMonth.formatted(.currency(code: "USD")))
            Link("Claude account", destination: URL(string: "https://platform.claude.com/settings/billing")!)
        } header: {
            Text("Claude")
        } footer: {
            Text("Claude reads labels and checks prices. The key stays on this phone.")
        }
    }

    private var vinousSection: some View {
        Section {
            if vinousSignedIn {
                LabeledContent("Vinous") {
                    Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Button("Open Vinous") { showVinous = true }
                Button("Sign out of Vinous", role: .destructive) {
                    Task {
                        await Vinous.signOut()
                        vinousSignedIn = false
                    }
                }
            } else {
                Button("Sign in to Vinous") { showVinous = true }
            }
        } header: {
            Text("Vinous")
        } footer: {
            Text("Sign in once with your Vinous subscription. Decant uses it to show Vinous scores.")
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            try await Claude.checkKey()
            keyStatus = "The key works."
        } catch {
            keyStatus = error.localizedDescription
        }
    }

}
