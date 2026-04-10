import SwiftUI

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var addressLine1 = ""
    @State private var addressLine2 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var complianceAccepted = false
    @State private var isPlacingOrder = false
    @State private var error: String?
    @State private var orderPlaced = false

    var body: some View {
        Form {
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

            if let error {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }
                .listRowBackground(Color.gsSurface)
            }

            Section {
                Button {
                    Task { await placeOrder() }
                } label: {
                    HStack {
                        Spacer()
                        if isPlacingOrder {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "bag.fill")
                            Text("Place Order")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 4)
                }
                .listRowBackground(isValid ? Color.gsEmerald : Color.gsTextSecondary)
                .disabled(!isValid || isPlacingOrder)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Order Placed!", isPresented: $orderPlaced) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your order has been submitted and is being processed.")
        }
    }

    private var isValid: Bool {
        !fullName.isEmpty && !addressLine1.isEmpty && !city.isEmpty &&
        !state.isEmpty && !zip.isEmpty && complianceAccepted
    }

    private func placeOrder() async {
        isPlacingOrder = true
        error = nil

        do {
            let _: EmptyData = try await APIClient.shared.request(APIEndpoint.Store.checkout)
            orderPlaced = true
        } catch {
            self.error = error.localizedDescription
        }

        isPlacingOrder = false
    }
}

#Preview {
    NavigationStack {
        CheckoutView()
    }
    .preferredColorScheme(.dark)
}
