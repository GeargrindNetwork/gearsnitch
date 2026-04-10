import SwiftUI

struct WaterTrackerView: View {
    @State private var todayMl: Double = 0
    @State private var targetMl: Double = 3000
    @State private var customAmount = ""
    @State private var logs: [WaterLogEntry] = []
    @State private var isLogging = false
    @State private var error: String?

    private var progress: Double {
        guard targetMl > 0 else { return 0 }
        return min(todayMl / targetMl, 1.0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Water ring
                waterRing

                // Quick add buttons
                quickAddSection

                // Custom amount
                customAmountSection

                // Daily log
                if !logs.isEmpty {
                    dailyLog
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Water")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Ring

    private var waterRing: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gsBorder, lineWidth: 14)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.gsCyan,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: progress)

                VStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.title2)
                        .foregroundColor(.gsCyan)

                    Text("\(Int(todayMl))")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.gsText)

                    Text("of \(Int(targetMl)) ml")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }
            .frame(width: 180, height: 180)

            if todayMl >= targetMl {
                Label("Goal reached!", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsSuccess)
            } else {
                Text("\(Int(targetMl - todayMl)) ml remaining")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - Quick Add

    private var quickAddSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add")
                .font(.headline)
                .foregroundColor(.gsText)

            HStack(spacing: 12) {
                quickAddButton(amount: 250, label: "250 ml")
                quickAddButton(amount: 500, label: "500 ml")
                quickAddButton(amount: 750, label: "750 ml")
            }
        }
    }

    private func quickAddButton(amount: Double, label: String) -> some View {
        Button {
            Task { await logWater(amount) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .foregroundColor(.gsCyan)

                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.gsText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(Color.gsSurface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gsBorder, lineWidth: 1)
            )
        }
        .disabled(isLogging)
    }

    // MARK: - Custom

    private var customAmountSection: some View {
        HStack(spacing: 12) {
            TextField("Custom ml", text: $customAmount)
                .keyboardType(.numberPad)
                .font(.subheadline)
                .foregroundColor(.gsText)
                .padding(12)
                .background(Color.gsSurfaceRaised)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gsBorder, lineWidth: 1)
                )

            Button {
                if let amount = Double(customAmount), amount > 0 {
                    Task {
                        await logWater(amount)
                        customAmount = ""
                    }
                }
            } label: {
                Text("Add")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.gsCyan)
                    .cornerRadius(10)
            }
            .disabled(customAmount.isEmpty || isLogging)
        }
    }

    // MARK: - Daily Log

    private var dailyLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Log")
                .font(.headline)
                .foregroundColor(.gsText)

            ForEach(logs) { entry in
                HStack {
                    Image(systemName: "drop")
                        .font(.caption)
                        .foregroundColor(.gsCyan)

                    Text("\(Int(entry.amountMl)) ml")
                        .font(.subheadline)
                        .foregroundColor(.gsText)

                    Spacer()

                    Text(entry.time.timeOnlyString())
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
                .padding(.vertical, 4)
            }
        }
        .cardStyle()
    }

    // MARK: - API

    private func logWater(_ amount: Double) async {
        isLogging = true

        let body = LogWaterBody(amountMl: amount)

        do {
            let _: EmptyData = try await APIClient.shared.request(
                APIEndpoint.Calories.logWater(body)
            )
            todayMl += amount
            logs.insert(WaterLogEntry(amountMl: amount, time: Date()), at: 0)
        } catch {
            self.error = error.localizedDescription
        }

        isLogging = false
    }
}

// MARK: - Log Entry

private struct WaterLogEntry: Identifiable {
    let id = UUID()
    let amountMl: Double
    let time: Date
}

#Preview {
    NavigationStack {
        WaterTrackerView()
    }
    .preferredColorScheme(.dark)
}
