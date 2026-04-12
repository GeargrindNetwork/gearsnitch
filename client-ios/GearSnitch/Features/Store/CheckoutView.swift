import PassKit
import SwiftUI

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss

    /// Cart data passed from CartView.
    let cartId: String
    let cartItems: [CartItemDTO]
    let subtotal: Double
    let tax: Double
    let shipping: Double
    let total: Double

    @StateObject private var applePayManager = ApplePayManager()

    @State private var fullName = ""
    @State private var addressLine1 = ""
    @State private var addressLine2 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var complianceAccepted = false
    @State private var error: String?
    @State private var checkoutNotice: String?
    @State private var orderPlaced = false
    @State private var confirmedOrderId: String?

    init(
        cartId: String = "",
        cartItems: [CartItemDTO] = [],
        subtotal: Double = 0,
        tax: Double = 0,
        shipping: Double = 0,
        total: Double = 0
    ) {
        self.cartId = cartId
        self.cartItems = cartItems
        self.subtotal = subtotal
        self.tax = tax
        self.shipping = shipping
        self.total = total
    }

    var body: some View {
        Form {
            // MARK: - Apple Pay Section

            if ApplePayManager.canMakePayments() {
                Section {
                    ApplePayButton(type: .checkout, style: .black) {
                        Task { await handleApplePay() }
                    }
                    .frame(height: 50)
                    .disabled(isProcessing || !complianceAccepted)
                    .opacity(complianceAccepted ? 1.0 : 0.5)
                } header: {
                    Text("Express Checkout")
                        .foregroundColor(.gsTextSecondary)
                }
                .listRowBackground(Color.gsSurface)

                // Separator
                Section {
                    HStack {
                        VStack { Divider().background(Color.gsBorder) }
                        Text("Or pay with card")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                            .layoutPriority(1)
                        VStack { Divider().background(Color.gsBorder) }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            // MARK: - Shipping Address

            Section {
                TextField("Full Name", text: $fullName)
                TextField("Address Line 1", text: $addressLine1)
                TextField("Address Line 2 (optional)", text: $addressLine2)
                TextField("City", text: $city)
                HStack {
                    TextField("State", text: $state)
                    TextField("ZIP", text: $zip)
                        .keyboardType(.numberPad)
                }
            } header: {
                Text("Shipping Address")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)
            .foregroundColor(.gsText)

            // MARK: - Compliance

            Section {
                Toggle(isOn: $complianceAccepted) {
                    Text("I acknowledge all applicable compliance requirements and age restrictions for the items in my cart.")
                        .font(.caption)
                        .foregroundColor(.gsText)
                }
                .tint(.gsEmerald)
            } header: {
                Text("Compliance")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                summaryRow("Subtotal", value: subtotal)
                summaryRow("Tax", value: tax)
                summaryRow("Shipping", value: shipping)
                summaryRow("Total", value: total)
            } header: {
                Text("Order Summary")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            if let checkoutNotice {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.gsWarning)
                            .padding(.top, 2)

                        Text(checkoutNotice)
                            .font(.caption)
                            .foregroundColor(.gsText)
                    }
                } header: {
                    Text("Card Checkout Status")
                        .foregroundColor(.gsTextSecondary)
                }
                .listRowBackground(Color.gsSurface)
            }

            // MARK: - Error

            if let error {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }
                .listRowBackground(Color.gsSurface)
            }

            // MARK: - Processing Indicator

            if case .processing = applePayManager.paymentStatus {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.gsEmerald)
                        Text("Processing payment...")
                            .font(.subheadline)
                            .foregroundColor(.gsTextSecondary)
                            .padding(.leading, 8)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.gsSurface)
            }

            // MARK: - Place Order Button

            Section {
                Button {
                    Task { await placeOrder() }
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "exclamationmark.bubble.fill")
                        Text("Card Checkout Coming Soon")
                            .font(.headline)
                        Spacer()
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 4)
                }
                .listRowBackground(isValid ? Color.gsEmerald : Color.gsTextSecondary)
                .disabled(!isValid || isProcessing)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Order Placed!", isPresented: $orderPlaced) {
            Button("OK") { dismiss() }
        } message: {
            if let orderId = confirmedOrderId {
                Text("Your order \(orderId) has been submitted and is being processed.")
            } else {
                Text("Your order has been submitted and is being processed.")
            }
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !fullName.isEmpty && !addressLine1.isEmpty && !city.isEmpty &&
        !state.isEmpty && !zip.isEmpty && complianceAccepted && !cartId.isEmpty
    }

    private var isProcessing: Bool {
        applePayManager.paymentStatus == .processing
    }

    // MARK: - Apple Pay

    private func handleApplePay() async {
        error = nil
        checkoutNotice = nil
        guard isValid else {
            error = "Complete your shipping details and compliance acknowledgement before paying."
            return
        }

        let shippingAddress = ShippingAddress(
            fullName: fullName,
            line1: addressLine1,
            line2: addressLine2.isEmpty ? nil : addressLine2,
            city: city,
            state: state,
            postalCode: zip
        )

        do {
            let orderId = try await applePayManager.startPayment(
                cartId: cartId,
                shippingAddress: shippingAddress,
                items: cartItems,
                subtotal: subtotal,
                tax: tax,
                shipping: shipping
            )
            confirmedOrderId = orderId
            orderPlaced = true
        } catch let applePayError as ApplePayError where applePayError == .cancelled {
            // User cancelled -- no error to show
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Standard Checkout

    private func placeOrder() async {
        error = nil
        checkoutNotice = """
        Card checkout is still being finalized in GearSnitch. Use Apple Pay on a supported device for now, or return to your cart and try again once manual checkout is live.
        """
    }

    @ViewBuilder
    private func summaryRow(_ label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gsTextSecondary)
            Spacer()
            Text(String(format: "$%.2f", value))
                .foregroundColor(label == "Total" ? .gsEmerald : .gsText)
        }
    }
}

// MARK: - ApplePayError Equatable

extension ApplePayError: Equatable {
    static func == (lhs: ApplePayError, rhs: ApplePayError) -> Bool {
        switch (lhs, rhs) {
        case (.controllerCreationFailed, .controllerCreationFailed),
             (.presentationFailed, .presentationFailed),
             (.cancelled, .cancelled):
            return true
        case (.backendConfirmationFailed(let a), .backendConfirmationFailed(let b)):
            return a == b
        default:
            return false
        }
    }
}

#Preview {
    NavigationStack {
        CheckoutView(
            cartId: "",
            cartItems: [],
            subtotal: 0,
            tax: 0,
            shipping: 0,
            total: 0
        )
    }
    .preferredColorScheme(.dark)
}
