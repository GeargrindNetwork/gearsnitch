import SwiftUI

struct CartView: View {
    @StateObject private var viewModel = CartViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.cart == nil {
                LoadingView(message: "Loading cart...")
            } else if viewModel.isEmpty {
                emptyState
            } else {
                cartContent
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Cart")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadCart()
        }
    }

    // MARK: - Cart Content

    private var cartContent: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.items) { item in
                    cartItemRow(item)
                        .listRowBackground(Color.gsSurface)
                        .listRowSeparatorTint(Color.gsBorder)
                }
                .onDelete { offsets in
                    for offset in offsets {
                        let item = viewModel.items[offset]
                        Task { await viewModel.removeItem(productId: item.productId) }
                    }
                }
            }
            .listStyle(.plain)

            // Bottom bar
            VStack(spacing: 12) {
                HStack {
                    Text("Subtotal")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                    Spacer()
                    Text(viewModel.subtotal)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.gsText)
                }

                NavigationLink {
                    CheckoutView()
                } label: {
                    Text("Checkout")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.gsEmerald)
                        .cornerRadius(14)
                }
            }
            .padding(16)
            .background(Color.gsSurface)
        }
    }

    private func cartItemRow(_ item: CartItemDTO) -> some View {
        HStack(spacing: 14) {
            // Thumbnail
            ZStack {
                Color.gsSurfaceRaised
                Image(systemName: "cube.box.fill")
                    .foregroundColor(.gsTextSecondary.opacity(0.4))
            }
            .frame(width: 56, height: 56)
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)
                    .lineLimit(1)

                Text(item.formattedPrice)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer()

            // Quantity stepper
            HStack(spacing: 0) {
                Button {
                    let newQty = max(1, item.quantity - 1)
                    Task { await viewModel.updateQuantity(productId: item.productId, quantity: newQty) }
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gsText)
                        .frame(width: 30, height: 30)
                }

                Text("\(item.quantity)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)
                    .frame(width: 30)

                Button {
                    Task { await viewModel.updateQuantity(productId: item.productId, quantity: item.quantity + 1) }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gsText)
                        .frame(width: 30, height: 30)
                }
            }
            .background(Color.gsSurfaceRaised)
            .cornerRadius(8)

            Text(item.formattedLineTotal)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsEmerald)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .disabled(viewModel.isUpdating)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart")
                .font(.system(size: 48))
                .foregroundColor(.gsTextSecondary)

            Text("Your cart is empty")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text("Browse the store to add items.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        CartView()
    }
    .preferredColorScheme(.dark)
}
