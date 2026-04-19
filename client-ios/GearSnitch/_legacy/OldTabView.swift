import SwiftUI

/// Legacy pre-S2 5-tab nav. Retained behind the
/// `FeatureFlags.legacyNavEnabled` kill-switch for emergency rollback.
/// New code should not reference `OldTabView`; use `RootTabView` instead.
struct OldTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var menuExpanded = false
    @State private var showHospitals = false
    @State private var showLabs = false

    var body: some View {
        ZStack {
            // Active tab content
            Group {
                switch coordinator.selectedTab {
                case .dashboard:
                    NavigationStack(path: coordinator.path(for: .dashboard)) {
                        DashboardView()
                            .navigationDestination(for: AppDestination.self) { destination in
                                destinationView(for: destination)
                            }
                    }

                case .workouts:
                    NavigationStack(path: coordinator.path(for: .workouts)) {
                        WorkoutListView()
                            .navigationDestination(for: AppDestination.self) { destination in
                                destinationView(for: destination)
                            }
                    }

                case .health:
                    NavigationStack(path: coordinator.path(for: .health)) {
                        HealthDashboardView()
                            .navigationDestination(for: AppDestination.self) { destination in
                                destinationView(for: destination)
                            }
                    }

                case .store:
                    NavigationStack(path: coordinator.path(for: .store)) {
                        StoreHomeView()
                            .navigationDestination(for: AppDestination.self) { destination in
                                destinationView(for: destination)
                            }
                    }

                case .profile:
                    NavigationStack(path: coordinator.path(for: .profile)) {
                        ProfileView()
                            .navigationDestination(for: AppDestination.self) { destination in
                                destinationView(for: destination)
                            }
                    }
                }
            }

            // Dim overlay when menu is expanded
            if menuExpanded {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            menuExpanded = false
                        }
                    }
            }

            // Floating hamburger menu
            FloatingMenuView(
                selectedTab: $coordinator.selectedTab,
                isExpanded: $menuExpanded,
                onHospitals: { showHospitals = true },
                onLabs: { showLabs = true }
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: HandPreferenceManager.shared.isMenuOnLeft ? .bottomLeading : .bottomTrailing
            )
        }
        .sheet(item: $coordinator.activeSheet) { sheet in
            sheetView(for: sheet)
        }
        .fullScreenCover(isPresented: $showHospitals) {
            NavigationStack {
                NearestHospitalsView()
            }
        }
        .fullScreenCover(isPresented: $showLabs) {
            NavigationStack {
                ScheduleLabsView()
            }
        }
    }

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .referral(_):
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
    OldTabView()
        .environmentObject(AppCoordinator())
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
