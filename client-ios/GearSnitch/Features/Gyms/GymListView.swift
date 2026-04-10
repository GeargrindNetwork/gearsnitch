import SwiftUI

struct GymListView: View {
    @StateObject private var viewModel = GymListViewModel()
    @State private var showAddGym = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.gyms.isEmpty {
                LoadingView(message: "Loading gyms...")
            } else if viewModel.gyms.isEmpty {
                emptyState
            } else {
                gymList
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Gyms")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddGym = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.gsEmerald)
                }
            }
        }
        .sheet(isPresented: $showAddGym) {
            NavigationStack {
                AddGymView {
                    Task { await viewModel.loadGyms() }
                }
            }
        }
        .task {
            await viewModel.loadGyms()
        }
    }

    // MARK: - Gym List

    private var gymList: some View {
        List {
            ForEach(viewModel.gyms) { gym in
                NavigationLink {
                    GymDetailView(gym: gym)
                } label: {
                    gymRow(gym)
                }
                .listRowBackground(Color.gsSurface)
                .listRowSeparatorTint(Color.gsBorder)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteGym(gymId: gym.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    if !gym.isDefault {
                        Button {
                            Task { await viewModel.setDefault(gymId: gym.id) }
                        } label: {
                            Label("Default", systemImage: "star.fill")
                        }
                        .tint(.gsWarning)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadGyms()
        }
    }

    private func gymRow(_ gym: GymDTO) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "building.2.fill")
                .font(.title3)
                .foregroundColor(.gsEmerald)
                .frame(width: 40, height: 40)
                .background(Color.gsEmerald.opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(gym.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsText)

                    if gym.isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.gsWarning)
                    }
                }

                Text("Radius: \(Int(gym.radiusMeters))m")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundColor(.gsTextSecondary)

            Text("No Gyms")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text("Add your gym so GearSnitch knows when to start monitoring.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showAddGym = true
            } label: {
                Label("Add Gym", systemImage: "plus.circle.fill")
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
        GymListView()
    }
    .preferredColorScheme(.dark)
}
