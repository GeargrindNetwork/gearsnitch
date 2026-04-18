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
        .sheet(isPresented: $viewModel.showUnavailableSheet) {
            LabsUnavailableView(stateCode: viewModel.selectedState)
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

                // Shipping State (eligibility gate)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Shipping State")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)

                    Text("Enter the 2-letter state code for your shipping address.")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)

                    TextField("e.g. CA", text: $viewModel.selectedState)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .font(.body.weight(.medium))
                        .foregroundColor(.gsText)
                        .padding(12)
                        .background(Color.gsBackground)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(viewModel.isStateRestricted ? Color.gsDanger : Color.gsBorder, lineWidth: 1)
                        )
                        .onChange(of: viewModel.selectedState) { _, newValue in
                            // Clamp to 2 chars, uppercase — keeps input canonical.
                            let trimmed = newValue
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .uppercased()
                            let clamped = String(trimmed.prefix(2))
                            if clamped != newValue {
                                viewModel.selectedState = clamped
                            }
                        }

                    if viewModel.isStateRestricted {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.gsDanger)
                            Text("Not available in \(viewModel.selectedState) due to state regulations.")
                                .font(.caption)
                                .foregroundColor(.gsDanger)
                        }
                    }
                }
                .padding(16)
                .background(Color.gsSurface)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(viewModel.isStateRestricted ? Color.gsDanger.opacity(0.5) : Color.gsBorder, lineWidth: 1)
                )

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
                    viewModel.attemptSubmit()
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
                    .opacity(viewModel.canSubmit ? 1 : 0.5)
                }
                .disabled(!viewModel.canSubmit)
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

    /// USPS 2-letter state code for the user's shipping address.
    /// Kept as canonical uppercase by the view's onChange clamp.
    @Published var selectedState: String = ""

    /// Drives presentation of `LabsUnavailableView` when a restricted state
    /// is entered and the user attempts to pay.
    @Published var showUnavailableSheet: Bool = false

    /// `true` when the current `selectedState` is in the restricted list.
    /// Used for inline validation styling and as part of `canSubmit`.
    var isStateRestricted: Bool {
        guard !selectedState.isEmpty else { return false }
        return LabsStateEligibility.isRestricted(selectedState)
    }

    /// Controls whether the Pay button is tappable. We keep the button
    /// tappable for restricted states so `attemptSubmit()` can present the
    /// `LabsUnavailableView` explainer sheet. We only block taps while
    /// mid-payment or when no valid 2-letter state has been entered.
    var canSubmit: Bool {
        guard !isProcessing else { return false }
        let normalized = selectedState.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.count == 2
    }

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

    // MARK: - Submit Gate

    /// Entry point for the primary Pay button. Enforces the state eligibility
    /// gate before handing off to Apple Pay. If the user's shipping state is
    /// on the restricted list (NY/NJ/RI per Rupa Health), we present an
    /// explainer sheet and do NOT initiate payment.
    func attemptSubmit() {
        if LabsStateEligibility.isRestricted(selectedState) {
            showUnavailableSheet = true
            return
        }
        initiateApplePay()
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

        // MARK: Provider-backed endpoints (LabProvider abstraction)

        static var tests: APIEndpoint {
            APIEndpoint(path: "/api/v1/labs/tests")
        }

        static func drawSites(zip: String, radius: Int? = nil) -> APIEndpoint {
            var queryItems: [URLQueryItem] = [URLQueryItem(name: "zip", value: zip)]
            if let radius {
                queryItems.append(URLQueryItem(name: "radius", value: "\(radius)"))
            }
            return APIEndpoint(path: "/api/v1/labs/draw-sites", queryItems: queryItems)
        }

        static func createOrder(body: CreateLabOrderBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/labs/orders", method: .POST, body: body)
        }

        static func orderStatus(orderId: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/labs/orders/\(orderId)")
        }

        static func orderResults(orderId: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/labs/orders/\(orderId)/results")
        }

        static func cancelOrder(orderId: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/labs/orders/\(orderId)/cancel", method: .POST)
        }
    }
}

// MARK: - Provider-backed Lab Types
//
// These types mirror the TypeScript `LabProvider` shapes in
// api/src/modules/labs/providers/types.ts. Keep the two in sync.
//
// PHI note: the patient-identity fields below are HIPAA-scoped. Do NOT log
// instances of `LabPatientBody` or `LabOrder` bodies to OSLog — the
// existing `APIClient` redacts paths but not bodies.

struct LabTestCatalogItem: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let priceCents: Int
    let currency: String
    let turnaroundHours: Int
    let collectionMethods: [String]
    let fastingRequired: Bool
}

struct LabTestsResponse: Decodable {
    let provider: String
    let tests: [LabTestCatalogItem]
}

