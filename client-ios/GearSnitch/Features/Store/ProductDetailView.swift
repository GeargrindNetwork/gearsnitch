import SwiftUI

struct ProductDetailView: View {
    let product: ProductDTO
    @State private var isAddingToCart = false
    @State private var addedToCart = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image area
                TabView {
                    ForEach(0..<max(1, product.imageURLs?.count ?? 1), id: \.self) { index in
                        ZStack {
                            Color.gsSurfaceRaised
                            Image(systemName: "cube.box.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.gsTextSecondary.opacity(0.4))
                        }
                    }
                }
                .frame(height: 280)
                .tabViewStyle(.page)
                .cornerRadius(16)

                // Info
                VStack(alignment: .leading, spacing: 12) {
                    Text(product.name)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.gsText)

                    Text(product.formattedPrice)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.gsEmerald)

                    if !product.inStock {
                        Label("Out of Stock", systemImage: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.gsDanger)
                    }

                    Divider().background(Color.gsBorder)

                    Text(product.description)
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                        .lineSpacing(4)
                }

                // Compliance warnings
                if let warnings = product.complianceWarnings, !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Compliance", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gsWarning)

                        ForEach(warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundColor(.gsTextSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.gsWarning.opacity(0.08))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gsWarning.opacity(0.2), lineWidth: 1)
                    )
                }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }

                if addedToCart {
                    Label("Added to cart!", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsSuccess)
                        .transition(.opacity)
                }

                // Add to cart
                Button {
                    Task { await addToCart() }
                } label: {
                    HStack {
                        if isAddingToCart {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "cart.badge.plus")
                            Text("Add to Cart")
                                .font(.headline)
                        }
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(product.inStock ? Color.gsEmerald : Color.gsTextSecondary)
                    .cornerRadius(14)
                }
                .disabled(!product.inStock || isAddingToCart)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addToCart() async {
        isAddingToCart = true
        error = nil

        do {
            let _: EmptyData = try await APIClient.shared.request(
                APIEndpoint.Store.addToCart(productId: product.id)
            )
            withAnimation { addedToCart = true }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { addedToCart = false }
        } catch {
            self.error = error.localizedDescription
        }

        isAddingToCart = false
    }
}

#Preview {
    NavigationStack {
        ProductDetailView(product: ProductDTO(
            id: "1", name: "Tactical Lock Pro",
            description: "Heavy-duty BLE-enabled padlock with tamper detection and 12-month battery life.",
            price: 49.99, currency: "USD", category: "locks",
            imageURLs: nil, inStock: true,
            complianceWarnings: ["This product contains lithium batteries"],
            createdAt: Date()
        ))
    }
    .preferredColorScheme(.dark)
}
