import SwiftUI

struct DayDetailView: View {
    let dateKey: String
    let activity: DayActivity?
    let detail: CalendarDayDetailResponse?
    let isLoadingDetail: Bool
    let detailError: String?
    let onLogMedication: ((String) -> Void)?
    let onEditMedication: ((CalendarMedicationDoseDTO, String) -> Void)?

    init(
        dateKey: String,
        activity: DayActivity?,
        detail: CalendarDayDetailResponse?,
        isLoadingDetail: Bool,
        detailError: String?,
        onLogMedication: ((String) -> Void)? = nil,
        onEditMedication: ((CalendarMedicationDoseDTO, String) -> Void)? = nil
    ) {
        self.dateKey = dateKey
        self.activity = activity
        self.detail = detail
        self.isLoadingDetail = isLoadingDetail
        self.detailError = detailError
        self.onLogMedication = onLogMedication
        self.onEditMedication = onEditMedication
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isLoadingDetail {
                loadingState
            } else if let detailError, detail == nil, activity == nil {
                errorState(detailError)
            } else {
                if let activity {
                    summaryRows(activity)
                }

                if let detail, detail.hasVisibleContent {
                    detailSections(detail)
                } else if activity == nil {
                    emptyState
                }
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

    private var header: some View {
        HStack {
            Text(formattedDate)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            Spacer()

            HStack(spacing: 8) {
                if let onLogMedication {
                    Button {
                        onLogMedication(dateKey)
                    } label: {
                        Label("Log Dose", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gsWarning)
                    }
                    .buttonStyle(.plain)
                }

                if isLoadingDetail {
                    Text("Loading details...")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                } else if activity == nil && detail?.hasVisibleContent != true {
                    Text("No Activity")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryRows(_ activity: DayActivity) -> some View {
        VStack(spacing: 10) {
            if activity.gymVisits.count > 0 {
                detailRow(
                    icon: "figure.strengthtraining.traditional",
                    iconColor: .gsEmerald,
                    title: "\(activity.gymVisits.count) Gym Session\(activity.gymVisits.count == 1 ? "" : "s")",
                    subtitle: formatMinutes(activity.gymVisits.totalMinutes)
                )
            }

            if activity.workoutsCompleted > 0 {
                detailRow(
                    icon: "figure.strengthtraining.traditional",
                    iconColor: .gsSuccess,
                    title: "\(activity.workoutsCompleted) Workout\(activity.workoutsCompleted == 1 ? "" : "s")",
                    subtitle: nil
                )
            }

            if activity.runsCompleted > 0 {
                detailRow(
                    icon: "figure.run",
                    iconColor: .gsCyan,
                    title: "\(activity.runsCompleted) Run\(activity.runsCompleted == 1 ? "" : "s")",
                    subtitle: nil
                )
            }

            if activity.medication.hasMedication {
                detailRow(
                    icon: "pills.fill",
                    iconColor: .gsWarning,
                    title: "Medication Logged",
                    subtitle: medicationSummary(activity.medication)
                )
            }

            if activity.mealsLogged.count > 0 {
                detailRow(
                    icon: "fork.knife",
                    iconColor: .gsWarning,
                    title: "\(activity.mealsLogged.count) Meal\(activity.mealsLogged.count == 1 ? "" : "s") Logged",
                    subtitle: "\(Int(activity.mealsLogged.totalCalories)) cal"
                )
            }

            if activity.waterIntakeMl > 0 {
                detailRow(
                    icon: "drop.fill",
                    iconColor: .gsCyan,
                    title: "Water Intake",
                    subtitle: formatWater(activity.waterIntakeMl)
                )
            }

            if activity.purchasesMade > 0 {
                detailRow(
                    icon: "bag.fill",
                    iconColor: .gsCyan,
                    title: "\(activity.purchasesMade) Purchase\(activity.purchasesMade == 1 ? "" : "s")",
                    subtitle: nil
                )
            }
        }
    }

    @ViewBuilder
    private func detailSections(_ detail: CalendarDayDetailResponse) -> some View {
        if !detail.sessions.isEmpty {
            section("Gym Sessions") {
                ForEach(detail.sessions) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.gymName ?? "Gym Session")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.gsText)

                        Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) - \((session.endedAt ?? session.startedAt).formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)

                        Text(session.durationString)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.gsEmerald)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(12)
                }
            }
        }

        if !detail.workouts.isEmpty {
            section("Workouts") {
                ForEach(detail.workouts) { workout in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.gsText)
                                Text("\(workout.startedAt.formatted(date: .omitted, time: .shortened)) • \(workout.durationString)")
                                    .font(.caption)
                                    .foregroundColor(.gsTextSecondary)
                            }

                            Spacer()
                        }

                        if !workout.exercises.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(workout.exercises) { exercise in
                                    Text("\(exercise.name): \(setSummary(exercise.sets))")
                                        .font(.caption)
                                        .foregroundColor(.gsTextSecondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(12)
                }
            }
        }

        if !detail.runs.isEmpty {
            section("Runs") {
                ForEach(detail.runs) { run in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(run.distanceString)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.gsText)
                        Text("\(run.startedAt.formatted(date: .omitted, time: .shortened)) • \(run.durationString) • \(run.paceString)")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(12)
                }
            }
        }

