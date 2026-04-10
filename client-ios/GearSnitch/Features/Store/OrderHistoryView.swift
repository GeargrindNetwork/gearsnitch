import SwiftUI

// MARK: - Order DTO

struct OrderDTO: Identifiable, Decodable {
    let id: String
    let status: String
    let total: Double
    let currency: String
    let itemCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status, total, currency, itemCount, createdAt
    }

    var formattedTotal: String {
        String(format: "$%.2f", total)
    }

    var statusIcon: String {
        switch status {
        case "pending": return "clock"
        case "processing": return "gearshape.2"
        case "shipped": return "shippingbox"
        case "delivered": return "checkmark.circle.fill"
        case "cancelled": return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - View

struct OrderHistoryView: View {
    @State private var orders: [OrderDTO] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && orders.isEmpty {
                LoadingView(message: "Loading orders...")
            } else if orders.isEmpty {
                emptyState
            } else {
                orderList
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Orders")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadOrders()
        }
    }

    private var orderList: some View {
        List {
            ForEach(orders) { order in
                orderRow(order)
                    .listRowBackground(Color.gsSurface)
                    .listRowSeparatorTint(Color.gsBorder)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await loadOrders()
        }
    }

    private func orderRow(_ order: OrderDTO) -> some View {
        HStack(spacing: 14) {
            Image(systemName: order.statusIcon)
                .font(.title3)
                .foregroundColor(statusColor(order.status))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text("Order #\(order.id.prefix(8))")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                Text("\(order.itemCount) item\(order.itemCount == 1 ? "" : "s") - \(order.createdAt.shortDateString())")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(order.formattedTotal)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)

                statusBadge(order.status)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundColor(statusColor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.12))
            .cornerRadius(4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "delivered": return .gsSuccess
        case "shipped": return .gsCyan
        case "processing": return .gsEmerald
        case "pending": return .gsWarning
        case "cancelled": return .gsDanger
        default: return .gsTextSecondary
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundColor(.gsTextSecondary)

            Text("No Orders Yet")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text("Your order history will appear here.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadOrders() async {
        isLoading = true
        error = nil

        do {
            let endpoint = APIEndpoint(path: "/api/v1/store/orders")
            let fetched: [OrderDTO] = try await APIClient.shared.request(endpoint)
            orders = fetched
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        OrderHistoryView()
    }
    .preferredColorScheme(.dark)
}
