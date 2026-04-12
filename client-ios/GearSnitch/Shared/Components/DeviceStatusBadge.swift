import SwiftUI

// MARK: - Device Connection Status

enum DeviceConnectionStatus: String, CaseIterable {
    case connected
    case disconnected
    case reconnecting
    case inactive
}

// MARK: - Device Status Badge

/// Small circle badge indicating BLE device connection state.
struct DeviceStatusBadge: View {
    let status: DeviceConnectionStatus
    var size: CGFloat = 10

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(statusColor.opacity(0.4), lineWidth: status == .reconnecting ? 2 : 0)
                    .frame(width: size + 6, height: size + 6)
                    .scaleEffect(isPulsing ? 1.6 : 1.0)
                    .opacity(isPulsing ? 0 : 1)
            )
            .onAppear {
                if status == .reconnecting {
                    withAnimation(
                        .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: false)
                    ) {
                        isPulsing = true
                    }
                }
            }
            .onChange(of: status) { _, newStatus in
                if newStatus == .reconnecting {
                    isPulsing = false
                    withAnimation(
                        .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: false)
                    ) {
                        isPulsing = true
                    }
                } else {
                    isPulsing = false
                }
            }
    }

    private var statusColor: Color {
        switch status {
        case .connected:    return .gsSuccess
        case .disconnected: return .gsDanger
        case .reconnecting: return .gsWarning
        case .inactive:     return .gsTextSecondary
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        VStack(spacing: 8) {
            DeviceStatusBadge(status: .connected)
            Text("Connected").font(.caption2)
        }
        VStack(spacing: 8) {
            DeviceStatusBadge(status: .disconnected)
            Text("Disconnected").font(.caption2)
        }
        VStack(spacing: 8) {
            DeviceStatusBadge(status: .reconnecting)
            Text("Reconnecting").font(.caption2)
        }
        VStack(spacing: 8) {
            DeviceStatusBadge(status: .inactive)
            Text("Inactive").font(.caption2)
        }
    }
    .foregroundColor(.gsTextSecondary)
    .padding()
    .background(Color.gsBackground)
    .preferredColorScheme(.dark)
}
