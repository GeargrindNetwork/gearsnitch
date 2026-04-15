import SwiftUI

struct AlertsView: View {
    @EnvironmentObject var syncManager: WatchSessionManager

    var body: some View {
        VStack(spacing: 12) {
            if syncManager.activeAlertCount > 0 {
                alertsActive
            } else {
                allClear
            }
        }
        .containerBackground(for: .tabView) {
            Color.black
        }
    }

    // MARK: - Alerts Active

    private var alertsActive: some View {
        VStack(spacing: 10) {
            ZStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
            }

            Text("\(syncManager.activeAlertCount) Active Alert\(syncManager.activeAlertCount == 1 ? "" : "s")")
                .font(.headline)
                .foregroundColor(.white)

            if let message = syncManager.latestAlertMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            Text("Open iPhone for details")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    // MARK: - All Clear

    private var allClear: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.largeTitle)
                .foregroundColor(.green)

            Text("All Clear")
                .font(.headline)
                .foregroundColor(.white)

            Text("No active device alerts")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    AlertsView()
        .environmentObject(WatchSessionManager.shared)
}
