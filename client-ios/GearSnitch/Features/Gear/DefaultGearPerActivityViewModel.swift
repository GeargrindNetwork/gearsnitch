import Foundation

/// ViewModel backing `DefaultGearPerActivityView` (backlog item #9).
///
/// Responsibilities:
///   - Load the user's gear inventory once
///   - Load the currently-configured default gear for each activity type
///   - Persist changes via `PUT /api/v1/gear/default-for-activity`
///
/// State shape: `defaults[activityType] = gearId?`. `nil` means "no default
/// set" (server will not auto-attach for that activity).
@MainActor
final class DefaultGearPerActivityViewModel: ObservableObject {

    @Published var gear: [GearComponentDTO] = []
    @Published var defaults: [GearActivityType: String?] = [:]
    @Published var isLoading = false
    @Published var savingActivity: GearActivityType?
    @Published var error: String?

    private let apiClient = APIClient.shared

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let gearFetch: [GearComponentDTO] = apiClient.request(APIEndpoint.Gear.list)
            async let defaultsFetch = fetchAllDefaults()

            let loadedGear = try await gearFetch
            let loadedDefaults = try await defaultsFetch

            self.gear = loadedGear
            self.defaults = loadedDefaults
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Persist a new default gear choice for an activity type. Passing nil
    /// clears the default (server will stop auto-attaching for that type).
    func setDefault(for activity: GearActivityType, gearId: String?) async {
        savingActivity = activity
        error = nil
        defer { savingActivity = nil }

        do {
            struct Ack: Decodable {
                let activityType: String
                let gearId: String?
            }
            let _: Ack = try await apiClient.request(
                APIEndpoint.Gear.setDefaultForActivity(
                    activityType: activity.rawValue,
                    gearId: gearId
                )
            )
            defaults[activity] = gearId
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Compatible gear subset for a given activity type.
    /// Delegates to `GearActivityCompatibility.filter` so the logic can
    /// be unit-tested in isolation.
    func compatibleGear(for activity: GearActivityType) -> [GearComponentDTO] {
        GearActivityCompatibility.filter(gear: gear, for: activity)
    }

    // MARK: - Helpers

    private func fetchAllDefaults() async throws -> [GearActivityType: String?] {
        var result: [GearActivityType: String?] = [:]
        for activity in GearActivityType.allCases {
            do {
                let response: DefaultGearForActivityDTO = try await apiClient.request(
                    APIEndpoint.Gear.defaultForActivity(type: activity.rawValue)
                )
                result[activity] = response.gear?.id
            } catch {
                // Non-fatal — leave unset, user can still configure.
                result[activity] = nil
            }
        }
        return result
    }
}
