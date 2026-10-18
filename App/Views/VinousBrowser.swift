import SwiftUI
import WebKit

/// A browser that shares Decant's Vinous sign-in.
struct VinousWebView: UIViewRepresentable {
    let start: URL
    @Binding var webView: WKWebView?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: start))
        DispatchQueue.main.async { webView = view }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// Vinous in a sheet. With a wine, it can take the score from whatever Vinous page is showing.
struct VinousBrowserSheet: View {
    let start: URL
    var wine: WineDetails?
    var onScore: ((VinousReview) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var webView: WKWebView?
    @State private var reading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VinousWebView(start: start, webView: $webView)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Vinous")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { finish() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { webView?.goBack() } label: { Label("Back", systemImage: "chevron.backward") }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if wine != nil {
                        VStack(spacing: 8) {
                            if let message {
                                Text(message).font(.footnote).foregroundStyle(.secondary)
                            }
                            Button {
                                Task { await useThisPage() }
                            } label: {
                                if reading {
                                    ProgressView().frame(maxWidth: .infinity)
                                } else {
                                    Label("Use the score on this page", systemImage: "rosette")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(reading || webView == nil)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.bar)
                    }
                }
        }
    }

    private func finish() {
        Task {
            if let webView, await Vinous.pageShowsSignedIn(webView) { Vinous.rememberedSignIn = true }
            dismiss()
        }
    }

    private func useThisPage() async {
        guard let webView, let wine else { return }
        reading = true
        message = nil
        defer { reading = false }
        do {
            let text = try await PageReader.settledText(of: webView, timeout: 8)
            var review = try await Vinous.extract(from: text, wine: wine, trustPage: true)
            review.url = webView.url?.absoluteString ?? ""
            if review.found {
                Vinous.rememberedSignIn = Vinous.rememberedSignIn || review.signedIn
                onScore?(review)
                dismiss()
            } else {
                message = review.signedIn ? "No score for this wine on this page." : "Sign in to Vinous to see scores."
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
