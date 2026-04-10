import SwiftUI

struct ActiveWorkoutView: View {
    @StateObject private var viewModel = ActiveWorkoutViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showEndConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isActive {
                startView
            } else {
                activeView
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .alert("End Workout?", isPresented: $showEndConfirm) {
            Button("End & Save", role: .destructive) {
                Task { await viewModel.endWorkout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your workout will be saved with \(viewModel.exercises.count) exercise(s).")
        }
        .sheet(isPresented: $viewModel.showAddExercise) {
            addExerciseSheet
        }
        .onChange(of: viewModel.didComplete) { completed in
            if completed { dismiss() }
        }
    }

    // MARK: - Start

    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 56))
                .foregroundStyle(Color.gsBrandGradient)

            Text("Ready to train?")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Button {
                viewModel.startWorkout()
            } label: {
                Text("Start Workout")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.gsEmerald)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Active

    private var activeView: some View {
        VStack(spacing: 0) {
            // Timer header
            VStack(spacing: 4) {
                Text(viewModel.elapsedFormatted)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(.gsEmerald)

                Text("Elapsed Time")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            .padding(.vertical, 20)

            Divider().background(Color.gsBorder)

            // Exercises
            if viewModel.exercises.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("No exercises yet")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)

                    Button {
                        viewModel.showAddExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.gsEmerald)
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.exercises) { exercise in
                        exerciseSection(exercise)
                    }
                    .onDelete(perform: viewModel.removeExercise)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }

            // Bottom bar
            HStack(spacing: 12) {
                Button {
                    viewModel.showAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsEmerald)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.gsEmerald.opacity(0.1))
                        .cornerRadius(12)
                }

                Button {
                    showEndConfirm = true
                } label: {
                    Text("End")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 80, height: 46)
                        .background(Color.gsDanger)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gsSurface)
        }
    }

    // MARK: - Exercise Section

    private func exerciseSection(_ exercise: WorkoutExercise) -> some View {
        Section {
            ForEach(exercise.sets) { workoutSet in
                setRow(exercise: exercise, workoutSet: workoutSet)
            }

            Button {
                viewModel.addSet(to: exercise.id)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.gsEmerald)
            }
            .listRowBackground(Color.gsSurface)
        } header: {
            Text(exercise.name)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)
        }
    }

    private func setRow(exercise: WorkoutExercise, workoutSet: WorkoutSet) -> some View {
        HStack(spacing: 16) {
            if let index = exercise.sets.firstIndex(where: { $0.id == workoutSet.id }) {
                Text("Set \(index + 1)")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
                    .frame(width: 44, alignment: .leading)
            }

            HStack(spacing: 4) {
                TextField("0", value: Binding(
                    get: { workoutSet.reps },
                    set: { viewModel.updateSet(exerciseId: exercise.id, setId: workoutSet.id, reps: $0, weight: workoutSet.weight) }
                ), format: .number)
                .keyboardType(.numberPad)
                .font(.subheadline)
                .foregroundColor(.gsText)
                .frame(width: 44)
                .multilineTextAlignment(.center)
                .padding(6)
                .background(Color.gsSurfaceRaised)
                .cornerRadius(6)

                Text("reps")
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary)
            }

            HStack(spacing: 4) {
                TextField("0", value: Binding(
                    get: { workoutSet.weight },
                    set: { viewModel.updateSet(exerciseId: exercise.id, setId: workoutSet.id, reps: workoutSet.reps, weight: $0) }
                ), format: .number)
                .keyboardType(.decimalPad)
                .font(.subheadline)
                .foregroundColor(.gsText)
                .frame(width: 50)
                .multilineTextAlignment(.center)
                .padding(6)
                .background(Color.gsSurfaceRaised)
                .cornerRadius(6)

                Text("lbs")
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer()
        }
        .listRowBackground(Color.gsSurface)
    }

    // MARK: - Add Exercise Sheet

    private var addExerciseSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Exercise name", text: $viewModel.newExerciseName)
                    .font(.subheadline)
                    .foregroundColor(.gsText)
                    .padding(12)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gsBorder, lineWidth: 1)
                    )
                    .padding(.top, 20)

                Button {
                    viewModel.addExercise()
                } label: {
                    Text("Add")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(viewModel.newExerciseName.isEmpty ? Color.gsTextSecondary : Color.gsEmerald)
                        .cornerRadius(12)
                }
                .disabled(viewModel.newExerciseName.isEmpty)

                Spacer()
            }
            .padding(.horizontal, 16)
            .background(Color.gsSurface.ignoresSafeArea())
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showAddExercise = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        ActiveWorkoutView()
    }
    .preferredColorScheme(.dark)
}
