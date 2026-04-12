import Foundation
import UIKit
import HealthKit
import PhotosUI
import SwiftUI
import os

// MARK: - Profile DTO

struct ProfileDTO: Decodable {
    let id: String
    let email: String?
    let displayName: String?
    let firstName: String?
    let lastName: String?
    let avatarURL: String?
    let role: String?
    let referralCode: String?
    let subscriptionTier: String?
    let linkedAccounts: [String]?
    let createdAt: String?
    let dateOfBirth: String?
    let heightInches: Double?
    let weightLbs: Double?
    let orderCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email, displayName, firstName, lastName, avatarURL, role
        case referralCode, subscriptionTier, linkedAccounts, createdAt
        case dateOfBirth, heightInches, weightLbs, orderCount
    }
}

// MARK: - ViewModel

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published State

    @Published var profile: ProfileDTO?
    @Published var isLoading = false
    @Published var error: String?
    @Published var showDeleteConfirm = false
    @Published var isDeleting = false

    // Profile photo
    @Published var profileImage: UIImage?
    @Published var showPhotoPicker = false
    @Published var selectedPhoto: PhotosPickerItem?

    // Edit sheet
    @Published var showEditProfile = false
    @Published var editFirstName: String = ""
    @Published var editLastName: String = ""
    @Published var editDateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @Published var editHeightInches: Double = 70
    @Published var editWeightLbs: Double = 170

    // Health data from HealthKit
    @Published var healthKitWeight: Double?    // lbs
    @Published var healthKitHeight: Double?    // inches
    @Published var bloodType: HKBloodType = .notSet
    @Published var biologicalSex: HKBiologicalSex = .notSet
    @Published var isImportingHealth = false

    // MARK: - Private

    private let apiClient = APIClient.shared
    private let authManager = AuthManager.shared
    private let healthKit = HealthKitManager.shared
    private let logger = Logger(subsystem: "com.gearsnitch", category: "ProfileVM")

    // MARK: - Computed Display Values

    var displayName: String {
        if let first = profile?.firstName, let last = profile?.lastName,
           !first.isEmpty || !last.isEmpty {
            return [first, last].compactMap { $0?.isEmpty == true ? nil : $0 }.joined(separator: " ")
        }
        return profile?.displayName ?? "User"
    }

    var email: String {
        profile?.email ?? "No email"
    }

    var subscriptionTier: String {
        profile?.subscriptionTier ?? "free"
    }

    var dateOfBirthDisplay: String {
        if let dob = profile?.dateOfBirth, !dob.isEmpty {
            // Try to parse and format
            if let date = ISO8601DateFormatter.standard.date(from: dob) {
                return date.formatted(date: .abbreviated, time: .omitted)
            }
            return dob
        }
        return "Not set"
    }

    var heightDisplay: String {
        let h = healthKitHeight ?? profile?.heightInches
        guard let inches = h, inches > 0 else { return "Not set" }
        let feet = Int(inches) / 12
        let remainingInches = Int(inches) % 12
        return "\(feet)'\(remainingInches)\""
    }

    var weightDisplay: String {
        let w = healthKitWeight ?? profile?.weightLbs
        guard let lbs = w, lbs > 0 else { return "Not set" }
        return String(format: "%.0f lbs", lbs)
    }

    var bmiDisplay: String {
        let h = healthKitHeight ?? profile?.heightInches ?? 0
        let w = healthKitWeight ?? profile?.weightLbs ?? 0
        guard h > 0, w > 0 else { return "--" }
        let bmi = (w / (h * h)) * 703
        return String(format: "%.1f", bmi)
    }

    var bloodTypeDisplay: String {
        switch bloodType {
        case .notSet: return "Unknown"
        case .aPositive: return "A+"
        case .aNegative: return "A-"
        case .bPositive: return "B+"
        case .bNegative: return "B-"
        case .abPositive: return "AB+"
        case .abNegative: return "AB-"
        case .oPositive: return "O+"
        case .oNegative: return "O-"
        @unknown default: return "Unknown"
        }
    }

    var biologicalSexDisplay: String {
        switch biologicalSex {
        case .notSet: return "Not set"
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        @unknown default: return "Unknown"
        }
    }

    var orderCountDisplay: String? {
        guard let count = profile?.orderCount, count > 0 else { return nil }
        return "\(count) order\(count == 1 ? "" : "s")"
    }

    /// Dietary recommendation based on blood type.
    var bloodTypeRecommendation: String? {
        switch bloodType {
        case .aPositive, .aNegative:
            return "Type A: Focus on plant-based foods and lean proteins. Vegetables, fruits, tofu, legumes, and whole grains work best. Limit red meat and dairy."
        case .bPositive, .bNegative:
            return "Type B: Balanced diet with variety. Dairy is generally well-tolerated. Green vegetables, eggs, low-fat meats, and certain grains are beneficial."
        case .abPositive, .abNegative:
            return "Type AB: Mixed diet combining A and B recommendations. Emphasize seafood, tofu, dairy, and green vegetables. Small frequent meals work best."
        case .oPositive, .oNegative:
            return "Type O: High-protein diet with lean meats, fish, and vegetables. Limit grains, beans, and legumes. Physical activity pairs well with this diet."
        case .notSet:
            return nil
        @unknown default:
            return nil
        }
    }

    // MARK: - Load Profile

    func loadProfile() async {
        isLoading = true
        error = nil

        do {
            let fetched: ProfileDTO = try await apiClient.request(APIEndpoint.Users.me)
            profile = fetched

            // Pre-populate edit fields
            editFirstName = fetched.firstName ?? ""
            editLastName = fetched.lastName ?? ""
            if let dob = fetched.dateOfBirth,
               let date = ISO8601DateFormatter.standard.date(from: dob) {
                editDateOfBirth = date
            }
            editHeightInches = fetched.heightInches ?? 70
            editWeightLbs = fetched.weightLbs ?? 170

            // Load avatar image if URL exists
            if let urlString = fetched.avatarURL, let url = URL(string: urlString) {
                await loadAvatarImage(from: url)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Photo Handling

    func loadSelectedPhoto() async {
        guard let item = selectedPhoto else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                profileImage = image
                // TODO: Upload image to backend
            }
        } catch {
            logger.error("Failed to load selected photo: \(error.localizedDescription)")
        }

        selectedPhoto = nil
    }

    private func loadAvatarImage(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                profileImage = image
            }
        } catch {
            logger.error("Failed to load avatar: \(error.localizedDescription)")
        }
    }

    // MARK: - HealthKit Import

    func importFromHealthKit() async {
        guard healthKit.isAvailable else {
            error = "HealthKit is not available on this device."
            return
        }

        isImportingHealth = true

        do {
            // Request authorization with characteristics
            try await requestHealthKitWithCharacteristics()

            // Read characteristics (blood type, biological sex)
            readCharacteristics()

            // Read latest weight
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let weightSamples = try await healthKit.querySamples(
                type: .bodyMass,
                since: thirtyDaysAgo,
                unit: .pound()
            )
            if let latestWeight = weightSamples.last {
                healthKitWeight = latestWeight.value
                editWeightLbs = latestWeight.value
            }

            // Read latest height
            let heightSamples = try await healthKit.querySamples(
                type: .height,
                since: Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? Date(),
                unit: .inch()
            )
            if let latestHeight = heightSamples.last {
                healthKitHeight = latestHeight.value
                editHeightInches = latestHeight.value
            }

            logger.info("HealthKit import completed")
        } catch {
            self.error = "Failed to import from Apple Health: \(error.localizedDescription)"
            logger.error("HealthKit import failed: \(error.localizedDescription)")
        }

        isImportingHealth = false
    }

    private func requestHealthKitWithCharacteristics() async throws {
        guard healthKit.isAvailable else {
            throw HealthKitError.notAvailable
        }

        let healthStore = HKHealthStore()

        var readTypes = HealthKitManager.readTypes
        // Add characteristic types
        if let bloodTypeChar = HKObjectType.characteristicType(forIdentifier: .bloodType) {
            readTypes.insert(bloodTypeChar)
        }
        if let bioSexChar = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            readTypes.insert(bioSexChar)
        }
        if let dobChar = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            readTypes.insert(dobChar)
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    private func readCharacteristics() {
        let healthStore = HKHealthStore()

        // Blood type
        do {
            let bloodTypeObj = try healthStore.bloodType()
            bloodType = bloodTypeObj.bloodType
        } catch {
            logger.debug("Could not read blood type: \(error.localizedDescription)")
        }

        // Biological sex
        do {
            let bioSexObj = try healthStore.biologicalSex()
            biologicalSex = bioSexObj.biologicalSex
        } catch {
            logger.debug("Could not read biological sex: \(error.localizedDescription)")
        }

        // Date of birth
        do {
            let dobComponents = try healthStore.dateOfBirthComponents()
            if let date = Calendar.current.date(from: dobComponents) {
                editDateOfBirth = date
            }
        } catch {
            logger.debug("Could not read date of birth: \(error.localizedDescription)")
        }
    }

    // MARK: - Save Edits

    func saveProfileEdits() async {
        let body = UpdateProfileBody(
            firstName: editFirstName,
            lastName: editLastName,
            dateOfBirth: ISO8601DateFormatter.standard.string(from: editDateOfBirth),
            heightInches: editHeightInches,
            weightLbs: editWeightLbs
        )

        do {
            let _: ProfileDTO = try await apiClient.request(
                APIEndpoint.Users.updateProfile(body)
            )
            await loadProfile()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Existing Actions

    func signOut() async {
        await authManager.logout()
    }

    func requestDataExport() async {
        do {
            try await AccountDataExporter.exportMyData()
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

// MARK: - Update Profile Body

struct UpdateProfileBody: Encodable {
    let firstName: String
    let lastName: String
    let dateOfBirth: String
    let heightInches: Double
    let weightLbs: Double
}

// MARK: - Account Data Export

enum AccountDataExportError: LocalizedError {
    case invalidPayload
    case presentationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "The export payload was invalid."
        case .presentationUnavailable:
            return "Could not present the share sheet."
        }
    }
}

enum AccountDataExporter {
    static func exportMyData() async throws {
        let rawResponse = try await APIClient.shared.requestRaw(APIEndpoint.Users.export)
        let prettyPrintedData = try makePrettyPrintedExportData(from: rawResponse)
        let fileURL = try writeExportFile(data: prettyPrintedData)
        try await presentShareSheet(fileURL: fileURL)
    }

    private static func makePrettyPrintedExportData(from rawResponse: Data) throws -> Data {
        let jsonObject = try JSONSerialization.jsonObject(with: rawResponse, options: [])

        guard
            let root = jsonObject as? [String: Any],
            let exportPayload = root["data"]
        else {
            throw AccountDataExportError.invalidPayload
        }

        return try JSONSerialization.data(
            withJSONObject: exportPayload,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private static func writeExportFile(data: Data) throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GearSnitch-Data-Export-\(timestamp)")
            .appendingPathExtension("json")

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    @MainActor
    private static func presentShareSheet(fileURL: URL) throws {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let rootViewController = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            throw AccountDataExportError.presentationUnavailable
        }

        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootViewController.view
            popover.sourceRect = CGRect(
                x: rootViewController.view.bounds.midX,
                y: rootViewController.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }

        topViewController(from: rootViewController).present(activityVC, animated: true)
    }

    @MainActor
    private static func topViewController(from root: UIViewController) -> UIViewController {
        var current = root

        while let presented = current.presentedViewController {
            current = presented
        }

        return current
    }
}

// MARK: - API Endpoint Extension

extension APIEndpoint.Users {
    static func updateProfile(_ body: UpdateProfileBody) -> APIEndpoint {
        APIEndpoint(path: "/api/v1/users/me/profile", method: .PATCH, body: body)
    }
}