struct LabDrawSiteAddress: Decodable, Hashable {
    let line1: String
    let line2: String?
    let city: String
    let state: String
    let postalCode: String
}

struct LabDrawSite: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let address: LabDrawSiteAddress
    let phone: String?
    let hours: String?
    let distanceMiles: Double?
}

struct LabDrawSitesResponse: Decodable {
    let provider: String
    let sites: [LabDrawSite]
}

struct LabPatientAddressBody: Encodable {
    let line1: String
    let line2: String?
    let city: String
    let state: String
    let postalCode: String
}

/// @phi — patient identity. Do not persist or log beyond the active request.
struct LabPatientBody: Encodable {
    let firstName: String
    let lastName: String
    /// YYYY-MM-DD
    let dateOfBirth: String
    /// "male" | "female" | "unknown"
    let sexAtBirth: String
    let email: String
    let phone: String
    let address: LabPatientAddressBody
}

struct CreateLabOrderBody: Encodable {
    let testIds: [String]
    /// "phlebotomy_site" | "mobile_phleb" | "self_collect"
    let collectionMethod: String
    let drawSiteId: String?
    let preferredDateTime: String?
    let patient: LabPatientBody
}

struct LabOrderResponse: Decodable {
    let orderId: String
    let status: String
    let externalRef: String?
    let requisitionUrl: String?
}

struct CreateLabOrderResponse: Decodable {
    let provider: String
    let order: LabOrderResponse
}

// MARK: - Provider-backed ViewModel

/// ViewModel for the tests-catalog + draw-site + order flow backed by the
/// `LabProvider` abstraction. Kept deliberately simple so it can be unit
/// tested without presenting SwiftUI views.
@MainActor
final class LabProviderViewModel: ObservableObject {
    @Published var tests: [LabTestCatalogItem] = []
    @Published var drawSites: [LabDrawSite] = []
    @Published var selectedTestIds: Set<String> = []
    @Published var selectedDrawSiteId: String?
    @Published var zip: String = ""
    @Published var errorMessage: String?
    @Published var isLoadingTests = false
    @Published var isLoadingSites = false
    @Published var isSubmitting = false
    @Published var confirmedOrderId: String?

    private let client: LabProviderAPI

    init(client: LabProviderAPI = LiveLabProviderAPI()) {
        self.client = client
    }

    // MARK: Computed

    var totalPriceCents: Int {
        tests
            .filter { selectedTestIds.contains($0.id) }
            .reduce(0) { $0 + $1.priceCents }
    }

    var canSubmitOrder: Bool {
        !selectedTestIds.isEmpty && selectedDrawSiteId != nil && !isSubmitting
    }

    // MARK: Actions

    func loadTests() async {
        isLoadingTests = true
        defer { isLoadingTests = false }
        do {
            let response = try await client.fetchTests()
            tests = response.tests
        } catch {
            errorMessage = Self.sanitize(error)
        }
    }

    func loadDrawSites() async {
        guard Self.isValidZip(zip) else {
            errorMessage = "Enter a valid 5-digit ZIP code."
            return
        }
        isLoadingSites = true
        defer { isLoadingSites = false }
        do {
            let response = try await client.fetchDrawSites(zip: zip, radius: 25)
            drawSites = response.sites
            if let firstId = response.sites.first?.id, selectedDrawSiteId == nil {
                selectedDrawSiteId = firstId
            }
        } catch {
            errorMessage = Self.sanitize(error)
        }
    }

    func toggleTest(_ testId: String) {
        if selectedTestIds.contains(testId) {
            selectedTestIds.remove(testId)
        } else {
            selectedTestIds.insert(testId)
        }
    }

    func submitOrder(patient: LabPatientBody, preferredDateTime: Date? = nil) async {
        guard canSubmitOrder, let siteId = selectedDrawSiteId else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let body = CreateLabOrderBody(
            testIds: Array(selectedTestIds),
            collectionMethod: "phlebotomy_site",
            drawSiteId: siteId,
            preferredDateTime: preferredDateTime?.ISO8601Format(),
            patient: patient
        )

        do {
            let response = try await client.createOrder(body: body)
            confirmedOrderId = response.order.orderId
        } catch {
            errorMessage = Self.sanitize(error)
        }
    }

    // MARK: Helpers

    static func isValidZip(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) != nil
    }

    /// Sanitizes errors so no PHI leaks into the UI. The underlying NSError
    /// is allowed through, but network/decoder/internal messages are scrubbed.
    static func sanitize(_ error: Error) -> String {
        let message = (error as NSError).localizedDescription
        if message.isEmpty {
            return "Something went wrong. Please try again."
        }
        // Defensive: strip anything that could plausibly be PHI.
        return message
            .replacingOccurrences(of: #"\b\d{4}-\d{2}-\d{2}\b"#, with: "<date>", options: .regularExpression)
            .replacingOccurrences(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, with: "<email>", options: .regularExpression)
    }
}

