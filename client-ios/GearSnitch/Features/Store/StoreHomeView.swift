import SwiftUI

struct StoreHomeView: View {
    @StateObject private var viewModel = StoreHomeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gsTextSecondary)

                TextField("Search products...", text: $viewModel.searchText)
                    .font(.subheadline)
                    .foregroundColor(.gsText)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gsTextSecondary)
                    }
                }
            }
            .padding(12)
            .background(Color.gsSurface)
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Category pills
            if !viewModel.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.categories, id: \.self) { category in
                            categoryPill(category)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }

            // Products grid
            if viewModel.isLoading && viewModel.products.isEmpty {
                Spacer()
                LoadingView(message: "Loading store...")
                Spacer()
            } else if viewModel.filteredProducts.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bag")
                        .font(.system(size: 40))
                        .foregroundColor(.gsTextSecondary)
                    Text("No products found")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(viewModel.filteredProducts) { product in
                            NavigationLink {
                                ProductDetailView(product: product)
                            } label: {
                                productCard(product)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Store")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    CartView()
                } label: {
                    Image(systemName: "cart")
                        .foregroundColor(.gsEmerald)
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                NavigationLink {
                    OrderHistoryView()
                } label: {
                    Label("Orders", systemImage: "shippingbox")
                }
            }
        }
        .task {
            await viewModel.loadProducts()
        }
    }

    // MARK: - Category Pill

    private func categoryPill(_ category: String) -> some View {
        let isSelected = viewModel.selectedCategory == category

        return Button {
            viewModel.selectCategory(category)
        } label: {
            Text(category.capitalized)
                .font(.caption.weight(.medium))
                .foregroundColor(isSelected ? .black : .gsText)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.gsEmerald : Color.gsSurface)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.clear : Color.gsBorder, lineWidth: 1)
                )
        }
    }

    // MARK: - Product Card

    private func productCard(_ product: ProductDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image placeholder
            ZStack {
                Color.gsSurfaceRaised
                Image(systemName: "cube.box.fill")
                    .font(.largeTitle)
                    .foregroundColor(.gsTextSecondary.opacity(0.5))
            }
            .frame(height: 120)
            .cornerRadius(10)

            Text(product.name)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
                .lineLimit(2)

            Text(product.formattedPrice)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.gsEmerald)

            if !product.inStock {
                Text("Out of Stock")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.gsDanger)
            }
        }
        .padding(10)
        .background(Color.gsSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        StoreHomeView()
    }
    .preferredColorScheme(.dark)
}
