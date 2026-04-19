import SwiftUI

struct WorkoutDetailView: View {
    let workout: WorkoutDTO

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary card
                VStack(spacing: 16) {
                    HStack(spacing: 24) {
                        statItem(value: workout.durationString, label: "Duration", icon: "clock")
                        statItem(value: "\(workout.exerciseCount)", label: "Exercises", icon: "dumbbell")
                        statItem(
                            value: workout.source?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Manual",
                            label: "Source",
                            icon: "waveform.path.ecg"
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .cardStyle()

                // Details
                VStack(spacing: 0) {
                    detailRow(label: "Name", value: workout.name)
                    Divider().background(Color.gsBorder)
                    detailRow(label: "Date", value: workout.startedAt.shortDateString())
                    Divider().background(Color.gsBorder)
                    detailRow(label: "Start", value: workout.startedAt.timeOnlyString())
                    Divider().background(Color.gsBorder)
                    detailRow(label: "End", value: workout.endedAt?.timeOnlyString() ?? "In Progress")
                    if let gymName = workout.gymName {
                        Divider().background(Color.gsBorder)
                        detailRow(label: "Gym", value: gymName)
                    }
                }
                .cardStyle(padding: 0)

                // Exercises
                if !workout.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Exercises")
                            .font(.headline)
                            .foregroundColor(.gsText)

                        ForEach(workout.exercises) { exercise in
                            exerciseCard(exercise)
                        }
                    }
                }

                // Notes
                if let notes = workout.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.gsTextSecondary)
                        Text(notes)
                            .font(.subheadline)
                            .foregroundColor(.gsText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.gsEmerald)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(.gsText)

            Text(label)
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func exerciseCard(_ exercise: ExerciseDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.name)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                HStack {
                    Text("Set \(index + 1)")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                        .frame(width: 44, alignment: .leading)

                    Text("\(set.reps) reps")
                        .font(.caption)
                        .foregroundColor(.gsText)

                    if set.weightKg > 0 {
                        Text("@ \(Int(set.weightLbs.rounded())) lbs")
                            .font(.caption)
                            .foregroundColor(.gsEmerald)
                    }

                    Spacer()
                }
            }
        }
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
        WorkoutDetailView(workout: WorkoutDTO(
            id: "1",
            name: "Strength Workout",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            durationMinutes: 60,
            durationSeconds: 3600,
            exerciseCount: 2,
            notes: "Great session",
            exercises: [],
            gymName: "Iron Temple",
            source: "manual",
            createdAt: Date(),
            updatedAt: Date(),
            gearId: nil,
            gearIds: nil,
            activityType: nil
        ))
    }
    .preferredColorScheme(.dark)
}