// MARK: - Lab Provider API boundary

/// Abstracts the `APIClient` interactions used by `LabProviderViewModel` so
/// tests can inject a stub and run deterministically without a live API.
protocol LabProviderAPI {
    func fetchTests() async throws -> LabTestsResponse
    func fetchDrawSites(zip: String, radius: Int?) async throws -> LabDrawSitesResponse
    func createOrder(body: CreateLabOrderBody) async throws -> CreateLabOrderResponse
}

struct LiveLabProviderAPI: LabProviderAPI {
    func fetchTests() async throws -> LabTestsResponse {
        try await APIClient.shared.request(APIEndpoint.Labs.tests)
    }

    func fetchDrawSites(zip: String, radius: Int?) async throws -> LabDrawSitesResponse {
        try await APIClient.shared.request(APIEndpoint.Labs.drawSites(zip: zip, radius: radius))
    }

    func createOrder(body: CreateLabOrderBody) async throws -> CreateLabOrderResponse {
        try await APIClient.shared.request(APIEndpoint.Labs.createOrder(body: body))
    }
}

// MARK: - Provider-backed catalog view
//
// A minimalist catalog UI so `LabProviderViewModel` has a real
// SwiftUI surface. The existing `ScheduleLabsView` Apple Pay flow is
// preserved above; this view is additive.

struct LabTestsCatalogView: View {
    @StateObject private var viewModel = LabProviderViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Lab Test Catalog")
                    .font(.title2.bold())
                    .foregroundColor(.gsText)

                if viewModel.isLoadingTests {
                    ProgressView().frame(maxWidth: .infinity)
                } else if viewModel.tests.isEmpty {
                    Text("No tests available right now. Check back soon.")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                } else {
                    ForEach(viewModel.tests) { test in
                        Button {
                            viewModel.toggleTest(test.id)
                        } label: {
                            catalogRow(for: test, selected: viewModel.selectedTestIds.contains(test.id))
                        }
                        .buttonStyle(.plain)
                    }
                }

                drawSiteSection

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .task { await viewModel.loadTests() }
    }

    private var drawSiteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Draw Site")
                .font(.headline)
                .foregroundColor(.gsText)

            HStack {
                TextField("ZIP", text: $viewModel.zip)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)

                Button("Find Sites") {
                    Task { await viewModel.loadDrawSites() }
                }
                .disabled(viewModel.isLoadingSites)
            }

            if viewModel.isLoadingSites {
                ProgressView()
            } else {
                ForEach(viewModel.drawSites) { site in
                    Button {
                        viewModel.selectedDrawSiteId = site.id
                    } label: {
                        drawSiteRow(site, selected: viewModel.selectedDrawSiteId == site.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func catalogRow(for test: LabTestCatalogItem, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(selected ? .gsEmerald : .gsTextSecondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(test.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)
                Text(test.description)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
                    .lineLimit(2)
                Text(String(format: "$%.2f • ~%dh turnaround", Double(test.priceCents) / 100.0, test.turnaroundHours))
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.gsSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.gsEmerald : Color.gsBorder, lineWidth: 1)
        )
    }

    private func drawSiteRow(_ site: LabDrawSite, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(site.name)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
            Text("\(site.address.line1), \(site.address.city), \(site.address.state) \(site.address.postalCode)")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
            if let miles = site.distanceMiles {
                Text(String(format: "%.1f mi", miles))
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gsSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.gsEmerald : Color.gsBorder, lineWidth: 1)
        )
    }
}

// MARK: - Labs Unavailable Sheet

/// Shown when a user with a restricted-state shipping address (NY, NJ, RI)
/// attempts to submit the labs flow. Explains the regulatory reason and
/// offers a single "Back" action — there is no path forward from this sheet.
/// See `LabsStateEligibility` for the source-of-truth list.
struct LabsUnavailableView: View {
    @Environment(\.dismiss) private var dismiss
    let stateCode: String

    private var displayState: String {
        let trimmed = stateCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "your state" : trimmed
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.gsDanger.opacity(0.15))
                    .frame(width: 96, height: 96)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.gsDanger)
            }

            Text("Labs Unavailable")
                .font(.title2.bold())
                .foregroundColor(.gsText)

            Text("Unfortunately, at-home lab testing is not available in \(displayState) due to current state regulations. We'll notify you when this changes.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Back")
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
        .background(Color.gsBackground.ignoresSafeArea())
    }
}

#Preview {
    NavigationStack {
        ScheduleLabsView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Labs Unavailable") {
    LabsUnavailableView(stateCode: "NY")
        .preferredColorScheme(.dark)
}
