import SwiftUI

struct CalorieDashboardView: View {
    @StateObject private var viewModel = CalorieDashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let summary = viewModel.summary {
                    // Calorie ring
                    calorieRing(summary)

                    // Macro bars
                    macroBars(summary)

                    // Today's meals
                    mealsSection(summary.meals)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Calories")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    LogMealView { Task { await viewModel.loadDaily() } }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.gsEmerald)
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    NavigationLink {
                        NutritionGoalsView()
                    } label: {
                        Label("Goals", systemImage: "target")
                    }

                    NavigationLink {
                        WaterTrackerView()
                    } label: {
                        Label("Water", systemImage: "drop.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.gsTextSecondary)
                }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.summary == nil {
                LoadingView(message: "Loading nutrition data...")
            }
        }
        .task {
            await viewModel.loadDaily()
        }
    }

    // MARK: - Calorie Ring

    private func calorieRing(_ summary: DailySummaryDTO) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gsBorder, lineWidth: 12)

                Circle()
                    .trim(from: 0, to: viewModel.calorieProgress)
                    .stroke(
                        Color.gsEmerald,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: viewModel.calorieProgress)

                VStack(spacing: 4) {
                    Text("\(Int(summary.totalCalories))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.gsText)

                    Text("of \(Int(summary.targetCalories)) kcal")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }
            .frame(width: 160, height: 160)

            Text("\(viewModel.remaining) remaining")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsEmerald)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - Macro Bars

    private func macroBars(_ summary: DailySummaryDTO) -> some View {
        HStack(spacing: 16) {
            macroBar(label: "Protein", value: summary.protein, color: .gsEmerald)
            macroBar(label: "Carbs", value: summary.carbs, color: .gsCyan)
            macroBar(label: "Fat", value: summary.fat, color: .gsWarning)
        }
        .cardStyle()
    }

    private func macroBar(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(Int(value))g")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.gsText)

            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gsBorder)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(height: geometry.size.height * min(value / 150, 1))
                }
            }
            .frame(height: 60)

            Text(label)
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Meals

    private func mealsSection(_ meals: [MealDTO]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Meals")
                .font(.headline)
                .foregroundColor(.gsText)

            if meals.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "fork.knife")
                            .font(.title2)
                            .foregroundColor(.gsTextSecondary)
                        Text("No meals logged yet")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .cardStyle()
            } else {
                ForEach(meals) { meal in
                    mealRow(meal)
                }
            }
        }
    }

    private func mealRow(_ meal: MealDTO) -> some View {
        HStack(spacing: 12) {
            Image(systemName: meal.mealTypeIcon)
                .font(.title3)
                .foregroundColor(.gsEmerald)
                .frame(width: 36, height: 36)
                .background(Color.gsEmerald.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                Text(meal.mealType.capitalized)
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer()

            Text("\(Int(meal.calories)) kcal")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsEmerald)
        }
        .cardStyle()
    }
}

#Preview {
    NavigationStack {
        CalorieDashboardView()
    }
    .preferredColorScheme(.dark)
}
