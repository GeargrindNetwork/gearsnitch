import SwiftUI
import os

// MARK: - Primary Tab

/// The three consolidated top-level destinations introduced in S2.
/// These replace the legacy 5-tab floating-menu nav. Stable `String` raw
/// values are used as analytics IDs so downstream consumers (funnels,
/// dashboards) stay keyed to a forever-name rather than an enum case ordinal.
enum PrimaryTab: String, CaseIterable, Identifiable, Hashable {
    case gear
    case train
    case chemistry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gear:      return "Gear"
        case .train:     return "Train"
        case .chemistry: return "Chemistry"
        }
    }

    var systemImage: String {
        switch self {
        case .gear:      return "bolt.horizontal.circle.fill"
        case .train:     return "figure.run"
        case .chemistry: return "flask.fill"
        }
    }

    /// Analytics mapping of legacy tab IDs → new PrimaryTab. Used for
    /// continuity of historical tab-view funnels as the enum rolls forward.
    static func fromLegacy(_ legacy: Tab) -> PrimaryTab {
        switch legacy {
        case .dashboard: return .gear
        case .workouts:  return .train
        case .health:    return .chemistry
        case .store:     return .gear          // Store surfaces in Gear via card + avatar menu
        case .profile:   return .gear          // Profile moves into avatar menu; return .gear as a safe default landing
        }
    }

    /// The legacy Tab case the primary tab most closely maps to. Used for
    /// back-compat deep-links that still write to `coordinator.selectedTab`.
    var legacyEquivalent: Tab {
        switch self {
        case .gear:      return .dashboard
        case .train:     return .workouts
        case .chemistry: return .health
        }
    }
}

// MARK: - Root Tab View

/// S2 root UI: 3 primary tabs + avatar overlay.
///
/// Preserves the legacy nav behind the `legacyNavEnabled` feature flag
/// so we can flip back to the old `MainTabView` instantly if something
/// regresses in the field.
struct RootTabView: View {

    private let logger = Logger(subsystem: "com.gearsnitch", category: "RootTabView")

    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var featureFlags: FeatureFlags

    @State private var selection: PrimaryTab = .gear
    @State private var lastEmittedTab: PrimaryTab?
    @State private var showAvatarMenu: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $selection) {
                NavigationStack(path: coordinator.path(for: PrimaryTab.gear.legacyEquivalent)) {
                    GearTabView()
                        .navigationDestination(for: AppDestination.self) { destination in
                            RootTabDestinations.view(for: destination)
                        }
                }
                .tabItem {
                    Label(PrimaryTab.gear.title, systemImage: PrimaryTab.gear.systemImage)
                }
                .tag(PrimaryTab.gear)

                NavigationStack(path: coordinator.path(for: PrimaryTab.train.legacyEquivalent)) {
                    TrainTabView()
                        .navigationDestination(for: AppDestination.self) { destination in
                            RootTabDestinations.view(for: destination)
                        }
                }
                .tabItem {
                    Label(PrimaryTab.train.title, systemImage: PrimaryTab.train.systemImage)
                }
                .tag(PrimaryTab.train)

                NavigationStack(path: coordinator.path(for: PrimaryTab.chemistry.legacyEquivalent)) {
                    ChemistryTabView()
                        .navigationDestination(for: AppDestination.self) { destination in
                            RootTabDestinations.view(for: destination)
                        }
                }
                .tabItem {
                    Label(PrimaryTab.chemistry.title, systemImage: PrimaryTab.chemistry.systemImage)
                }
                .tag(PrimaryTab.chemistry)
            }
            .tint(.gsEmerald)
            .onAppear { emitTabEnteredIfChanged(selection) }
            .onChange(of: selection) { _, newValue in
                emitTabEnteredIfChanged(newValue)
                coordinator.selectedTab = newValue.legacyEquivalent
            }
            .onChange(of: coordinator.selectedTab) { _, newLegacy in
                // Keep new-nav in sync when deep-links mutate legacy Tab.
                let mapped = PrimaryTab.fromLegacy(newLegacy)
                if mapped != selection { selection = mapped }
            }

            // Avatar overlay — anchored top-right, above the nav bar.
            AvatarMenuLauncher(isPresented: $showAvatarMenu)
                .padding(.trailing, 16)
                .padding(.top, 6)
                .accessibilityIdentifier("rootTab.avatarMenu.launcher")
        }
        .sheet(isPresented: $showAvatarMenu) {
            AvatarMenuView(isPresented: $showAvatarMenu)
                .environmentObject(coordinator)
        }
        .sheet(item: $coordinator.activeSheet) { sheet in
            RootTabDestinations.sheet(for: sheet)
        }
    }

    // MARK: - TabEntered telemetry

    private func emitTabEnteredIfChanged(_ tab: PrimaryTab) {
        guard tab != lastEmittedTab else { return }
        lastEmittedTab = tab
        AnalyticsClient.shared.track(event: .tabEntered(
            newTabId: tab.rawValue,
            legacyTabId: tab.legacyEquivalent.rawValue
        ))
        logger.debug("TabEntered \(tab.rawValue, privacy: .public)")
    }
}

// MARK: - Destination / Sheet routing

/// Shared routing helpers reused across the 3 NavigationStacks. Keeping them
/// here (rather than duplicated inside each tab view) prevents drift if the
/// `AppDestination` union grows.
enum RootTabDestinations {

    @ViewBuilder
    static func view(for destination: AppDestination) -> some View {
        switch destination {
        case .referral(_):
            ReferralView()
        case .product(let reference):
            RootTabProductDestinationView(productReference: reference)
        case .alert(let id):
            RootTabAlertDestinationView(alertId: id)
        case .subscription:
            SubscriptionView()
        case .deviceDetail(let id):
            DeviceDetailView(deviceId: id)
        case .gymDetail(let id):
            RootTabGymDestinationView(gymId: id)
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    static func sheet(for sheet: AppSheet) -> some View {
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

// MARK: - Lightweight async loaders (private to RootTabView)

/// Private re-implementations of the `MainTabView` detail loaders so legacy
/// code can be deleted/moved without RootTabView silently linking against
/// it. Kept internal + file-private to avoid polluting the global namespace.

private struct RootTabProductDestinationView: View {
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

private struct RootTabGymDestinationView: View {
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

private struct RootTabAlertDestinationView: View {
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

// MARK: - Avatar launcher

private struct AvatarMenuLauncher: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.gsEmerald.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.gsEmerald)
            }
        }
        .accessibilityLabel("Open account menu")
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppCoordinator())
        .environmentObject(FeatureFlags.shared)
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
