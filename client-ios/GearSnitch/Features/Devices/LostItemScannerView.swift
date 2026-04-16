import NearbyInteraction
import SwiftUI

// MARK: - Lost Item Scanner View

struct LostItemScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner: LostItemScannerViewModel

    init(device: BLEDevice? = nil) {
        _scanner = StateObject(wrappedValue: LostItemScannerViewModel(targetDevice: device))
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Radial edge glow — top half
            radialGlow
                .ignoresSafeArea()

            // Center content
            VStack(spacing: 24) {
                Spacer()

                // Device icon
                deviceIcon

                // Device name
                Text(scanner.targetDeviceName ?? "Scanning...")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                // Distance / signal info
                signalInfo

                // Direction hint (UWB)
                if let direction = scanner.directionHint {
                    Text(direction)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                }

                Spacer()

                // Status text
                Text(scanner.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Stop button
                Button {
                    scanner.stopScanning()
                    dismiss()
                } label: {
                    Text("Stop Scanning")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.ultraThinMaterial)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            scanner.startScanning()
        }
        .onDisappear {
            scanner.stopScanning()
        }
    }

    // MARK: - Radial Glow

    private var radialGlow: some View {
        let glowColor = scanner.proximityColor

        return VStack {
            ZStack {
                // Outer glow ring — edges of screen
                RadialGradient(
                    gradient: Gradient(colors: [
                        glowColor.opacity(0.6),
                        glowColor.opacity(0.3),
                        glowColor.opacity(0.1),
                        Color.clear,
                    ]),
                    center: .top,
                    startRadius: 0,
                    endRadius: 500
                )
                .frame(height: UIScreen.main.bounds.height * 0.55)

                // Edge glow left + right
                HStack {
                    LinearGradient(
                        colors: [glowColor.opacity(0.4), Color.clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 80)

                    Spacer()

                    LinearGradient(
                        colors: [Color.clear, glowColor.opacity(0.4)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 80)
                }
                .frame(height: UIScreen.main.bounds.height * 0.55)
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.5), value: scanner.proximityLevel)
    }

    // MARK: - Device Icon

    private var deviceIcon: some View {
        ZStack {
            // Pulsing ring
            Circle()
                .stroke(scanner.proximityColor.opacity(0.3), lineWidth: 2)
                .frame(width: 120, height: 120)
                .scaleEffect(scanner.isPulsing ? 1.3 : 1.0)
                .opacity(scanner.isPulsing ? 0.0 : 0.6)
                .animation(
                    .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                    value: scanner.isPulsing
                )

            Circle()
                .fill(scanner.proximityColor.opacity(0.15))
                .frame(width: 100, height: 100)

            Image(systemName: scanner.deviceIconName)
                .font(.system(size: 40))
                .foregroundColor(scanner.proximityColor)
        }
    }

    // MARK: - Signal Info

    private var signalInfo: some View {
        VStack(spacing: 6) {
            Text(scanner.proximityLabel)
                .font(.title3.weight(.semibold))
                .foregroundColor(scanner.proximityColor)

            if let rssi = scanner.currentRSSI {
                Text("\(rssi) dBm")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            if let distance = scanner.estimatedDistance {
                Text(String(format: "~%.1f m", distance))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Lost Item Scanner ViewModel

@MainActor
final class LostItemScannerViewModel: NSObject, ObservableObject {

    @Published var proximityLevel: ProximityLevel = .unknown
    @Published var proximityColor: Color = .red
    @Published var proximityLabel: String = "Searching..."
    @Published var currentRSSI: Int?
    @Published var estimatedDistance: Double?
    @Published var directionHint: String?
    @Published var targetDeviceName: String?
    @Published var deviceIconName: String = "sensor.tag.radiowaves.forward"
    @Published var statusMessage: String = "Move around slowly to locate your device"
    @Published var isPulsing = false
    @Published var isScanning = false

    private var targetDevice: BLEDevice?
    private var niSession: NISession?
    private var rssiHistory: [Int] = []

    enum ProximityLevel: Int {
        case unknown = 0
        case far = 1
        case medium = 2
        case near = 3
        case immediate = 4
    }

    init(targetDevice: BLEDevice? = nil) {
        self.targetDevice = targetDevice
        super.init()

        if let device = targetDevice {
            self.targetDeviceName = device.displayName
            self.deviceIconName = iconForDevice(device)
        }
    }

    func startScanning() {
        isScanning = true
        isPulsing = true

        // If no target specified, find the first lost device
        if targetDevice == nil {
            let lostDevices = BLEManager.shared.connectedDevices + BLEManager.shared.discoveredDevices
            if let lost = lostDevices.first(where: { $0.status == .disconnected || $0.status == .lost }) {
                targetDevice = lost
                targetDeviceName = lost.displayName
                deviceIconName = iconForDevice(lost)
            }
        }

        // Start BLE scanning for the target
        BLEManager.shared.startScanning(mode: .monitoring)

        // Start UWB session if available
        startNearbyInteraction()

        // Start RSSI monitoring
        startRSSIPolling()
    }

    func stopScanning() {
        isScanning = false
        isPulsing = false
        niSession?.invalidate()
        niSession = nil
        BLEManager.shared.stopScanning()
    }

    // MARK: - RSSI Monitoring

    private func startRSSIPolling() {
        Task { @MainActor in
            while isScanning {
                try? await Task.sleep(for: .milliseconds(500))
                guard isScanning else { break }
                updateProximityFromRSSI()
            }
        }
    }

    private func updateProximityFromRSSI() {
        guard let target = targetDevice else { return }

        // Find the device in discovered or connected lists
        let allDevices = BLEManager.shared.discoveredDevices + BLEManager.shared.connectedDevices
        guard let found = allDevices.first(where: { $0.identifier == target.identifier }) else {
            proximityLevel = .unknown
            proximityColor = .red
            proximityLabel = "Searching..."
            statusMessage = "Move around slowly to locate your device"
            currentRSSI = nil
            estimatedDistance = nil
            return
        }

        let rssi = found.rssi
        currentRSSI = rssi
        rssiHistory.append(rssi)
        if rssiHistory.count > 10 {
            rssiHistory.removeFirst()
        }

        // Smoothed RSSI
        let smoothed = rssiHistory.reduce(0, +) / rssiHistory.count

        // Estimate distance from RSSI (rough approximation)
        // Using log-distance path loss model: d = 10^((txPower - rssi) / (10 * n))
        let txPower: Double = -59 // typical BLE tx power at 1m
        let n: Double = 2.5 // path loss exponent
        let distance = pow(10.0, (txPower - Double(smoothed)) / (10.0 * n))
        estimatedDistance = distance

        // Classify proximity
        switch smoothed {
        case -40...0:
            proximityLevel = .immediate
            proximityColor = .green
            proximityLabel = "Right Here!"
            statusMessage = "Your device is within arm's reach"
        case -55 ..< -40:
            proximityLevel = .near
            proximityColor = Color(red: 0.4, green: 0.9, blue: 0.2) // yellow-green
            proximityLabel = "Very Close"
            statusMessage = "Getting warmer — keep moving this direction"
        case -70 ..< -55:
            proximityLevel = .medium
            proximityColor = .orange
            proximityLabel = "Nearby"
            statusMessage = "You're in the right area — look around"
        case -85 ..< -70:
            proximityLevel = .far
            proximityColor = Color(red: 1.0, green: 0.4, blue: 0.2) // red-orange
            proximityLabel = "Far"
            statusMessage = "Keep moving — signal is weak"
        default:
            proximityLevel = .far
            proximityColor = .red
            proximityLabel = "Very Far"
            statusMessage = "Move around slowly to locate your device"
        }
    }

    // MARK: - Nearby Interaction (UWB)

    private func startNearbyInteraction() {
        guard NISession.deviceCapabilities.supportsDirectionMeasurement else {
            directionHint = nil
            return
        }

        niSession = NISession()
        niSession?.delegate = self
    }

    private func iconForDevice(_ device: BLEDevice) -> String {
        let name = device.name.lowercased()
        if name.contains("airpod") { return "airpodspro" }
        if name.contains("watch") { return "applewatch" }
        if name.contains("bag") { return "bag" }
        if name.contains("belt") { return "figure.strengthtraining.traditional" }
        return "sensor.tag.radiowaves.forward"
    }
}

// MARK: - NISessionDelegate

extension LostItemScannerViewModel: NISessionDelegate {
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { @MainActor in
            guard let nearest = nearbyObjects.first else { return }

            if let distance = nearest.distance {
                estimatedDistance = Double(distance)
            }

            if let direction = nearest.direction {
                let angle = atan2(direction.x, direction.z) * 180 / .pi
                if abs(angle) < 15 {
                    directionHint = "Straight ahead"
                } else if angle > 0 {
                    directionHint = "Turn right"
                } else {
                    directionHint = "Turn left"
                }
            }
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in
            directionHint = nil
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {}
    nonisolated func sessionSuspensionEnded(_ session: NISession) {}
}

#Preview {
    LostItemScannerView()
        .preferredColorScheme(.dark)
}
