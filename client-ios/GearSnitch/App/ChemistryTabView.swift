import SwiftUI

/// Chemistry tab — the longitudinal-health pillar.
///
/// Per S2 PRD (Tab 3 — Chemistry) this aggregates:
/// - Peptide / medication dose log (DosingCalculator + HealthKit Medications)
/// - Cycle planner (CycleTrackingView)
/// - Labs (ScheduleLabsView — currently stubbed; Rupa integration next)
/// - Health metrics (HealthDashboardView — HR history, weight, biomarkers)
/// - ECG viewer (ECGView)
/// - Hospitals card (demoted per S2 PRD from primary nav to Chemistry card)
/// - BMI calculator (nested under health metrics per S4 direction)
struct ChemistryTabView: View {

    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        // HealthDashboardView already surfaces metrics grid, trends,
        // ECG, cycles, and BMI links. We embed it as the primary body
        // and layer Chemistry-specific quick links (dosing, labs,
        // hospitals) above it.
        ScrollView {
            VStack(spacing: 16) {
                chemistryQuickLinksSection

                HealthDashboardView()
                    .frame(minHeight: 600)
            }
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Chemistry")
        .navigationBarTitleDisplayMode(.large)
    }

    private var chemistryQuickLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chemistry")
                .font(.headline)
                .foregroundColor(.gsText)
                .padding(.horizontal, 16)

            VStack(spacing: 10) {
                chemistryLink(
                    icon: "syringe.fill",
                    title: "Dosing log",
                    subtitle: "Peptide / medication log + HealthKit sync",
                    color: .gsEmerald
                ) {
                    DosingCalculatorView()
                }

                chemistryLink(
                    icon: "staroflife.fill",
                    title: "Labs",
                    subtitle: "Schedule draws (Rupa integration coming)",
                    color: .gsCyan
                ) {
                    ScheduleLabsView()
                }

                chemistryLink(
                    icon: "cross.case.fill",
                    title: "Nearest hospitals",
                    subtitle: "Emergency-adjacent safety net",
                    color: .gsDanger
                ) {
                    NearestHospitalsView()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chemistryLink<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.12))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gsTextSecondary)
            }
            .padding(14)
            .background(Color.gsSurface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gsBorder, lineWidth: 1))
        }
    }
}

#Preview {
    NavigationStack {
        ChemistryTabView()
            .environmentObject(AppCoordinator())
    }
    .preferredColorScheme(.dark)
}
