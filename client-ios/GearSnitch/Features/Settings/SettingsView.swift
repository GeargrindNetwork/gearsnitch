import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var showSignOutConfirm = false
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        List {
            // Notifications
            Section {
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

            // App info
            Section {
                infoRow(label: "Version", value: AppConfig.appVersion)
                infoRow(label: "Build", value: AppConfig.buildNumber)
            } header: {
                Text("App Info")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            // Data
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

            // Legal
            Section {
                Link(destination: URL(string: AppConfig.privacyPolicyURL)!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                        .foregroundColor(.gsText)
                }

                Link(destination: URL(string: AppConfig.termsURL)!) {
                    Label("Terms of Service", systemImage: "doc.text")
                        .foregroundColor(.gsText)
                }

                Link(destination: URL(string: "mailto:\(AppConfig.supportEmail)")!) {
                    Label("Contact Support", systemImage: "envelope")
                        .foregroundColor(.gsText)
                }
            } header: {
                Text("Legal")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            // Sign out
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

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthManager.shared)
    }
    .preferredColorScheme(.dark)
}
