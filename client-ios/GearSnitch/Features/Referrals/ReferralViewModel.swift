import Foundation
import UIKit

// MARK: - Referral DTO

struct ReferralDataDTO: Decodable {
    let referralCode: String
    let referralURL: String
    let totalReferrals: Int
    let activeReferrals: Int
    let extensionDaysEarned: Int
    let history: [ReferralHistoryItem]
}

struct ReferralHistoryItem: Identifiable, Decodable {
    let id: String
    let referredEmail: String?
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case referredEmail, status, createdAt
    }

    var statusColor: String {
        switch status {
        case "completed": return "green"
        case "pending": return "yellow"
        case "expired": return "gray"
        default: return "gray"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ReferralViewModel: ObservableObject {

    @Published var data: ReferralDataDTO?
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    var referralURL: String {
        data?.referralURL ?? "https://gearsnitch.com/ref/..."
    }

    var referralCode: String {
        data?.referralCode ?? "---"
    }

    func loadReferralData() async {
        isLoading = true
        error = nil

        do {
            let fetched: ReferralDataDTO = try await apiClient.request(APIEndpoint.Referrals.me)
            data = fetched
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func shareReferral() {
        let text = "Join me on GearSnitch! Use my referral code: \(referralCode)\n\(referralURL)"

        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }

        rootVC.present(activityVC, animated: true)
    }
}
