import SwiftUI
import MapKit

struct GymDetailView: View {
    let gym: GymDTO
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var editedName: String
    @State private var isEditing = false
    @State private var error: String?

    init(gym: GymDTO) {
        self.gym = gym
        _editedName = State(initialValue: gym.name)
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: gym.latitude, longitude: gym.longitude),
            latitudinalMeters: gym.radiusMeters * 3,
            longitudinalMeters: gym.radiusMeters * 3
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Map
                Map(coordinateRegion: .constant(region), annotationItems: [gym]) { g in
                    MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: g.latitude, longitude: g.longitude)) {
                        Circle()
                            .fill(Color.gsEmerald.opacity(0.2))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Circle()
                                    .stroke(Color.gsEmerald, lineWidth: 2)
                            )
                            .overlay(
                                Image(systemName: "building.2.fill")
                                    .foregroundColor(.gsEmerald)
                            )
                    }
                }
                .frame(height: 240)
                .cornerRadius(16)
                .allowsHitTesting(false)

                // Info
                VStack(spacing: 0) {
                    if isEditing {
                        HStack {
                            TextField("Gym name", text: $editedName)
                                .font(.subheadline)
                                .foregroundColor(.gsText)
                                .textFieldStyle(.roundedBorder)

                            Button("Save") {
                                Task { await saveName() }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gsEmerald)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    } else {
                        HStack {
                            Text("Name").font(.subheadline).foregroundColor(.gsTextSecondary)
                            Spacer()
                            Text(gym.name).font(.subheadline.weight(.medium)).foregroundColor(.gsText)
                            Button { isEditing = true } label: {
                                Image(systemName: "pencil").font(.caption).foregroundColor(.gsEmerald)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    Divider().background(Color.gsBorder)
                    infoRow(label: "Radius", value: "\(Int(gym.radiusMeters)) meters")
                    Divider().background(Color.gsBorder)
                    infoRow(label: "Default", value: gym.isDefault ? "Yes" : "No")
                    if let created = gym.createdAt {
                        Divider().background(Color.gsBorder)
                        infoRow(label: "Added", value: created.shortDateString())
                    }
                }
                .cardStyle(padding: 0)

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }

                // Delete
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Gym", systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsDanger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.gsDanger.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Gym", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteGym() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This gym and its geofence will be removed.")
        }
    }

    private func infoRow(label: String, value: String) -> some View {
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

    private func saveName() async {
        do {
            let body = ["name": editedName]
            let endpoint = APIEndpoint(
                path: "/api/v1/gyms/\(gym.id)",
                method: .PATCH,
                body: body
            )
            let _: EmptyData = try await APIClient.shared.request(endpoint)
            isEditing = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteGym() async {
        do {
            let endpoint = APIEndpoint(path: "/api/v1/gyms/\(gym.id)", method: .DELETE)
            let _: EmptyData = try await APIClient.shared.request(endpoint)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        GymDetailView(gym: GymDTO(
            id: "1", name: "Iron Temple", latitude: 40.7128, longitude: -74.006,
            radiusMeters: 200, isDefault: true, createdAt: Date()
        ))
    }
    .preferredColorScheme(.dark)
}
