import SwiftUI

/// Gear tab — paired devices, gear components (retirement + mileage),
/// default gear per activity, pairing flow. Aggregates existing feature
/// views; does **not** re-implement any of them. Per S2 PRD the legacy
/// DashboardView lives here as the summary surface while component
/// inventory / defaults / pairing are exposed via inline cards + links.
struct GearTabView: View {

    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        // DashboardView already composes gym session, HR, alerts, and
        // quick actions. Per the S2 PRD (Tab 1 — Gear) this is the
        // canonical landing surface for the Gear pillar; the Gear
        // inventory + defaults + pairing flow are reachable via the
        // cards below and the existing dashboard quick actions.
        ScrollView {
            VStack(spacing: 16) {
                DashboardEmbedView()

                gearQuickLinksSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Gear")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Quick links

    private var gearQuickLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gear management")
                .font(.headline)
                .foregroundColor(.gsText)

            quickLinkCard(
                icon: "shippingbox.fill",
                title: "Components & mileage",
                subtitle: "Chains, shoes, tires — retirement thresholds",
                color: .gsEmerald
            ) {
                GearListView()
            }

            quickLinkCard(
                icon: "slider.horizontal.3",
                title: "Default gear per activity",
                subtitle: "Auto-assign gear when a workout starts",
                color: .gsCyan
            ) {
                DefaultGearPerActivityView()
            }

            quickLinkCard(
                icon: "antenna.radiowaves.left.and.right",
                title: "Pair new device",
                subtitle: "AccessorySetupKit one-tap pairing",
                color: .gsWarning
            ) {
                DevicePairingView()
            }
        }
        .padding(.top, 8)
    }

    private func quickLinkCard<Destination: View>(
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

/// Thin wrapper so we can host `DashboardView` without the dashboard's
/// own NavigationStack / nav bar fighting ours.
private struct DashboardEmbedView: View {
    var body: some View {
        DashboardView()
            // DashboardView sets its own .navigationTitle("Dashboard") — in
            // our Gear tab context we prefer the tab title instead. We
            // don't strip it here because DashboardView handles its
            // own nav modifiers; SwiftUI composes cleanly with the
            // outer NavigationStack's title owning the bar.
    }
}

#Preview {
    NavigationStack {
        GearTabView()
            .environmentObject(AppCoordinator())
    }
    .preferredColorScheme(.dark)
}
