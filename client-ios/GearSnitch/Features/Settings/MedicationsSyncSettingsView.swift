import SwiftUI
import os

/// Small Medications sub-section inside Settings: lets the user opt in /
/// out of two-way HealthKit Medications sync (item #7). Off by default.
/// On first toggle → requests HealthKit authorization. The choice is
/// persisted locally in `UserDefaults` (via
/// `HealthKitMedicationsPreference`) AND pushed to
/// `User.preferences.custom["healthKitMedicationsSync"]` so it survives
/// reinstall.
struct MedicationsSyncSettingsView: View {

    @State private var isEnabled: Bool = HealthKitMedicationsPreference.isEnabled
    @State private var isRequesting = false
    @State private var errorMessage: String?

    private let logger = Logger(
        subsystem: "com.gearsnitch",
        category: "MedicationsSyncSettings"
    )

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        Task { await handleToggle(newValue) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sync with Apple Health")
                            .foregroundColor(.gsText)
                        Text("Two-way sync for peptide and medication doses.")
                            .font(.footnote)
                            .foregroundColor(.gsTextSecondary)
                    }
                }
                .tint(.gsEmerald)
                .disabled(isRequesting)
            } header: {
                Text("Apple Health")
                    .foregroundColor(.gsTextSecondary)
            } footer: {
                Text(
                    "When on, every dose you log in GearSnitch is written to Apple Health, and doses logged in other apps are pulled in on app open. Off by default."
                )
                .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Medications")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Could not enable sync",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
    }

    @MainActor
    private func handleToggle(_ newValue: Bool) async {
        // Optimistic local toggle — we revert on authorization failure.
        isEnabled = newValue
        HealthKitMedicationsPreference.setEnabled(newValue)

        guard newValue else {
            logger.info("HealthKit Medications sync disabled by user")
            return
        }

        isRequesting = true
        defer { isRequesting = false }

        do {
            try await HealthKitMedicationsSync.shared.requestAuthorization()
            logger.info("HealthKit Medications authorization granted")
        } catch {
            logger.error(
                "HealthKit Medications authorization failed: \(error.localizedDescription, privacy: .public)"
            )
            isEnabled = false
            HealthKitMedicationsPreference.setEnabled(false)
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        MedicationsSyncSettingsView()
    }
    .preferredColorScheme(.dark)
}
#endif
