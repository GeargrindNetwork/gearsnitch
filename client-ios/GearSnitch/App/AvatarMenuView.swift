import SwiftUI

/// Avatar menu — presented as a sheet from the top-right of `RootTabView`.
///
/// Houses the secondary navigation that used to live as primary tabs
/// (Profile, Subscription) plus all of the settings / account / referral
/// / gym / help flows. Per S2 PRD "Avatar menu (top-right popover)".
struct AvatarMenuView: View {

    @Binding var isPresented: Bool
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        NavigationStack {
            List {
                // MARK: Account

                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        avatarRow(icon: "person.crop.circle.fill", label: "Account / profile", color: .gsEmerald)
                    }

                    NavigationLink {
                        SubscriptionView()
                    } label: {
                        avatarRow(icon: "creditcard.fill", label: "Subscription", color: .gsEmerald)
                    }

                    NavigationLink {
                        NotificationPreferencesView()
                    } label: {
                        avatarRow(icon: "bell.badge.fill", label: "Notifications", color: .gsCyan)
                    }
                } header: {
                    sectionHeader("Account")
                }

                // MARK: Community

                Section {
                    NavigationLink {
                        ReferralView()
                    } label: {
                        avatarRow(icon: "qrcode", label: "Referrals & QR share", color: .gsWarning)
                    }

                    NavigationLink {
                        GymListView()
                    } label: {
                        avatarRow(icon: "building.2.fill", label: "Gym management", color: .gsCyan)
                    }
                } header: {
                    sectionHeader("Community")
                }

                // MARK: Settings

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        avatarRow(icon: "gearshape.fill", label: "Settings", color: .gsEmerald)
                    }

                    NavigationLink {
                        WorkoutSettingsView()
                    } label: {
                        avatarRow(icon: "timer", label: "Rest timer & workout defaults", color: .gsCyan)
                    }

                    NavigationLink {
                        RunTrackingSettingsView()
                    } label: {
                        avatarRow(icon: "figure.run", label: "Run tracking", color: .gsCyan)
                    }

                    NavigationLink {
                        MedicationsSyncSettingsView()
                    } label: {
                        avatarRow(icon: "cross.case.fill", label: "HealthKit medications sync", color: .gsCyan)
                    }
                } header: {
                    sectionHeader("Settings")
                }

                // MARK: Help

                Section {
                    Link(destination: URL(string: "https://gearsnitch.com/support")!) {
                        avatarRow(icon: "questionmark.circle.fill", label: "Help & support", color: .gsEmerald)
                    }
                    .buttonStyle(.plain)
                } header: {
                    sectionHeader("Help")
                }

                // MARK: Sign out

                Section {
                    Button(role: .destructive) {
                        Task {
                            await AuthManager.shared.logout()
                            isPresented = false
                        }
                    } label: {
                        avatarRow(icon: "rectangle.portrait.and.arrow.right", label: "Sign out", color: .gsDanger)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.gsBackground.ignoresSafeArea())
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .foregroundColor(.gsEmerald)
                }
            }
        }
        .accessibilityIdentifier("avatarMenu.sheet")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.gsTextSecondary)
    }

    private func avatarRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .cornerRadius(8)

            Text(label)
                .font(.body)
                .foregroundColor(.gsText)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AvatarMenuView(isPresented: .constant(true))
        .environmentObject(AppCoordinator())
        .preferredColorScheme(.dark)
}
