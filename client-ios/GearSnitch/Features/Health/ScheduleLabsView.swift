import PassKit
import SwiftUI

// MARK: - Schedule Labs View

struct ScheduleLabsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ScheduleLabsViewModel()

    var body: some View {
        Group {
            if viewModel.isConfirmed {
                confirmationView
            } else {
                schedulingForm
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Schedule Labs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .alert("Payment Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "Something went wrong")
        }
    }

    // MARK: - Scheduling Form

    private var schedulingForm: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.gsCyan.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "staroflife.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.gsCyan)
                    }

                    Text("Blood Work")
                        .font(.title2.bold())
                        .foregroundColor(.gsText)

                    Text("Schedule your comprehensive blood panel at one of our designated provider locations.")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 16)

                // What's included card
                VStack(alignment: .leading, spacing: 10) {
                    Text("Comprehensive Panel Includes:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)

                    ForEach([
                        "Complete Blood Count (CBC)",
                        "Comprehensive Metabolic Panel (CMP)",
                        "Lipid Panel (Cholesterol, Triglycerides)",
                        "Testosterone (Total & Free)",
                        "Thyroid Panel (TSH, T3, T4)",
                        "Liver Function (AST, ALT)",
                        "Kidney Function (BUN, Creatinine)",
                        "Hemoglobin A1C",
                    ], id: \.self) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.gsEmerald)
                            Text(item)
                                .font(.caption)
                                .foregroundColor(.gsText.opacity(0.85))
                        }
                    }
                }
                .padding(16)
                .background(Color.gsSurface)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gsBorder, lineWidth: 1)
                )

                // Date & Time Picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Date & Time")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)

                    DatePicker(
                        "Appointment",
                        selection: $viewModel.selectedDate,
                        in: viewModel.dateRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .tint(.gsEmerald)
                    .colorScheme(.dark)
                }
                .padding(16)
                .background(Color.gsSurface)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gsBorder, lineWidth: 1)
                )

                // Price
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Blood Work Panel")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gsText)
                        Text("Results in 3-5 business days")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                    }

                    Spacer()

                    Text("$69.99")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.gsEmerald)
                }
                .padding(16)
                .background(Color.gsSurface)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gsEmerald.opacity(0.3), lineWidth: 1)
                )

                // Apple Pay button
                Button {
                    viewModel.initiateApplePay()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isProcessing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "apple.logo")
                                .font(.title3)
                            Text("Pay $69.99")
                                .font(.headline)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.black)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .disabled(viewModel.isProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Confirmation View

    private var confirmationView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.gsSuccess.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.gsSuccess)
            }

            Text("Appointment Scheduled!")
                .font(.title2.bold())
                .foregroundColor(.gsText)

            VStack(spacing: 8) {
                infoRow(label: "Date", value: viewModel.formattedDate)
                infoRow(label: "Time", value: viewModel.formattedTime)
                infoRow(label: "Location", value: viewModel.assignedLocation)
                infoRow(label: "Amount Paid", value: "$69.99")
            }
            .padding(16)
            .background(Color.gsSurface)
            .cornerRadius(14)
            .padding(.horizontal, 16)

            Text("Please fast for 8-12 hours before your appointment. Bring a valid photo ID.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.gsEmerald)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ScheduleLabsViewModel: NSObject, ObservableObject {
    @Published var selectedDate: Date = {
        // Default to next weekday at 9am
        let calendar = Calendar.current
        var date = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        while calendar.isDateInWeekend(date) {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }()

    @Published var isProcessing = false
    @Published var isConfirmed = false
    @Published var error: String?
    @Published var assignedLocation = ""

    private static let bloodworkProductId = "com.gearsnitch.app.bloodwork"
    private static let bloodworkPrice: NSDecimalNumber = 69.99
    private static let merchantId = "merchant.com.gearsnitch"

    var dateRange: ClosedRange<Date> {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let threeMonths = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        return tomorrow...threeMonths
    }

    var formattedDate: String {
        selectedDate.formatted(date: .abbreviated, time: .omitted)
    }

    var formattedTime: String {
        selectedDate.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Apple Pay

    func initiateApplePay() {
        guard PKPaymentAuthorizationViewController.canMakePayments() else {
            error = "Apple Pay is not available on this device."
            return
        }

        isProcessing = true

        let request = PKPaymentRequest()
        request.merchantIdentifier = Self.merchantId
        request.supportedNetworks = [.visa, .masterCard, .amex, .discover]
        request.merchantCapabilities = .threeDSecure
        request.countryCode = "US"
        request.currencyCode = "USD"

        request.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: "Blood Work Panel",
                amount: Self.bloodworkPrice
            ),
            PKPaymentSummaryItem(
                label: "GearSnitch",
                amount: Self.bloodworkPrice,
                type: .final
            ),
        ]

        guard let paymentController = PKPaymentAuthorizationViewController(paymentRequest: request) else {
            error = "Unable to present Apple Pay."
            isProcessing = false
            return
        }

        paymentController.delegate = self

        // Present the Apple Pay sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var presenter = rootVC
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            presenter.present(paymentController, animated: true)
        }
    }

    private func processPaymentOnBackend(token: PKPaymentToken) async -> Bool {
        do {
            let body = LabAppointmentBody(
                date: selectedDate.ISO8601Format(),
                paymentToken: token.paymentData.base64EncodedString(),
                productId: Self.bloodworkProductId
            )
            let response: LabAppointmentResponse = try await APIClient.shared.request(
                APIEndpoint.Labs.schedule(body: body)
            )
            assignedLocation = response.location
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

// MARK: - PKPaymentAuthorizationViewControllerDelegate

extension ScheduleLabsViewModel: PKPaymentAuthorizationViewControllerDelegate {

    nonisolated func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        Task { @MainActor in
            controller.dismiss(animated: true)
            if !isConfirmed {
                isProcessing = false
            }
        }
    }

    nonisolated func paymentAuthorizationViewController(
        _ controller: PKPaymentAuthorizationViewController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        Task { @MainActor in
            let success = await processPaymentOnBackend(token: payment.token)

            if success {
                isConfirmed = true
                isProcessing = false
                completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
            } else {
                completion(PKPaymentAuthorizationResult(
                    status: .failure,
                    errors: [NSError(domain: "com.gearsnitch", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: error ?? "Payment processing failed",
                    ])]
                ))
                isProcessing = false
            }
        }
    }
}

// MARK: - API Types

struct LabAppointmentBody: Encodable {
    let date: String
    let paymentToken: String
    let productId: String
}

struct LabAppointmentResponse: Decodable {
    let appointmentId: String
    let location: String
    let date: String
    let status: String
}

// MARK: - API Endpoint Extension

extension APIEndpoint {
    enum Labs {
        static func schedule(body: LabAppointmentBody) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/labs/schedule",
                method: .POST,
                body: body
            )
        }
    }
}

#Preview {
    NavigationStack {
        ScheduleLabsView()
    }
    .preferredColorScheme(.dark)
}
