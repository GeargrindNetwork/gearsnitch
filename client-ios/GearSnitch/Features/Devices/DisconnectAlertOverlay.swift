import SwiftUI
import os

// MARK: - Disconnect Alert State

enum DisconnectAlertPhase {
    case countdown(secondsRemaining: Int)
    case silencePrompt
    case actionChoice
}

// MARK: - Disconnect Alert Overlay

fileprivate let perfLog = Logger(subsystem: "com.your.bundle", category: "performance")
fileprivate let signposter = OSSignposter(subsystem: "com.your.bundle", category: "ui")

struct DisconnectAlertOverlay: View {
    let deviceName: String
    let deviceIdentifier: UUID
    let onTrackItem: () -> Void
    let onDisregard: () -> Void
    let onDismissed: () -> Void

    @ObservedObject private var bleManager = BLEManager.shared
    @State private var phase: DisconnectAlertPhase = .countdown(secondsRemaining: 20)
    @State private var countdownTask: Task<Void, Never>?
    
    // Signpost ID for countdown interval
    @State private var countdownSignpostID: OSSignpostID = signposter.makeSignpostID()

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { /* block taps */ }

            VStack(spacing: 0) {
                Spacer()

                // Alert icon
                alertIcon

                // Device name
                Text(deviceName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.top, 16)

                Text("has disconnected")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 4)

                Spacer()

                // Phase-specific content
                phaseContent
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            perfLog.info("DisconnectAlertOverlay appeared for device: \(self.deviceName, privacy: .public) \(self.deviceIdentifier.uuidString, privacy: .public)")
            countdownSignpostID = signposter.makeSignpostID()
            startCountdown()
        }
        .onDisappear {
            perfLog.info("DisconnectAlertOverlay disappeared for device: \(self.deviceName, privacy: .public)")
            countdownTask?.cancel()
        }
        .onChange(of: bleManager.connectedDevices.map(\.identifier)) { connected in
            perfLog.info("Connected devices changed. Monitoring reconnection for: \(self.deviceIdentifier.uuidString, privacy: .public)")
            // Auto-clear if device reconnects
            if connected.contains(deviceIdentifier) {
                perfLog.info("Device reconnected: \(self.deviceIdentifier.uuidString, privacy: .public). Dismissing overlay.")
                signposter.emitEvent("DeviceReconnected", id: countdownSignpostID)
                countdownTask?.cancel()
                DisconnectProtectionActivityManager.shared.clearCountdown()
                onDismissed()
            }
        }
    }

    // MARK: - Alert Icon

    private var alertIcon: some View {
        ZStack {
            Circle()
                .fill(Color.gsDanger.opacity(0.15))
                .frame(width: 100, height: 100)

            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundColor(.gsDanger)
        }
    }

    // MARK: - Phase Content

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .countdown(let seconds):
            countdownView(seconds)
        case .silencePrompt:
            silenceView
        case .actionChoice:
            actionChoiceView
        }
    }

    // MARK: - Phase 1: Countdown

    private func countdownView(_ seconds: Int) -> some View {
        VStack(spacing: 20) {
            // Countdown ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 4)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: CGFloat(seconds) / 20.0)
                    .stroke(Color.gsDanger, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: seconds)

                Text("\(seconds)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }

            Text("Attempting to reconnect...")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))

            Text("Alarm will sound if device is not found")
                .font(.caption2)
                .foregroundColor(.gsDanger.opacity(0.7))
        }
    }

    // MARK: - Phase 2: Silence Prompt

    private var silenceView: some View {
        VStack(spacing: 16) {
            Text("Device Not Found")
                .font(.headline)
                .foregroundColor(.gsDanger)

            Button {
                perfLog.info("Silence Alarm tapped for device: \(self.deviceIdentifier.uuidString, privacy: .public)")
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = .actionChoice
                }
                // Silence alarm audio
                PanicAlarmManager.shared.silencePanic()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.slash.fill")
                    Text("Silence Alarm")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.gsDanger)
                .cornerRadius(14)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Phase 3: Track / Disregard

    private var actionChoiceView: some View {
        VStack(spacing: 12) {
            Text("What would you like to do?")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            Button {
                perfLog.info("Track Item tapped for device: \(self.deviceIdentifier.uuidString, privacy: .public)")
                countdownTask?.cancel()
                onTrackItem()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.viewfinder")
                    Text("Track Item")
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.gsEmerald)
                .cornerRadius(14)
            }
            .padding(.horizontal, 24)

            Button {
                perfLog.info("Disregard tapped for device: \(self.deviceIdentifier.uuidString, privacy: .public)")
                countdownTask?.cancel()
                onDisregard()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                    Text("Disregard")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsTextSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .padding(.horizontal, 24)

            Text("Accidentally disconnected? Your device may have moved out of range.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Countdown Logic

    private func startCountdown() {
        countdownTask = Task { @MainActor in
            let beginState = signposter.beginInterval("DisconnectCountdown", id: countdownSignpostID)
            perfLog.info("Countdown started for device: \(self.deviceIdentifier.uuidString, privacy: .public)")
            for second in stride(from: 20, through: 1, by: -1) {
                signposter.emitEvent("CountdownTick", id: countdownSignpostID)
                perfLog.debug("Countdown tick: \(second) for device: \(self.deviceIdentifier.uuidString, privacy: .public)")
                guard !Task.isCancelled else { return }
                phase = .countdown(secondsRemaining: second)

                // Update Dynamic Island countdown
                DisconnectProtectionActivityManager.shared.updateCountdown(
                    seconds: second,
                    deviceName: deviceName
                )

                try? await Task.sleep(for: .seconds(1))
            }

            // Countdown finished — clear island countdown, trigger alarm, show silence button
            guard !Task.isCancelled else { return }
            signposter.endInterval("DisconnectCountdown", beginState)
            perfLog.info("Countdown finished for device: \(self.deviceIdentifier.uuidString, privacy: .public)")
            DisconnectProtectionActivityManager.shared.clearCountdown()
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = .silencePrompt
            }

            perfLog.info("Searching for device to trigger alarm: \(self.deviceIdentifier.uuidString, privacy: .public)")
            // Trigger audio alarm if we can find the BLE device
            let allDevices = BLEManager.shared.discoveredDevices + BLEManager.shared.connectedDevices
            if let device = allDevices.first(where: { $0.identifier == deviceIdentifier }) {
                perfLog.info("Triggering panic alarm for device: \(self.deviceIdentifier.uuidString, privacy: .public)")
                PanicAlarmManager.shared.triggerPanic(device: device)
            } else {
                perfLog.warning("Device not found in discovered/connected list: \(self.deviceIdentifier.uuidString, privacy: .public)")
            }
        }
    }
}

#Preview {
    DisconnectAlertOverlay(
        deviceName: "AirPods Pro",
        deviceIdentifier: UUID(),
        onTrackItem: {},
        onDisregard: {},
        onDismissed: {}
    )
}
