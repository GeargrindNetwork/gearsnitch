import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var releaseGateManager = ReleaseGateManager.shared
    @ObservedObject private var iCloudSync = ICloudProfileSync.shared
    @State private var showSignOutConfirm = false
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                accountSection
                findMyGearSection
                preferencesSection
                healthSection
                appInfoSection
                dataSection
                supportSection
                legalSection
                #if DEBUG
                developerSection
                #endif
                signOutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign Out", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) {
                Task { await authManager.logout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Something went wrong while exporting your data.")
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Account")

            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { iCloudSync.isEnabled },
                    set: { iCloudSync.setEnabled($0) }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud")
                            .font(.subheadline)
                            .foregroundColor(.gsCyan)
                            .frame(width: 28)
                        Text("Sync with iCloud")
                            .font(.subheadline)
                            .foregroundColor(.gsText)
                    }
                }
                .tint(.gsEmerald)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityIdentifier("settings.iCloudSync.toggle")
            }
            .cardStyle(padding: 0)

            Text("Syncs display name, preferences, feature flags, default gym, and HealthKit opt-ins across your iCloud devices. Auth tokens and subscription state stay on-device.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .padding(.horizontal, 4)
        }
    }

    private var findMyGearSection: some View {
        sectionCard(title: "Find My Gear") {
            NavigationLink {
                LostItemScannerView()
            } label: {
                menuRow(icon: "location.viewfinder", label: "Lost Item Scanner", color: .gsDanger)
            }
        }
    }

    private var preferencesSection: some View {
        sectionCard(title: "Preferences") {
            NavigationLink {
                GymListView()
            } label: {
                menuRow(icon: "building.2", label: "Manage Gyms", color: .gsCyan)
            }
            divider

            NavigationLink {
                DefaultGearPerActivityView()
            } label: {
                menuRow(icon: "shoe.2", label: "Default gear per activity", color: .gsEmerald)
            }
            divider

            NavigationLink {
                WorkoutSettingsView()
            } label: {
                menuRow(icon: "dumbbell", label: "Workout", color: .gsEmerald)
            }
            divider

            NavigationLink {
                RunTrackingSettingsView()
            } label: {
                menuRow(icon: "figure.run", label: "Run tracking", color: .gsEmerald)
            }
            divider

            NavigationLink {
                NotificationPreferencesView()
            } label: {
                menuRow(icon: "bell.badge", label: "Notification Preferences", color: .gsWarning)
            }
            divider

            NavigationLink {
                MedicationsSyncSettingsView()
            } label: {
                menuRow(icon: "pills", label: "Medications", color: .gsCyan)
            }
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Health")

            VStack(spacing: 0) {
                NavigationLink {
                    ExternalHRSensorsView()
                } label: {
                    menuRow(icon: "sensor.tag.radiowaves.forward", label: "External Heart-Rate Sensors", color: .gsDanger)
                }
            }
            .cardStyle(padding: 0)

            Text("Chest straps, optical armbands, and Powerbeats Pro 2. Additive source — Apple Watch and AirPods keep working as before.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .padding(.horizontal, 4)
        }
    }

    private var appInfoSection: some View {
        sectionCard(title: "App Info") {
            infoRow(label: "Version", value: AppConfig.appVersion)
            divider
            infoRow(label: "Build", value: AppConfig.buildNumber)
            if let serverVersion = releaseGateManager.serverVersion {
                divider
                infoRow(label: "Server", value: serverVersion)
            }
        }
    }

    private var dataSection: some View {
        sectionCard(title: "Data") {
            Button {
                Task { await exportAccountData() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.body)
                        .foregroundColor(.gsCyan)
                        .frame(width: 28)

                    Text("Export My Data")
                        .font(.subheadline)
                        .foregroundColor(.gsText)

                    Spacer()

                    if isExporting {
                        ProgressView()
                            .tint(.gsEmerald)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.gsTextSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
        }
    }

    private var supportSection: some View {
        sectionCard(title: "Support") {
            NavigationLink {
                SupportCenterView()
            } label: {
                menuRow(icon: "lifepreserver", label: "Support Center", color: .gsEmerald)
            }
            divider

            Link(destination: URL(string: AppConfig.supportURL)!) {
                menuRow(icon: "safari", label: "Open Web Support", color: .gsCyan)
            }
            .buttonStyle(.plain)
            divider

            Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                menuRow(icon: "envelope", label: "Email Support", color: .gsCyan)
            }
            .buttonStyle(.plain)
            divider

            Button {
                openAppStoreReviewPage()
            } label: {
                menuRow(icon: "star.bubble", label: "Rate GearSnitch on the App Store", color: .gsWarning)
            }
            .buttonStyle(.plain)
        }
    }

    private var legalSection: some View {
        sectionCard(title: "Legal") {
            Link(destination: URL(string: AppConfig.privacyPolicyURL)!) {
                menuRow(icon: "hand.raised", label: "Privacy Policy", color: .gsTextSecondary)
            }
            .buttonStyle(.plain)
            divider

            NavigationLink {
                TermsOfServiceView()
            } label: {
                menuRow(icon: "doc.text", label: "Terms of Service", color: .gsTextSecondary)
            }
        }
    }

    #if DEBUG
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Developer")

            VStack(spacing: 0) {
                Button {
                    NotificationCenter.default.post(name: .debugResetOnboarding, object: nil)
                } label: {
                    menuRow(icon: "arrow.counterclockwise", label: "Reset Onboarding", color: .gsWarning)
                }
                .buttonStyle(.plain)
            }
            .cardStyle(padding: 0)

            Text("Restarts onboarding locally for simulator and device testing.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .padding(.horizontal, 4)
        }
    }
    #endif

    private var signOutSection: some View {
        VStack(spacing: 0) {
            Button {
                showSignOutConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsDanger)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
        }
        .cardStyle(padding: 0)
    }

    // MARK: - Shared Builders

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title)

            VStack(spacing: 0) {
                content()
            }
            .cardStyle(padding: 0)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.gsText)
            .padding(.horizontal, 4)
    }

    private func menuRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 28)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsText)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Divider().background(Color.gsBorder)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsText)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func exportAccountData() async {
        isExporting = true
        defer { isExporting = false }

        do {
            try await AccountDataExporter.exportMyData()
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Open the App Store listing with the "Write a Review" action
    /// pre-selected. See `AppConfig.appStoreURL` for the canonical URL
    /// (TODO: placeholder ID until the app ships).
    private func openAppStoreReviewPage() {
        let base = AppConfig.appStoreURL.replacingOccurrences(
            of: "https://apps.apple.com",
            with: "itms-apps://itunes.apple.com"
        )
        guard var components = URLComponents(string: base) else { return }
        components.queryItems = [URLQueryItem(name: "action", value: "write-review")]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}

private struct SupportFAQItem: Decodable, Identifiable {
    let question: String
    let answer: String

    var id: String { question }
}

private struct SupportTicketDTO: Decodable, Identifiable {
    let id: String
    let subject: String
    let message: String
    let status: String
    let source: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case subject, message, status, source, createdAt
    }

    var shortReference: String {
        String(id.suffix(8)).uppercased()
    }

    var statusColor: Color {
        switch status {
        case "resolved":
            return .gsEmerald
        case "closed":
            return .gsTextSecondary
        default:
            return .gsCyan
        }
    }

    var statusLabel: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct SupportTicketSubmissionResponse: Decodable {
    let ticketId: String
    let status: String
    let ticket: SupportTicketDTO?
}

@MainActor
private final class SupportCenterViewModel: ObservableObject {
    @Published var faqEntries: [SupportFAQItem] = []
    @Published var tickets: [SupportTicketDTO] = []
    @Published var draftName = ""
    @Published var draftEmail = ""
    @Published var draftSubject = ""
    @Published var draftMessage = ""
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var error: String?
    @Published var submissionMessage: String?

    private let apiClient = APIClient.shared
    private let authManager = AuthManager.shared
    private var hasLoaded = false

    func loadIfNeeded() async {
        seedDraftsFromCurrentUser()
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        seedDraftsFromCurrentUser()
        isLoading = true
        error = nil

        do {
            async let loadedFaq: [SupportFAQItem] = apiClient.request(APIEndpoint.Support.faq)
            async let loadedTickets: [SupportTicketDTO] = apiClient.request(APIEndpoint.Support.tickets)
            faqEntries = try await loadedFaq
            tickets = try await loadedTickets
            hasLoaded = true
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func submitTicket() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = draftEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = draftSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !email.isEmpty, !subject.isEmpty, !message.isEmpty else {
            error = "Complete all fields before sending your request."
            return
        }

        isSubmitting = true
        error = nil
        submissionMessage = nil

        do {
            let response: SupportTicketSubmissionResponse = try await apiClient.request(
                APIEndpoint.Support.createTicket(
                    CreateSupportTicketBody(
                        name: name,
                        email: email,
                        subject: subject,
                        message: message,
                        source: "ios"
                    )
                )
            )

            if let ticket = response.ticket {
                tickets.insert(ticket, at: 0)
            } else {
                await load()
            }

            draftSubject = ""
            draftMessage = ""
            submissionMessage = "Support request \(String(response.ticketId.suffix(8)).uppercased()) received."
        } catch {
            self.error = error.localizedDescription
        }

        isSubmitting = false
    }

    private func seedDraftsFromCurrentUser() {
        guard let currentUser = authManager.currentUser else { return }

        if draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftName = currentUser.displayName?.isEmpty == false
                ? (currentUser.displayName ?? "")
                : currentUser.resolvedDisplayName
        }

        if draftEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftEmail = currentUser.email
        }
    }
}

private struct SupportCenterView: View {
    @StateObject private var viewModel = SupportCenterViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.faqEntries.isEmpty && viewModel.tickets.isEmpty {
                LoadingView(message: "Loading support center...")
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        quickHelpSection
                        recentTicketsSection
                        if !viewModel.faqEntries.isEmpty {
                            faqSection
                        }
                        sendMessageSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .background(Color.gsBackground.ignoresSafeArea())
            }
        }
        .navigationTitle("Support Center")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.load()
        }
        .alert("Support Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "Something went wrong while loading support.")
        }
    }

    private var quickHelpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Help")
                .font(.headline)
                .foregroundColor(.gsText)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Link(destination: URL(string: AppConfig.supportURL)!) {
                    supportMenuRow(icon: "safari", label: "Open web support", color: .gsCyan)
                }
                .buttonStyle(.plain)

                Divider().background(Color.gsBorder)

                Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                    supportMenuRow(icon: "envelope", label: "Email support", color: .gsCyan)
                }
                .buttonStyle(.plain)
            }
            .cardStyle(padding: 0)

            Text("Response time is usually 24 to 48 hours. Requests sent here stay attached to your GearSnitch account.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .padding(.horizontal, 4)
        }
    }

    private var recentTicketsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Tickets")
                .font(.headline)
                .foregroundColor(.gsText)
                .padding(.horizontal, 4)

            if viewModel.tickets.isEmpty {
                Text("No support tickets yet. Your latest requests will show up here automatically.")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(viewModel.tickets.prefix(5))) { ticket in
                        SupportTicketRow(ticket: ticket)
                            .cardStyle()
                    }
                }
            }
        }
    }

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FAQ")
                .font(.headline)
                .foregroundColor(.gsText)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ForEach(viewModel.faqEntries) { faq in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(faq.question)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.gsText)
                        Text(faq.answer)
                            .font(.subheadline)
                            .foregroundColor(.gsTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
            }
        }
    }

    private var sendMessageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Send a Message")
                .font(.headline)
                .foregroundColor(.gsText)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 12) {
                SupportField(title: "Name", text: $viewModel.draftName)
                SupportField(title: "Email", text: $viewModel.draftEmail, keyboardType: .emailAddress, autocapitalization: .never)
                SupportField(title: "Subject", text: $viewModel.draftSubject)
                SupportMessageEditor(text: $viewModel.draftMessage)

                if let submissionMessage = viewModel.submissionMessage {
                    Text(submissionMessage)
                        .font(.caption)
                        .foregroundColor(.gsEmerald)
                }

                PrimaryButton(title: viewModel.isSubmitting ? "Sending..." : "Send Request", isLoading: viewModel.isSubmitting) {
                    Task { await viewModel.submitTicket() }
                }
            }
            .cardStyle()
        }
    }

    private func supportMenuRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 28)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsText)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct SupportTicketRow: View {
    let ticket: SupportTicketDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ticket.subject)
                        .font(.headline)
                        .foregroundColor(.gsText)

                    Text("Ticket \(ticket.shortReference)")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }

                Spacer()

                Text(ticket.statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ticket.statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ticket.statusColor.opacity(0.14))
                    .clipShape(Capsule())
            }

            Text(ticket.message)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .lineLimit(3)

            Text(ticket.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.vertical, 6)
    }
}

private struct SupportField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .words

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.gsTextSecondary)
            TextField("", text: $text)
                .textInputAutocapitalization(autocapitalization)
                .keyboardType(keyboardType)
                .disableAutocorrection(keyboardType == .emailAddress)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .foregroundColor(.gsText)
                .background(Color.gsSurfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct SupportMessageEditor: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Message")
                .font(.caption.weight(.semibold))
                .foregroundColor(.gsTextSecondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gsSurfaceRaised)

                if text.isEmpty {
                    Text("Describe your issue or question...")
                        .font(.body)
                        .foregroundColor(.gsTextSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 144)
                    .foregroundColor(.gsText)
                    .background(Color.clear)
            }
            .frame(minHeight: 144)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthManager.shared)
    }
    .preferredColorScheme(.dark)
}