        if !detail.medicationDoses.isEmpty || detail.medicationTotals?.hasMedication == true {
            section("Medication") {
                if let medicationTotals = detail.medicationTotals, medicationTotals.hasMedication {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(formatDoseMg(medicationTotals.totalDoseMg)) total")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.gsText)

                        if let categoryBreakdown = medicationCategoryBreakdown(medicationTotals) {
                            Text(categoryBreakdown)
                                .font(.caption)
                                .foregroundColor(.gsTextSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(12)
                }

                ForEach(detail.medicationDoses) { dose in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dose.compoundName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.gsText)
                                Text(medicationCategoryLabel(dose.category))
                                    .font(.caption)
                                    .foregroundColor(.gsWarning)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 6) {
                                Text(doseAmountLabel(dose.dose))
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.gsText)

                                if let onEditMedication {
                                    Button {
                                        onEditMedication(dose, dateKey)
                                    } label: {
                                        Label("Edit", systemImage: "square.and.pencil")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(.gsTextSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if let occurredAt = dose.occurredAt {
                            Text(occurredAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.gsTextSecondary)
                        }

                        if let doseMg = dose.doseMg, dose.dose.unit.lowercased() != "mg" {
                            Text("Normalized: \(formatDoseMg(doseMg))")
                                .font(.caption)
                                .foregroundColor(.gsTextSecondary)
                        }

                        if let notes = dose.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.gsTextSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(12)
                }
            }
        }

        if !detail.meals.isEmpty {
            section("Meals") {
                ForEach(detail.meals) { meal in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gsText)
                            Text(meal.mealType.capitalized)
                                .font(.caption)
                                .foregroundColor(.gsTextSecondary)
                        }

                        Spacer()

                        Text("\(Int(meal.calories)) cal")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.gsWarning)
                    }
                    .padding(12)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(12)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.gsTextSecondary)
                .textCase(.uppercase)

            content()
        }
        .padding(.top, 4)
    }

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

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.gsEmerald)
            Text("Pulling workout, run, meal, and medication details…")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity details unavailable")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)
            Text(message)
                .font(.caption)
                .foregroundColor(.gsDanger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.title2)
                .foregroundColor(.gsTextSecondary)

            Text("Rest day — no activity or medication recorded")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: dateKey) else { return dateKey }
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins) min"
    }

    private func formatWater(_ milliliters: Double) -> String {
        let liters = milliliters / 1000
        if liters >= 1 {
            return String(format: "%.1fL", liters)
        }
        return "\(Int(milliliters))ml"
    }

    private func medicationSummary(_ overlay: DayActivity.MedicationOverlay) -> String {
        "\(overlay.entryCount) dose\(overlay.entryCount == 1 ? "" : "s") • \(formatDoseMg(overlay.totalDoseMg)) total"
    }

    private func medicationCategoryBreakdown(_ overlay: DayActivity.MedicationOverlay) -> String? {
        let parts = [
            overlay.categoryDoseMg.steroid > 0 ? "Steroid \(formatDoseMg(overlay.categoryDoseMg.steroid))" : nil,
            overlay.categoryDoseMg.peptide > 0 ? "Peptide \(formatDoseMg(overlay.categoryDoseMg.peptide))" : nil,
            overlay.categoryDoseMg.oralMedication > 0 ? "Oral \(formatDoseMg(overlay.categoryDoseMg.oralMedication))" : nil,
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func medicationCategoryLabel(_ category: String) -> String {
        switch category.lowercased() {
        case "oralmedication":
            return "Oral Medication"
        case "steroid":
            return "Steroid"
        case "peptide":
            return "Peptide"
        default:
            return category.capitalized
        }
    }

    private func doseAmountLabel(_ dose: CalendarMedicationDoseAmountDTO) -> String {
        let unit = dose.unit.lowercased()
        let displayUnit = unit == "mg" ? "mg" : unit.uppercased()
        let decimals = dose.value.rounded() == dose.value ? 0 : 1
        let format = "%.\(decimals)f %@"
        return String(format: format, dose.value, displayUnit)
    }

    private func formatDoseMg(_ value: Double) -> String {
        let decimals = value.rounded() == value ? 0 : 1
        let format = "%.\(decimals)f mg"
        return String(format: format, value)
    }

    private func setSummary(_ sets: [SetDTO]) -> String {
        guard !sets.isEmpty else { return "No sets logged" }
        return sets.map { set in
            if set.weightKg > 0 {
                return "\(set.reps)x \(Int(set.weightKg.rounded()))kg"
            }
            return "\(set.reps) reps"
        }.joined(separator: " • ")
    }
}

private extension CalendarDayDetailResponse {
    var hasVisibleContent: Bool {
        !sessions.isEmpty
            || !meals.isEmpty
            || !workouts.isEmpty
            || !runs.isEmpty
            || !medicationDoses.isEmpty
            || medicationTotals?.hasMedication == true
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
                workoutsCompleted: 1,
                runsCompleted: 1
            ),
            detail: nil,
            isLoadingDetail: false,
            detailError: nil
        )

        DayDetailView(
            dateKey: "2026-04-08",
            activity: nil,
            detail: nil,
            isLoadingDetail: false,
            detailError: nil
        )
    }
    .padding()
    .background(Color.gsBackground)
    .preferredColorScheme(.dark)
}
