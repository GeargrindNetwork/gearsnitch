import SwiftUI
import UIKit

struct ActiveRunView: View {
    @ObservedObject private var manager = RunTrackingManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showEndConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if let activeRun = manager.activeRun {
                activeRunContent(activeRun)
            } else {
                startRunContent
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Finish Run?", isPresented: $showEndConfirmation) {
            Button("Finish & Save", role: .destructive) {
                Task {
                    await manager.stopRun()
                    if manager.activeRun == nil {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current route and timing snapshot will be saved to your run history.")
        }
        .alert("Run Tracking", isPresented: Binding(
            get: { manager.error != nil },
            set: { if !$0 { manager.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(manager.error ?? "Unknown error")
        }
    }

    private var startRunContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)

                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(Color.gsBrandGradient)

                VStack(spacing: 10) {
                    Text("Track an outdoor run")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.gsText)

                    Text("GearSnitch will record your live route, pace, and distance while location access is available.")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                permissionCard

                Button {
                    Task { await manager.startRun() }
                } label: {
                    Text(manager.isStarting ? "Starting..." : "Start Run")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.gsEmerald)
                        .cornerRadius(16)
                }
                .disabled(manager.isStarting || !manager.isAuthorizedForTracking)
                .opacity(manager.isStarting || !manager.isAuthorizedForTracking ? 0.55 : 1)
                .padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location Access")
                .font(.caption.weight(.medium))
                .foregroundColor(.gsTextSecondary)

            Text(permissionMessage)
                .font(.subheadline)
                .foregroundColor(.gsText)

            HStack(spacing: 12) {
                Button("Request Access") {
                    manager.requestPermission()
                }
                .buttonStyle(.bordered)
                .tint(.gsEmerald)

                if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .padding(.horizontal, 24)
    }

    private func activeRunContent(_ activeRun: ActiveRunSession) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                if let banner = manager.autoPauseBanner {
                    AutoPauseBannerView(
                        state: banner,
                        onAutoDismiss: { manager.clearAutoPauseBanner() },
                        onForceResume: { manager.forceResume() }
                    )
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                VStack(spacing: 6) {
                    Text(activeRun.durationString)
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .foregroundColor(activeRun.isPaused ? .gsWarning : .gsEmerald)

                    Text(statusLabel(for: activeRun))
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
                .padding(.top, 20)

                HStack(spacing: 12) {
                    statCard(title: "Distance", value: activeRun.distanceString)
                    statCard(title: "Pace", value: activeRun.paceString)
                }

                if activeRun.routePoints.count >= 2 {
                    RunRouteMap(route: activeRun.routeSummary)
                        .frame(height: 280)
                        .cardStyle(padding: 0)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "location.slash")
                            .font(.title2)
                            .foregroundColor(.gsTextSecondary)
                        Text("Move to begin plotting your route.")
                            .font(.subheadline)
                            .foregroundColor(.gsTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .cardStyle()
                }

                VStack(spacing: 0) {
                    detailRow(label: "Captured Points", value: "\(activeRun.routePoints.count)")
                    Divider().background(Color.gsBorder)
                    detailRow(label: "Status", value: activeRun.isEndingPending ? "Pending save" : (activeRun.isPaused ? "Auto-paused" : "Recording"))
                    Divider().background(Color.gsBorder)
                    detailRow(label: "Started", value: activeRun.startedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .cardStyle(padding: 0)

                HStack(spacing: 12) {
                    Button {
                        manager.requestPermission()
                    } label: {
                        Text("Permissions")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gsEmerald)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.gsEmerald.opacity(0.12))
                            .cornerRadius(14)
                    }

                    Button {
                        showEndConfirmation = true
                    } label: {
                        Text(manager.isStopping ? "Saving..." : (activeRun.isEndingPending ? "Retry Save" : "Finish"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 120, height: 48)
                            .background(Color.gsDanger)
                            .cornerRadius(14)
                    }
                    .disabled(manager.isStopping)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func statusLabel(for run: ActiveRunSession) -> String {
        if run.isEndingPending { return "Awaiting Save" }
        if run.isPaused { return "Auto-paused" }
        return "Elapsed Time"
    }

    private var permissionMessage: String {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            return "Always-on tracking is enabled. Route capture can continue reliably when the app is backgrounded."
        case .authorizedWhenInUse:
            return "Tracking works while the app stays active. Upgrade to Always if you want stronger background resilience."
        case .denied, .restricted:
            return "Location is blocked right now. Enable it in Settings before starting a run."
        case .notDetermined:
            return "Allow location access to start tracking distance, pace, and route geometry."
        @unknown default:
            return "Review location access before starting a run."
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.gsTextSecondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(.gsText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        ActiveRunView()
    }
    .preferredColorScheme(.dark)
}
