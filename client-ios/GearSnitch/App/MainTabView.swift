import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            // Dashboard
            NavigationStack(path: coordinator.path(for: .dashboard)) {
                DashboardPlaceholderView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem {
                Label("Dashboard", systemImage: "house.fill")
            }
            .tag(Tab.dashboard)

            // Workouts
            NavigationStack(path: coordinator.path(for: .workouts)) {
                WorkoutsPlaceholderView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem {
                Label("Workouts", systemImage: "figure.run")
            }
            .tag(Tab.workouts)

            // Health
            NavigationStack(path: coordinator.path(for: .health)) {
                HealthPlaceholderView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem {
                Label("Health", systemImage: "heart.text.clipboard")
            }
            .tag(Tab.health)

            // Store
            NavigationStack(path: coordinator.path(for: .store)) {
                StorePlaceholderView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem {
                Label("Store", systemImage: "bag.fill")
            }
            .tag(Tab.store)

            // Profile
            NavigationStack(path: coordinator.path(for: .profile)) {
                ProfilePlaceholderView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle.fill")
            }
            .tag(Tab.profile)
        }
        .tint(.gsEmerald)
        .sheet(item: $coordinator.activeSheet) { sheet in
            sheetView(for: sheet)
        }
    }

    // MARK: - Destination Router

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .referral(let code):
            Text("Referral: \(code)")
                .foregroundColor(.gsText)
        case .product(let slug):
            Text("Product: \(slug)")
                .foregroundColor(.gsText)
        case .alert(let id):
            Text("Alert: \(id)")
                .foregroundColor(.gsText)
        case .subscription:
            Text("Subscription")
                .foregroundColor(.gsText)
        case .deviceDetail(let id):
            Text("Device: \(id)")
                .foregroundColor(.gsText)
        case .gymDetail(let id):
            Text("Gym: \(id)")
                .foregroundColor(.gsText)
        case .settings:
            Text("Settings")
                .foregroundColor(.gsText)
        }
    }

    // MARK: - Sheet Router

    @ViewBuilder
    private func sheetView(for sheet: AppSheet) -> some View {
        switch sheet {
        case .addDevice:
            Text("Add Device")
                .foregroundColor(.gsText)
                .presentationDetents([.large])
        case .addGym:
            Text("Add Gym")
                .foregroundColor(.gsText)
                .presentationDetents([.large])
        case .referralShare:
            Text("Share Referral")
                .foregroundColor(.gsText)
                .presentationDetents([.medium])
        case .editProfile:
            Text("Edit Profile")
                .foregroundColor(.gsText)
                .presentationDetents([.large])
        }
    }
}

// MARK: - Placeholder Views (replaced by Feature modules)

private struct DashboardPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "house.fill",
            title: "Dashboard",
            description: "Your gear monitoring dashboard will appear here."
        )
        .navigationTitle("Dashboard")
    }
}

private struct WorkoutsPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "figure.run",
            title: "Workouts",
            description: "Your workout history and tracking will appear here."
        )
        .navigationTitle("Workouts")
    }
}

private struct HealthPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "heart.text.clipboard",
            title: "Health",
            description: "Your health metrics and trends will appear here."
        )
        .navigationTitle("Health")
    }
}

private struct StorePlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "bag.fill",
            title: "Store",
            description: "Browse gear and accessories here."
        )
        .navigationTitle("Store")
    }
}

private struct ProfilePlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "person.crop.circle.fill",
            title: "Profile",
            description: "Your profile and settings will appear here."
        )
        .navigationTitle("Profile")
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppCoordinator())
        .preferredColorScheme(.dark)
}
