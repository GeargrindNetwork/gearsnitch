import SwiftUI
import MapKit
import CoreLocation

struct AddGymView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationDelegate = LocationDelegate()

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        latitudinalMeters: 500,
        longitudinalMeters: 500
    )
    @State private var gymName = ""
    @State private var radiusMeters: Double = 200
    @State private var isDefault = true
    @State private var isSaving = false
    @State private var error: String?

    var onSaved: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Map
            ZStack {
                Map(coordinateRegion: $region, showsUserLocation: true)
                    .ignoresSafeArea(edges: .top)

                // Crosshair
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
                    .allowsHitTesting(false)
            }
            .frame(height: 280)

            // Form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Gym Name")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.gsTextSecondary)

                    TextField("e.g. Iron Temple", text: $gymName)
                        .font(.subheadline)
                        .foregroundColor(.gsText)
                        .padding(12)
                        .background(Color.gsSurfaceRaised)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gsBorder, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Monitoring Radius: \(Int(radiusMeters))m")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.gsTextSecondary)

                    Slider(value: $radiusMeters, in: 50...500, step: 25)
                        .tint(.gsEmerald)
                }

                Toggle(isOn: $isDefault) {
                    Text("Set as default gym")
                        .font(.subheadline)
                        .foregroundColor(.gsText)
                }
                .tint(.gsEmerald)

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }

                Button {
                    Task { await saveGym() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Add Gym")
                                .font(.headline)
                        }
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(gymName.isEmpty ? Color.gsTextSecondary : Color.gsEmerald)
                    .cornerRadius(14)
                }
                .disabled(gymName.isEmpty || isSaving)
            }
            .padding(16)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Add Gym")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            locationDelegate.requestLocation { coordinate in
                region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                )
            }
        }
    }

    private func saveGym() async {
        isSaving = true
        error = nil

        let body = CreateGymBody(
            name: gymName,
            latitude: region.center.latitude,
            longitude: region.center.longitude,
            radiusMeters: radiusMeters,
            isDefault: isDefault
        )

        do {
            let _: GymDTO = try await APIClient.shared.request(APIEndpoint.Gyms.create(body))
            onSaved?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Location Delegate

private final class LocationDelegate: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D) -> Void)?

    func requestLocation(completion: @escaping (CLLocationCoordinate2D) -> Void) {
        self.completion = completion
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coordinate = locations.first?.coordinate {
            completion?(coordinate)
            completion = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Fall back to default coordinates
    }
}

#Preview {
    NavigationStack {
        AddGymView()
    }
    .preferredColorScheme(.dark)
}
