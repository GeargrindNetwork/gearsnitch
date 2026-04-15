import SwiftUI

struct QuickActionsView: View {
    @EnvironmentObject var syncManager: WatchSessionManager

    var body: some View {
        VStack(spacing: 14) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.white)

            if let gymName = syncManager.defaultGymName, let gymId = syncManager.defaultGymId {
                if !syncManager.isSessionActive {
                    Button {
                        syncManager.sendSessionCommand(action: .start, gymId: gymId, gymName: gymName)
                    } label: {
                        Label("Start Session", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                } else {
                    Button {
                        syncManager.sendSessionCommand(action: .end, gymId: nil, gymName: nil)
                    } label: {
                        Label("End Session", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                }
            }

            Button {
                let enabled = !syncManager.isHeartRateMonitoring
                syncManager.sendHRMonitoringToggle(enabled: enabled)
            } label: {
                Label(
                    syncManager.isHeartRateMonitoring ? "Stop HR Monitor" : "Start HR Monitor",
                    systemImage: syncManager.isHeartRateMonitoring ? "heart.slash" : "heart"
                )
                .frame(maxWidth: .infinity)
            }
            .tint(syncManager.isHeartRateMonitoring ? .orange : .cyan)
        }
        .containerBackground(for: .tabView) {
            Color.black
        }
    }
}

#Preview {
    QuickActionsView()
        .environmentObject(WatchSessionManager.shared)
}
