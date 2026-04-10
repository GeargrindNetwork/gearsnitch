import SwiftUI

struct WorkoutListView: View {
    @StateObject private var viewModel = WorkoutListViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.workouts.isEmpty {
                LoadingView(message: "Loading workouts...")
            } else if viewModel.workouts.isEmpty {
                emptyState
            } else {
                workoutList
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ActiveWorkoutView()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.gsEmerald)
                }
            }
        }
        .task {
            await viewModel.loadWorkouts()
        }
    }

    private var workoutList: some View {
        List {
            ForEach(viewModel.workouts) { workout in
                NavigationLink {
                    WorkoutDetailView(workout: workout)
                } label: {
                    workoutRow(workout)
                }
                .listRowBackground(Color.gsSurface)
                .listRowSeparatorTint(Color.gsBorder)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadWorkouts()
        }
    }

    private func workoutRow(_ workout: WorkoutDTO) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title3)
                .foregroundColor(.gsEmerald)
                .frame(width: 40, height: 40)
                .background(Color.gsEmerald.opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.startDate.shortDateString())
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                HStack(spacing: 12) {
                    Label(workout.durationString, systemImage: "clock")
                    Label("\(workout.exerciseCount) exercises", systemImage: "dumbbell")
                }
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

                if let gymName = workout.gymName {
                    Label(gymName, systemImage: "building.2")
                        .font(.caption2)
                        .foregroundColor(.gsTextSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 48))
                .foregroundColor(.gsTextSecondary)

            Text("No Workouts")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text("Start a workout to begin tracking your progress.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            NavigationLink {
                ActiveWorkoutView()
            } label: {
                Label("Start Workout", systemImage: "play.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.gsEmerald)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        WorkoutListView()
    }
    .preferredColorScheme(.dark)
}
