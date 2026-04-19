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
        .onChange(of: viewModel.didComplete) { _, completed in
            if completed { dismiss() }
        }
        // Rest timer overlay (backlog item #16) — sits above everything.
        .overlay {
            if let restTimer = viewModel.restTimer {
                RestTimerOverlayView(
                    state: restTimer,
                    onDismiss: { viewModel.dismissRestTimer() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.restTimer == nil)
        // Pick up any workout session that the scene delegate recovered
        // before this view appeared (iOS 26+, item #10).
        .onAppear {
            consumeRecoveredSessionIfNeeded()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: workoutRecoveryNotificationName)
        ) { note in
            if #available(iOS 26.0, *) {
                if let session = note.object as? IPhoneWorkoutSession {
                    viewModel.attachRecovered(session)
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast = viewModel.recoveryToast {
                recoveryToastView(toast)
            }
        }
    }

    // MARK: - Source Tag

    private var workoutSourceIconName: String {
        switch viewModel.workoutSource {
        case .watch: return "applewatch"
        case .iPhoneHealthKit: return "iphone.gen3"
        case .timerOnly: return "timer"
        }
    }

    // MARK: - Recovery

    private var workoutRecoveryNotificationName: Notification.Name {
        if #available(iOS 26.0, *) {
            return SceneDelegate.recoveredWorkoutNotification
        } else {
            return Notification.Name("com.gearsnitch.workout.recovered.noop")
        }
    }

    private func consumeRecoveredSessionIfNeeded() {
        guard let any = SceneDelegate.recoveredSessionStore.consume() else { return }
        if #available(iOS 26.0, *), let session = any as? IPhoneWorkoutSession {
            viewModel.attachRecovered(session)
        }
    }

    @ViewBuilder
    private func recoveryToastView(_ toast: WorkoutRecoveryToast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundColor(.gsEmerald)
            Text(toast.message)
                .font(.caption.weight(.medium))
                .foregroundColor(.gsText)
            Spacer()
            Button {
                viewModel.recoveryToast = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .padding(12)
        .background(Color.gsSurfaceRaised)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
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

                // "Powered by:" tag — tells the user whether their workout is
                // being tracked by the Watch, iPhone HealthKit, or just the
                // wall-clock timer (backlog item #10).
                HStack(spacing: 6) {
                    Image(systemName: workoutSourceIconName)
                        .font(.caption2)
                        .foregroundColor(.gsTextSecondary)
                    Text(viewModel.workoutSource.displayTag)
                        .font(.caption2)
                        .foregroundColor(.gsTextSecondary)
                    if let bpm = viewModel.currentBPM {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.gsTextSecondary)
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundColor(.gsDanger)
                            Text("\(bpm) BPM")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.gsText)
                        }
                    }
                }
                .padding(.top, 2)
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

            // Log Set button — backlog item #16. Marks the set complete
            // and starts the rest timer overlay.
            Button {
                viewModel.logSet(exerciseId: exercise.id, setId: workoutSet.id)
            } label: {
                Image(systemName: workoutSet.completed ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title3)
                    .foregroundColor(workoutSet.completed ? .gsEmerald : .gsTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(workoutSet.completed ? "Set logged" : "Log set")
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
