import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var releaseGateManager = ReleaseGateManager.shared
    @State private var showSignOutConfirm = false
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LostItemScannerView()
                } label: {
                    Label("Lost Item Scanner", systemImage: "location.viewfinder")
                        .foregroundColor(.gsDanger)
                }
            } header: {
                Text("Find My Gear")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                NavigationLink {
                    GymListView()
                } label: {
                    Label("Manage Gyms", systemImage: "building.2")
                        .foregroundColor(.gsText)
                }

                NavigationLink {
                    NotificationPreferencesView()
                } label: {
                    Label("Notification Preferences", systemImage: "bell.badge")
                        .foregroundColor(.gsText)
                }
            } header: {
                Text("Preferences")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                NavigationLink {
                    ExternalHRSensorsView()
                } label: {
                    Label("External Heart-Rate Sensors", systemImage: "sensor.tag.radiowaves.forward")
                        .foregroundColor(.gsText)
                }
            } header: {
                Text("Health")
                    .foregroundColor(.gsTextSecondary)
            } footer: {
                Text("Chest straps, optical armbands, and Powerbeats Pro 2. Additive source — Apple Watch and AirPods keep working as before.")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                infoRow(label: "Version", value: AppConfig.appVersion)
                infoRow(label: "Build", value: AppConfig.buildNumber)
                if let serverVersion = releaseGateManager.serverVersion {
                    infoRow(label: "Server", value: serverVersion)
                }
            } header: {
                Text("App Info")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                Button {
                    Task { await exportAccountData() }
                } label: {
                    HStack {
                        Label("Export My Data", systemImage: "arrow.down.doc")
                            .foregroundColor(.gsText)
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .tint(.gsEmerald)
                        }
                    }
                }
                .disabled(isExporting)
            } header: {
                Text("Data")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                NavigationLink {
                    SupportCenterView()
                } label: {
                    Label("Support Center", systemImage: "lifepreserver")
                        .foregroundColor(.gsText)
                }

                Link(destination: URL(string: AppConfig.supportURL)!) {
                    Label("Open Web Support", systemImage: "safari")
                        .foregroundColor(.gsText)
                }

                Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                    Label("Email Support", systemImage: "envelope")
                        .foregroundColor(.gsText)
                }
            } header: {
                Text("Support")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                Link(destination: URL(string: AppConfig.privacyPolicyURL)!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                        .foregroundColor(.gsText)
                }

                NavigationLink {
                    TermsOfServiceView()
                } label: {
                    Label("Terms of Service", systemImage: "doc.text")
                        .foregroundColor(.gsText)
                }
            } header: {
                Text("Legal")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            #if DEBUG
            Section {
                Button {
                    NotificationCenter.default.post(name: .debugResetOnboarding, object: nil)
                } label: {
                    Label("Reset Onboarding", systemImage: "arrow.counterclockwise")
                        .foregroundColor(.gsText)
                }
            } header: {
                Text("Developer")
                    .foregroundColor(.gsTextSecondary)
            } footer: {
                Text("Restarts onboarding locally for simulator and device testing.")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)
            #endif

            Section {
                Button {
                    showSignOutConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gsDanger)
                        Spacer()
                    }
                }
            }
            .listRowBackground(Color.gsSurface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gsText)
            Spacer()
            Text(value)
                .foregroundColor(.gsTextSecondary)
        }
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
                List {
                    Section {
                        Link(destination: URL(string: AppConfig.supportURL)!) {
                            Label("Open web support", systemImage: "safari")
                                .foregroundColor(.gsText)
                        }

                        Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                            Label("Email support", systemImage: "envelope")
                                .foregroundColor(.gsText)
                        }

                        Text("Response time is usually 24 to 48 hours. Requests sent here stay attached to your GearSnitch account.")
                            .font(.footnote)
                            .foregroundColor(.gsTextSecondary)
                            .padding(.vertical, 4)
                    } header: {
                        Text("Quick Help")
                            .foregroundColor(.gsTextSecondary)
                    }
                    .listRowBackground(Color.gsSurface)

                    Section {
                        if viewModel.tickets.isEmpty {
                            Text("No support tickets yet. Your latest requests will show up here automatically.")
                                .font(.footnote)
                                .foregroundColor(.gsTextSecondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(Array(viewModel.tickets.prefix(5))) { ticket in
                                SupportTicketRow(ticket: ticket)
                            }
                        }
                    } header: {
                        Text("Recent Tickets")
                            .foregroundColor(.gsTextSecondary)
                    }
                    .listRowBackground(Color.gsSurface)

                    Section {
                        ForEach(viewModel.faqEntries) { faq in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(faq.question)
                                    .font(.headline)
                                    .foregroundColor(.gsText)
                                Text(faq.answer)
                                    .font(.subheadline)
                                    .foregroundColor(.gsTextSecondary)
                            }
                            .padding(.vertical, 6)
                        }
                    } header: {
                        Text("FAQ")
                            .foregroundColor(.gsTextSecondary)
                    }
                    .listRowBackground(Color.gsSurface)

                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            SupportField(title: "Name", text: $viewModel.draftName)
                            SupportField(title: "Email", text: $viewModel.draftEmail, keyboardType: .emailAddress, autocapitalization: .never)
                            SupportField(title: "Subject", text: $viewModel.draftSubject)
                            SupportMessageEditor(text: $viewModel.draftMessage)

                            if let submissionMessage = viewModel.submissionMessage {
                                Text(submissionMessage)
                                    .font(.footnote)
                                    .foregroundColor(.gsEmerald)
                            }

                            PrimaryButton(title: viewModel.isSubmitting ? "Sending..." : "Send Request", isLoading: viewModel.isSubmitting) {
                                Task { await viewModel.submitTicket() }
                            }
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Send a Message")
                            .foregroundColor(.gsTextSecondary)
                    }
                    .listRowBackground(Color.gsSurface)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
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
