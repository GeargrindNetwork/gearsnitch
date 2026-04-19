import SwiftUI

// MARK: - AutoPauseBannerView (Backlog item #18)
//
// Transient banner shown at the top of the active run view when the
// inactivity detector auto-pauses or auto-resumes the run. Auto
// dismisses after 3s; a tap invokes `onForceResume` which tells the
// RunTrackingManager to resume immediately and suppress the detector
// for 30s (so the user isn't re-paused the instant they tap).

struct AutoPauseBannerView: View {

    let state: RunTrackingManager.AutoPauseBannerState
    var autoDismissSeconds: TimeInterval = 3
    var onAutoDismiss: () -> Void = {}
    var onForceResume: () -> Void = {}

    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Button(action: onForceResume) {
            HStack(spacing: 12) {
                Image(systemName: systemImageName)
                    .font(.body.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
                if state == .paused {
                    Text("Tap to resume")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(for: state))
        .accessibilityHint(state == .paused ? "Double tap to resume the run." : "")
        .onAppear { scheduleDismiss() }
        .onChange(of: state) { _, _ in scheduleDismiss() }
        .onDisappear { dismissTask?.cancel() }
    }

    // MARK: - Static helpers (for snapshot-style unit tests)

    static func title(for state: RunTrackingManager.AutoPauseBannerState) -> String {
        switch state {
        case .paused: return "Auto-paused"
        case .resumed: return "Resumed"
        }
    }

    static func subtitle(for state: RunTrackingManager.AutoPauseBannerState) -> String {
        switch state {
        case .paused: return "You stopped moving — pace and distance are frozen."
        case .resumed: return "Tracking is back on."
        }
    }

    static func systemImageName(for state: RunTrackingManager.AutoPauseBannerState) -> String {
        switch state {
        case .paused: return "pause.circle.fill"
        case .resumed: return "play.circle.fill"
        }
    }

    static func accessibilityLabel(for state: RunTrackingManager.AutoPauseBannerState) -> String {
        "\(title(for: state)). \(subtitle(for: state))"
    }

    // MARK: - Private

    private var title: String { Self.title(for: state) }
    private var subtitle: String { Self.subtitle(for: state) }
    private var systemImageName: String { Self.systemImageName(for: state) }

    private var backgroundFill: Color {
        switch state {
        case .paused: return Color.gsWarning.opacity(0.92)
        case .resumed: return Color.gsEmerald.opacity(0.92)
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoDismissSeconds * 1_000_000_000))
            if !Task.isCancelled {
                onAutoDismiss()
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AutoPauseBannerView(state: .paused)
        AutoPauseBannerView(state: .resumed)
    }
    .padding()
    .background(Color.gsBackground)
    .preferredColorScheme(.dark)
}
