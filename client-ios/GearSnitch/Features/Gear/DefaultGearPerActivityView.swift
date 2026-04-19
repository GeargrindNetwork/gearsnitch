import SwiftUI

/// Settings screen that lets users configure the default gear per activity
/// type (backlog item #9 — Strava-style auto-gear assignment). When a
/// workout/run starts, the server auto-attaches the gear the user selected
/// here for the matching HKWorkoutActivityType.
///
/// Layout: one row per activity type with a gear picker that surfaces only
/// kind-compatible gear (running → shoes + chest strap; cycling → bike +
/// tire + chain + helmet; strength → chest strap + other). "No default"
/// option clears the preference.
struct DefaultGearPerActivityView: View {

    @StateObject private var viewModel = DefaultGearPerActivityViewModel()

    var body: some View {
        List {
            Section {
                Text("Pick the gear that auto-attaches when you start a workout of each type. You can always override before tapping Start.")
                    .font(.footnote)
                    .foregroundColor(.gsTextSecondary)
                    .listRowBackground(Color.gsSurface)
            }

            if viewModel.isLoading && viewModel.gear.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.gsEmerald)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
                .listRowBackground(Color.gsSurface)
            } else if viewModel.gear.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No gear yet")
                            .font(.headline)
                            .foregroundColor(.gsText)
                        Text("Add gear components (shoes, bikes, chains) to assign defaults. The full gear manager ships with the next update.")
                            .font(.footnote)
                            .foregroundColor(.gsTextSecondary)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.gsSurface)
            } else {
                Section {
                    ForEach(GearActivityType.allCases) { activity in
                        ActivityRow(
                            activity: activity,
                            compatible: viewModel.compatibleGear(for: activity),
                            selectedGearId: viewModel.defaults[activity] ?? nil,
                            isSaving: viewModel.savingActivity == activity,
                            onSelect: { gearId in
                                Task { await viewModel.setDefault(for: activity, gearId: gearId) }
                            }
                        )
                    }
                } header: {
                    Text("Activity Types")
                        .foregroundColor(.gsTextSecondary)
                }
                .listRowBackground(Color.gsSurface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Default Gear")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert("Couldn't Save", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "Something went wrong.")
        }
    }
}

// MARK: - Row

private struct ActivityRow: View {
    let activity: GearActivityType
    let compatible: [GearComponentDTO]
    let selectedGearId: String?
    let isSaving: Bool
    let onSelect: (String?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.systemImage)
                .font(.title3)
                .foregroundColor(.gsEmerald)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.displayName)
                    .font(.body)
                    .foregroundColor(.gsText)
                if let selected = compatible.first(where: { $0.id == selectedGearId }) {
                    Text("\(selected.name) · \(selected.usageLabel)")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                } else {
                    Text("No default")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }

            Spacer()

            if isSaving {
                ProgressView().tint(.gsEmerald)
            } else {
                Menu {
                    Button("No default") { onSelect(nil) }
                    if !compatible.isEmpty {
                        Divider()
                        ForEach(compatible) { item in
                            Button {
                                onSelect(item.id)
                            } label: {
                                Label(
                                    "\(item.name) · \(item.usageLabel)",
                                    systemImage: item.id == selectedGearId ? "checkmark" : ""
                                )
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedGearId == nil ? "Set" : "Change")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.gsEmerald)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.gsEmerald)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DefaultGearPerActivityView()
    }
    .preferredColorScheme(.dark)
}
#endif
