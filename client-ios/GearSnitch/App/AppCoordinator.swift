import SwiftUI
import os

// MARK: - Tab

enum Tab: String, CaseIterable, Identifiable {
    case dashboard
    case workouts
    case health
    case store
    case profile

    var id: String { rawValue }
}

// MARK: - Navigation Destinations

enum AppDestination: Hashable {
    case referral(code: String)
    case product(slug: String)
    case alert(id: String)
    case subscription
    case deviceDetail(id: String)
    case gymDetail(id: String)
    case settings
}

// MARK: - Sheets

enum AppSheet: Identifiable {
    case addDevice
    case addGym
    case referralShare
    case editProfile

    var id: String {
        switch self {
        case .addDevice: return "addDevice"
        case .addGym: return "addGym"
        case .referralShare: return "referralShare"
        case .editProfile: return "editProfile"
        }
    }
}

// MARK: - App Coordinator

@MainActor
final class AppCoordinator: ObservableObject {

    private let logger = Logger(subsystem: "com.gearsnitch", category: "AppCoordinator")

    // MARK: Published State

    @Published var selectedTab: Tab = .dashboard

    @Published var dashboardPath = NavigationPath()
    @Published var workoutsPath = NavigationPath()
    @Published var healthPath = NavigationPath()
    @Published var storePath = NavigationPath()
    @Published var profilePath = NavigationPath()

    @Published var activeSheet: AppSheet?

    // MARK: - Navigation Path for Current Tab

    func path(for tab: Tab) -> Binding<NavigationPath> {
        switch tab {
        case .dashboard: return Binding(get: { self.dashboardPath }, set: { self.dashboardPath = $0 })
        case .workouts:  return Binding(get: { self.workoutsPath },  set: { self.workoutsPath = $0 })
        case .health:    return Binding(get: { self.healthPath },    set: { self.healthPath = $0 })
        case .store:     return Binding(get: { self.storePath },     set: { self.storePath = $0 })
        case .profile:   return Binding(get: { self.profilePath },   set: { self.profilePath = $0 })
        }
    }

    // MARK: - Deep Link Handling

    /// Handle a deep link URL (gearsnitch:// or universal link).
    func handle(url: URL) {
        logger.info("Handling deep link: \(url.absoluteString)")

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            logger.warning("Invalid deep link URL: \(url.absoluteString)")
            return
        }

        let pathSegments = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .components(separatedBy: "/")
            .filter { !$0.isEmpty }

        guard let first = pathSegments.first else { return }

        switch first {
        case "referral":
            // gearsnitch://referral/:code
            guard pathSegments.count >= 2 else { return }
            let code = pathSegments[1]
            selectedTab = .dashboard
            dashboardPath.append(AppDestination.referral(code: code))

        case "store":
            // gearsnitch://store/products/:slug
            if pathSegments.count >= 3, pathSegments[1] == "products" {
                let slug = pathSegments[2]
                selectedTab = .store
                storePath.append(AppDestination.product(slug: slug))
            } else {
                selectedTab = .store
            }

        case "alerts":
            // gearsnitch://alerts/:id
            guard pathSegments.count >= 2 else {
                selectedTab = .dashboard
                return
            }
            let alertId = pathSegments[1]
            selectedTab = .dashboard
            dashboardPath.append(AppDestination.alert(id: alertId))

        case "subscription":
            // gearsnitch://subscription
            selectedTab = .profile
            profilePath.append(AppDestination.subscription)

        default:
            logger.warning("Unhandled deep link path: \(first)")
        }
    }

    // MARK: - Programmatic Navigation Helpers

    func navigate(to destination: AppDestination, tab: Tab? = nil) {
        let targetTab = tab ?? selectedTab
        selectedTab = targetTab
        path(for: targetTab).wrappedValue.append(destination)
    }

    func popToRoot(tab: Tab? = nil) {
        let targetTab = tab ?? selectedTab
        path(for: targetTab).wrappedValue = NavigationPath()
    }

    func present(sheet: AppSheet) {
        activeSheet = sheet
    }

    func dismissSheet() {
        activeSheet = nil
    }
}
