import SwiftUI

// MARK: - TopNavBar
//
// Single shared top-right button cluster used by every top-level screen so
// the button stack is consistent and never overlaps. The cluster is
// layered as an overlay above the standard nav-bar so we control its
// exact position and ordering.
//
// Button order, right-to-left:
//   1. Profile avatar        (farthest right, always present)
//   2. QR referral icon      (optional)
//   3. Cart icon             (optional)
//
// A Disarm chip sits BELOW the profile avatar (so it does not collide
// with cart / QR). "Add Run" style FABs should be rendered as bottom
// trailing overlays via `TopNavBarContainer` using the `bottomTrailingFab`
// slot — they are explicitly forbidden from the top-right cluster.
//
// This is intentionally a pure overlay + not a `.toolbar { ... }` so each
// tab can opt-in without needing its own `ToolbarItem` plumbing and so
// iOS's toolbar auto-compression never drops one of the buttons.

struct TopNavBarConfig {
    var showCart: Bool = false
    var showReferral: Bool = true
    var showProfile: Bool = true
    /// Master gate — displays the disarm chip only when the alarm system
    /// is armed. The tap still fires even when disabled so we can show
    /// the "pair a device first" sheet (see AlarmGate below).
    var showDisarm: Bool = false
    /// If true, the disarm button is rendered greyed out and taps show the
    /// pair-device prompt instead of disarming.
    var isDisarmDisabled: Bool = false
}

struct TopNavBar: View {

    let config: TopNavBarConfig
    let onProfileTap: () -> Void
    let onReferralTap: () -> Void
    let onCartTap: () -> Void
    let onDisarmTap: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 10) {
                if config.showCart {
                    iconButton(systemImage: "cart", label: "Open cart", action: onCartTap)
                        .accessibilityIdentifier("topNavBar.cart")
                }
                if config.showReferral {
                    iconButton(systemImage: "qrcode", label: "Show referral QR code", action: onReferralTap)
                        .accessibilityIdentifier("topNavBar.referral")
                }
                if config.showProfile {
                    profileButton
                        .accessibilityIdentifier("topNavBar.profile")
                }
            }

            if config.showDisarm {
                disarmChip
                    .accessibilityIdentifier("topNavBar.disarm")
            }
        }
        .padding(.trailing, 14)
        .padding(.top, 6)
    }

    // MARK: - Subviews

    private var profileButton: some View {
        Button(action: onProfileTap) {
            ZStack {
                Circle()
                    .fill(Color.gsEmerald.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.gsEmerald)
            }
        }
        .accessibilityLabel("Open account menu")
    }

    private var disarmChip: some View {
        Button(action: onDisarmTap) {
            HStack(spacing: 4) {
                Image(systemName: config.isDisarmDisabled ? "lock.fill" : "lock.open.fill")
                    .font(.caption)
                Text(config.isDisarmDisabled ? "Locked" : "Disarm")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (config.isDisarmDisabled ? Color.gsTextSecondary : Color.red)
                    .opacity(0.85)
            )
            .cornerRadius(8)
        }
        .accessibilityLabel(config.isDisarmDisabled ? "Alarm requires a paired device" : "Disarm alarm system")
    }

    private func iconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.gsSurface.opacity(0.9))
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gsEmerald)
            }
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Container modifier

/// Wraps an arbitrary view in a `ZStack` overlay that layers the shared
/// `TopNavBar` at the top-trailing corner and an optional FAB at the
/// bottom-trailing. Every top-level screen applies this rather than
/// rolling its own .toolbar so the button order is identical everywhere.
struct TopNavBarContainer<Content: View, Fab: View>: View {

    let config: TopNavBarConfig
    let onProfileTap: () -> Void
    let onReferralTap: () -> Void
    let onCartTap: () -> Void
    let onDisarmTap: () -> Void
    @ViewBuilder let bottomTrailingFab: () -> Fab
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content()

            TopNavBar(
                config: config,
                onProfileTap: onProfileTap,
                onReferralTap: onReferralTap,
                onCartTap: onCartTap,
                onDisarmTap: onDisarmTap
            )

            // Bottom-right FAB slot (e.g. "Add Run"). Kept as an overlay
            // so it never competes with the top-right cluster.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    bottomTrailingFab()
                        .padding(.trailing, 16)
                        .padding(.bottom, 24)
                }
            }
        }
    }
}

extension TopNavBarContainer where Fab == EmptyView {
    init(
        config: TopNavBarConfig,
        onProfileTap: @escaping () -> Void,
        onReferralTap: @escaping () -> Void,
        onCartTap: @escaping () -> Void,
        onDisarmTap: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.config = config
        self.onProfileTap = onProfileTap
        self.onReferralTap = onReferralTap
        self.onCartTap = onCartTap
        self.onDisarmTap = onDisarmTap
        self.bottomTrailingFab = { EmptyView() }
        self.content = content
    }
}

// MARK: - Preview

#Preview("Default") {
    ZStack {
        Color.gsBackground.ignoresSafeArea()
        TopNavBar(
            config: TopNavBarConfig(showCart: true, showReferral: true, showProfile: true, showDisarm: true),
            onProfileTap: {},
            onReferralTap: {},
            onCartTap: {},
            onDisarmTap: {}
        )
    }
    .preferredColorScheme(.dark)
}
