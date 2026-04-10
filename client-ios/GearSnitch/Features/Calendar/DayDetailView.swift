import SwiftUI

// MARK: - Day Detail View

/// Expandable detail view shown when a day is tapped on the heatmap calendar.
struct DayDetailView: View {
    let dateKey: String
    let activity: DayActivity?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                Text(formattedDate)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)

                Spacer()

                if activity == nil {
                    Text("No Activity")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }

            if let activity {
                VStack(spacing: 10) {
                    // Gym sessions
                    if activity.gymVisits.count > 0 {
                        gymSessionCard(activity.gymVisits)
                    }

                    // Meals
                    if activity.mealsLogged.count > 0 {
                        mealsCard(activity.mealsLogged)
                    }

                    // Purchases
                    if activity.purchasesMade > 0 {
                        purchasesCard(count: activity.purchasesMade)
                    }

                    // Water intake
                    if activity.waterIntakeMl > 0 {
                        waterCard(ml: activity.waterIntakeMl)
                    }

                    // Workouts
                    if activity.workoutsCompleted > 0 {
                        workoutsCard(count: activity.workoutsCompleted)
                    }
                }
            } else {
                emptyState
            }
        }
        .padding(16)
        .background(Color.gsSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
        .padding(.horizontal, 8)
    }

    // MARK: - Formatted Date

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: dateKey) else { return dateKey }
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    // MARK: - Gym Session Card

    private func gymSessionCard(_ visits: DayActivity.GymVisitSummary) -> some View {
        detailRow(
            icon: "figure.strengthtraining.traditional",
            iconColor: .gsEmerald,
            title: "\(visits.count) Gym Session\(visits.count == 1 ? "" : "s")",
            subtitle: formatMinutes(visits.totalMinutes)
        )
    }

    // MARK: - Meals Card

    private func mealsCard(_ meals: DayActivity.MealSummary) -> some View {
        detailRow(
            icon: "fork.knife",
            iconColor: .gsWarning,
            title: "\(meals.count) Meal\(meals.count == 1 ? "" : "s") Logged",
            subtitle: "\(Int(meals.totalCalories)) cal"
        )
    }

    // MARK: - Purchases Card

    private func purchasesCard(count: Int) -> some View {
        detailRow(
            icon: "bag.fill",
            iconColor: .gsCyan,
            title: "\(count) Purchase\(count == 1 ? "" : "s")",
            subtitle: nil
        )
    }

    // MARK: - Water Card

    private func waterCard(ml: Double) -> some View {
        let liters = ml / 1000
        let formatted = liters >= 1
            ? String(format: "%.1fL", liters)
            : "\(Int(ml))ml"

        return detailRow(
            icon: "drop.fill",
            iconColor: .gsCyan,
            title: "Water Intake",
            subtitle: formatted
        )
    }

    // MARK: - Workouts Card

    private func workoutsCard(count: Int) -> some View {
        detailRow(
            icon: "figure.run",
            iconColor: .gsSuccess,
            title: "\(count) Workout\(count == 1 ? "" : "s")",
            subtitle: nil
        )
    }

    // MARK: - Detail Row

    private func detailRow(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.15))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(Color.gsSurfaceRaised)
        .cornerRadius(10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.title2)
                .foregroundColor(.gsTextSecondary)

            Text("Rest day — no activity recorded")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Helpers

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins) min"
    }
}

#Preview {
    VStack(spacing: 16) {
        DayDetailView(
            dateKey: "2026-04-09",
            activity: DayActivity(
                gymVisits: .init(count: 1, totalMinutes: 75),
                mealsLogged: .init(count: 3, totalCalories: 2100),
                purchasesMade: 1,
                waterIntakeMl: 2500,
                workoutsCompleted: 1
            )
        )

        DayDetailView(dateKey: "2026-04-08", activity: nil)
    }
    .padding()
    .background(Color.gsBackground)
    .preferredColorScheme(.dark)
}
