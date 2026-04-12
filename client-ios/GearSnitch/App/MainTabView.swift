import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            NavigationStack(path: coordinator.path(for: .dashboard)) {
                DashboardView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem {
                Label("Dashboard", systemImage: "house.fill")
            }
            .tag(Tab.dashboard)

            NavigationStack(path: coordinator.path(for: .workouts)) {
                WorkoutListView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem {
                Label("Workouts", systemImage: "figure.run")
            }
            .tag(Tab.workouts)

            NavigationStack(path: coordinator.path(for: .health)) {
                HealthDashboardView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem {
                Label("Health", systemImage: "heart.text.clipboard")
            }
            .tag(Tab.health)

            NavigationStack(path: coordinator.path(for: .store)) {
                StoreHomeView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem {
                Label("Store", systemImage: "bag.fill")
            }
            .tag(Tab.store)

            NavigationStack(path: coordinator.path(for: .profile)) {
                ProfileView()
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

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .referral:
            ReferralView()
        case .product(let reference):
            ProductDestinationView(productReference: reference)
        case .alert(let id):
            AlertDestinationView(alertId: id)
        case .subscription:
            SubscriptionView()
        case .deviceDetail(let id):
            DeviceDetailView(deviceId: id)
        case .gymDetail(let id):
            GymDetailDestinationView(gymId: id)
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private func sheetView(for sheet: AppSheet) -> some View {
        switch sheet {
        case .addDevice:
            NavigationStack {
                DevicePairingView()
            }
            .presentationDetents([.large])
        case .addGym:
            NavigationStack {
                AddGymView()
            }
            .presentationDetents([.large])
        case .referralShare:
            NavigationStack {
                ReferralView()
            }
            .presentationDetents([.medium, .large])
        case .editProfile:
            NavigationStack {
                ProfileView()
            }
            .presentationDetents([.large])
        }
    }
}

private struct ProductDestinationView: View {
    let productReference: String

    @State private var product: ProductDTO?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && product == nil {
                LoadingView(message: "Loading product...")
            } else if let product {
                ProductDetailView(product: product)
            } else if let error {
                ErrorView(message: error) {
                    Task { await loadProduct() }
                }
            }
        }
        .task {
            if product == nil && error == nil {
                await loadProduct()
            }
        }
    }

    private func loadProduct() async {
        isLoading = true
        error = nil

        do {
            product = try await APIClient.shared.request(
                APIEndpoint(path: "/api/v1/store/products/\(productReference)")
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

private struct GymDetailDestinationView: View {
    let gymId: String

    @State private var gym: GymDTO?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && gym == nil {
                LoadingView(message: "Loading gym...")
            } else if let gym {
                GymDetailView(gym: gym)
            } else if let error {
                ErrorView(message: error) {
                    Task { await loadGym() }
                }
            }
        }
        .task {
            if gym == nil && error == nil {
                await loadGym()
            }
        }
    }

    private func loadGym() async {
        isLoading = true
        error = nil

        do {
            gym = try await APIClient.shared.request(
                APIEndpoint(path: "/api/v1/gyms/\(gymId)")
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

private struct AlertDestinationView: View {
    let alertId: String

    @State private var alert: AlertDTO?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && alert == nil {
                LoadingView(message: "Loading alert...")
            } else if let alert {
                AlertDetailView(alert: alert, onAcknowledge: acknowledgeAlert)
            } else if let error {
                ErrorView(message: error) {
                    Task { await loadAlert() }
                }
            }
        }
        .task {
            if alert == nil && error == nil {
                await loadAlert()
            }
        }
    }

    private func loadAlert() async {
        isLoading = true
        error = nil

        do {
            let alerts: [AlertDTO] = try await APIClient.shared.request(APIEndpoint.Alerts.list)
            guard let match = alerts.first(where: { $0.id == alertId }) else {
                error = "Alert not found."
                isLoading = false
                return
            }
            alert = match
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func acknowledgeAlert() {
        Task {
            do {
                let _: EmptyData = try await APIClient.shared.request(
                    APIEndpoint.Alerts.acknowledge(id: alertId)
                )
                await loadAlert()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppCoordinator())
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
