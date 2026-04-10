import Foundation
import UIKit

// MARK: - Profile DTO

struct ProfileDTO: Decodable {
    let id: String
    let email: String?
    let displayName: String?
    let avatarURL: String?
    let role: String?
    let referralCode: String?
    let subscriptionTier: String?
    let linkedAccounts: [String]?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email, displayName, avatarURL, role
        case referralCode, subscriptionTier, linkedAccounts, createdAt
    }
}

// MARK: - ViewModel

@MainActor
final class ProfileViewModel: ObservableObject {

    @Published var profile: ProfileDTO?
    @Published var isLoading = false
    @Published var error: String?
    @Published var showDeleteConfirm = false
    @Published var isDeleting = false

    private let apiClient = APIClient.shared
    private let authManager = AuthManager.shared

    var displayName: String {
        profile?.displayName ?? "User"
    }

    var email: String {
        profile?.email ?? "No email"
    }

    var subscriptionTier: String {
        profile?.subscriptionTier ?? "free"
    }

    func loadProfile() async {
        isLoading = true
        error = nil

        do {
            let fetched: ProfileDTO = try await apiClient.request(APIEndpoint.Users.me)
            profile = fetched
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func signOut() async {
        await authManager.logout()
    }

    func requestDataExport() async {
        do {
            let endpoint = APIEndpoint(path: "/api/v1/users/me/export", method: .POST)
            let _: EmptyData = try await apiClient.request(endpoint)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAccount() async {
        isDeleting = true

        do {
            let endpoint = APIEndpoint(path: "/api/v1/users/me", method: .DELETE)
            let _: EmptyData = try await apiClient.request(endpoint)
            await authManager.logout()
        } catch {
            self.error = error.localizedDescription
        }

        isDeleting = false
    }
}
