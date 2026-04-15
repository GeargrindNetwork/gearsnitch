import SwiftUI

struct HealthDashboardView: View {
    @StateObject private var viewModel = HealthDashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Sync status
                syncStatusBar

                // Metrics grid
                if viewModel.metrics.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    metricsGrid
                }

                // Trends card
                NavigationLink {
                    TrendsView()
                } label: {
                    trendsCard
                }

                // Quick links
                VStack(spacing: 12) {
                    NavigationLink {
                        CycleTrackingView()
                    } label: {
                        quickLinkRow(icon: "calendar.badge.clock", label: "Cycle Tracking", color: .gsWarning)
                    }

                    NavigationLink {
                        MetricsLogView()
                    } label: {
                        quickLinkRow(icon: "pencil.line", label: "Log Weight / Height", color: .gsEmerald)
                    }

                    NavigationLink {
                        BMICalculatorView()
                    } label: {
                        quickLinkRow(icon: "chart.bar.doc.horizontal", label: "BMI Calculator", color: .gsCyan)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if viewModel.isLoading && viewModel.metrics.isEmpty {
                LoadingView(message: "Reading HealthKit...")
            }
        }
        .task {
            await viewModel.loadMetrics()
        }
    }

    // MARK: - Sync Bar

    private var syncStatusBar: some View {
        HStack {
            if let date = viewModel.lastSyncDate {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.gsSuccess)
                Text("Synced \(date.relativeTimeString())")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            } else {
                Text("Not synced yet")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer()

            Button {
                Task { await viewModel.syncToServer() }
            } label: {
                if viewModel.isSyncing {
                    ProgressView()
                        .tint(.gsEmerald)
                        .scaleEffect(0.8)
                } else {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.gsEmerald)
                }
            }
            .disabled(viewModel.isSyncing)
        }
        .padding(12)
        .background(Color.gsSurface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(viewModel.metrics) { metric in
                metricCard(metric)
            }
        }
    }

    private func metricCard(_ metric: HealthMetric) -> some View {
        VStack(spacing: 8) {
            Image(systemName: metric.icon)
                .font(.title3)
                .foregroundColor(metricColor(metric.color))

            Text(formatValue(metric.value, unit: metric.unit))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.gsText)

            Text(metric.label)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(Color.gsSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }

    private func formatValue(_ value: Double, unit: String) -> String {
        if unit == "steps" {
            return "\(Int(value))"
        }
        if value == value.rounded() {
            return "\(Int(value)) \(unit)"
        }
        return String(format: "%.1f %@", value, unit)
    }

    private func metricColor(_ name: String) -> Color {
        switch name {
        case "emerald": return .gsEmerald
        case "cyan": return .gsCyan
        case "green": return .gsSuccess
        case "orange": return .gsWarning
        case "red": return .gsDanger
        case "purple": return .purple
        default: return .gsTextSecondary
        }
    }

    private func quickLinkRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 36)

            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .cardStyle()
    }

    // MARK: - Trends Card

    private var trendsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.gsDanger.opacity(0.2), Color.gsCyan.opacity(0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "chart.xyaxis.line")
                        .font(.title3)
                        .foregroundColor(.gsCyan)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Trends")
                        .font(.headline)
                        .foregroundColor(.gsText)

                    Text("Heart rate, HRV, workouts, weight & more")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            // Mini preview bars
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.gsDanger.opacity(0.6), Color.gsCyan.opacity(0.6)],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(height: CGFloat([18, 24, 20, 30, 26, 22, 28, 32, 24, 20, 26, 30][i]))
                }
            }
            .frame(height: 32, alignment: .bottom)
        }
        .padding(16)
        .background(Color.gsSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [Color.gsDanger.opacity(0.3), Color.gsCyan.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 40))
                .foregroundColor(.gsTextSecondary)

            Text("No health data available")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)

            Text("Grant HealthKit access to see your metrics here.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    NavigationStack {
        HealthDashboardView()
    }
    .preferredColorScheme(.dark)
}
