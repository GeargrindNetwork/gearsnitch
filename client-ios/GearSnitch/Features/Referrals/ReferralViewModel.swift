import Foundation
import UIKit

// MARK: - Referral DTO

struct ReferralDataDTO: Decodable, Equatable {
    let referralCode: String
    let referralURL: String
    let totalReferrals: Int
    let activeReferrals: Int
    let extensionDaysEarned: Int
    let history: [ReferralHistoryItem]
}

struct ReferralHistoryItem: Identifiable, Decodable, Equatable {
    let id: String
    let referredEmail: String?
    let status: String
    let createdAt: Date

    // Optional fields populated by the referrer-side dashboard polish
    // (backlog #25). They are `nil` for referrals that haven't been
    // rewarded yet; the UI uses them to render the "+28 days earned"
    // badge and a pending reason label.
    let rewardDays: Int?
    let rewardedAt: Date?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case referredEmail, status, createdAt, rewardDays, rewardedAt, reason
    }

    var statusColor: String {
        switch status {
        case "completed": return "green"
        case "pending": return "yellow"
        case "expired": return "gray"
        default: return "gray"
        }
    }

    /// Best-effort human label for the invitee. Email addresses are
    /// masked (`sh***@gmail.com`) to keep PII off screen while still
    /// giving the referrer enough context to recognise the invite.
    var displayName: String {
        ReferralInviteeFormatter.displayName(for: referredEmail)
    }

    /// Capitalised, human-readable status label: "Pending", "Signed up",
    /// "Subscribed". Centralised so the badge and accessibility label
    /// agree.
    var statusLabel: String {
        switch status {
        case "pending": return "Signed up"
        case "completed": return rewardedAt == nil ? "Qualified" : "Subscribed"
        case "expired": return "Expired"
        default: return status.capitalized
        }
    }

    /// Whether the referral row has unlocked a reward for the referrer.
    var hasReward: Bool {
        (rewardDays ?? 0) > 0
    }
}

// MARK: - Invitee Formatter

/// Tiny pure helper so the masking rule is unit-testable without
/// having to instantiate the whole view model. Kept close to the DTO
/// rather than buried in `ReferralView` because the masked form is the
/// canonical on-screen identity for a referral.
enum ReferralInviteeFormatter {
    static func displayName(for email: String?) -> String {
        guard
            let raw = email?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let atIndex = raw.firstIndex(of: "@")
        else {
            return "Anonymous"
        }

        let local = raw[..<atIndex]
        let domain = raw[raw.index(after: atIndex)...]

        let visible: String = {
            switch local.count {
            case 0: return ""
            case 1: return String(local)
            case 2: return "\(local.prefix(1))*"
            default: return "\(local.prefix(2))***"
            }
        }()

        return "\(visible)@\(domain)"
    }
}

// MARK: - Service

/// Protocol boundary so the dashboard view model can be unit-tested
/// against a fake implementation without hitting `APIClient.shared`
/// or the network. The production implementation lives in
/// `APIReferralService` below and is a thin wrapper over the existing
/// `/api/v1/referrals/me` endpoint.
@MainActor
protocol ReferralServicing {
    func fetchReferralData() async throws -> ReferralDataDTO
}

@MainActor
final class APIReferralService: ReferralServicing {
    private let apiClient: APIClient

    // `nonisolated` init so the default-argument expression
    // `APIReferralService()` on `ReferralViewModel.init(service:)` —
    // which runs in a nonisolated context — compiles clean under
    // Swift 6. Field assignment only; no MainActor state touched.
    nonisolated init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func fetchReferralData() async throws -> ReferralDataDTO {
        try await apiClient.request(APIEndpoint.Referrals.me)
    }
}

// MARK: - ViewModel

@MainActor
final class ReferralViewModel: ObservableObject {

    @Published var data: ReferralDataDTO?
    @Published var isLoading = false
    @Published var error: String?

    private let service: ReferralServicing

    init(service: ReferralServicing = APIReferralService()) {
        self.service = service
    }

    var referralURL: String {
        data?.referralURL ?? "https://gearsnitch.com/ref/..."
    }

    var referralCode: String {
        data?.referralCode ?? "---"
    }

    /// Count of referrals that have been sent/signed-up but not yet
    /// converted into a reward. Equal to `total - active` and never
    /// negative even if the backend briefly disagrees.
    var pendingReferrals: Int {
        guard let data else { return 0 }
        return max(data.totalReferrals - data.activeReferrals, 0)
    }

    /// Whether the current state is an empty dashboard (data loaded
    /// successfully, no referrals yet). Used to decide whether to show
    /// the "invite friends" empty state instead of the list. Only true
    /// after a successful fetch returns zero rows — before the first
    /// load completes we still show the loading spinner rather than
    /// flashing the empty state.
    var isEmpty: Bool {
        guard let data else { return false }
        return data.history.isEmpty && !isLoading && error == nil
    }

    func loadReferralData() async {
        // First paint — show the full-screen loading overlay.
        if data == nil {
            isLoading = true
        }
        error = nil

        do {
            data = try await service.fetchReferralData()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Pull-to-refresh entry point. Leaves `data` in place so the list
    /// keeps rendering while the fetch is in flight, and surfaces
    /// errors via `error` without clearing previously-loaded history.
    func refresh() async {
        error = nil
        do {
            data = try await service.fetchReferralData()
        } catch {
            self.error = error.localizedDescription
        }
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
