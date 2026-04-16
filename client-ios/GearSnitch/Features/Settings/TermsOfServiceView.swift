import SwiftUI

struct TermsOfServiceView: View {
    @State private var content = ""
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading Terms of Service...")
            } else if let error {
                ErrorView(message: error) {
                    Task { await loadTerms() }
                }
            } else {
                ScrollView {
                    Text(content)
                        .font(.subheadline)
                        .foregroundColor(.gsText)
                        .padding(16)
                }
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadTerms()
        }
    }

    private func loadTerms() async {
        isLoading = true
        error = nil

        do {
            let response: TermsResponse = try await APIClient.shared.request(
                APIEndpoint(path: "/api/v1/content/terms")
            )
            content = response.content
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

private struct TermsResponse: Decodable {
    let content: String
}

#Preview {
    NavigationStack {
        TermsOfServiceView()
    }
    .preferredColorScheme(.dark)
}
