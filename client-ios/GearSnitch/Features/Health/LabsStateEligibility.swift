import Foundation

// MARK: - Labs State Eligibility
//
// Source-of-truth for which U.S. states are NOT permitted to order at-home
// lab testing through our partner (Rupa Health).
//
// Per Rupa Health policy (https://www.rupauniversity.com/faq), residents of
// New York (NY), New Jersey (NJ), and Rhode Island (RI) cannot use Rupa's
// direct-to-consumer lab ordering flow due to state regulations that prohibit
// patient-initiated laboratory testing without a prior in-state physician
// relationship. This is a legal-compliance requirement and must be enforced
// before any lab order is submitted.
//
// NOTE: This gate is an iOS-side UX guard. Backend enforcement is a follow-up.

enum LabsStateEligibility {

    /// ISO-style 2-letter USPS codes for states where Rupa Health (and most
    /// DTC lab integrations) cannot serve residents.
    /// Source: https://www.rupauniversity.com/faq
    static let restrictedStates: Set<String> = ["NY", "NJ", "RI"]

    /// Returns `true` when the supplied state code matches a restricted state.
    ///
    /// The check is:
    /// - trimmed of leading/trailing whitespace and newlines
    /// - case-insensitive (converted to uppercase before lookup)
    ///
    /// - Parameter stateCode: A USPS 2-letter state code (e.g. "NY", "ca").
    /// - Returns: `true` if the state is on the restricted list.
    static func isRestricted(_ stateCode: String) -> Bool {
        let normalized = stateCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return restrictedStates.contains(normalized)
    }
}
