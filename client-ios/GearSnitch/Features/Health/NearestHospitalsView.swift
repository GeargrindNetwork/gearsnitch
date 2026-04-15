import CoreLocation
import MapKit
import SwiftUI

// MARK: - Hospital Item

struct HospitalItem: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let distance: Double // miles
    let coordinate: CLLocationCoordinate2D
    let phoneNumber: String?
    let mapItem: MKMapItem
}

// MARK: - Nearest Hospitals View

struct NearestHospitalsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NearestHospitalsViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingView(message: "Finding nearby hospitals...")
            } else if viewModel.hospitals.isEmpty {
                emptyState
            } else {
                hospitalList
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Nearest Hospitals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task {
            await viewModel.searchNearbyHospitals()
        }
    }

    // MARK: - Hospital List

    private var hospitalList: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "cross.case.fill")
                        .font(.title2)
                        .foregroundColor(.gsDanger)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emergency & Hospitals")
                            .font(.headline)
                            .foregroundColor(.gsText)
                        Text("Within 20 miles of your location")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                ForEach(viewModel.hospitals) { hospital in
                    Button {
                        openInMaps(hospital)
                    } label: {
                        hospitalCard(hospital)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    private func hospitalCard(_ hospital: HospitalItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.gsDanger.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: "cross.case.fill")
                    .font(.title3)
                    .foregroundColor(.gsDanger)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(hospital.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(hospital.address)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let phone = hospital.phoneNumber {
                    Text(phone)
                        .font(.caption)
                        .foregroundColor(.gsCyan)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f mi", hospital.distance))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.gsEmerald)

                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.caption)
                    .foregroundColor(.gsEmerald)
            }
        }
        .padding(14)
        .background(Color.gsSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }

    private func openInMaps(_ hospital: HospitalItem) {
        let launchOptions = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
        ]
        hospital.mapItem.openInMaps(launchOptions: launchOptions)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cross.case")
                .font(.system(size: 48))
                .foregroundColor(.gsTextSecondary)

            Text("No hospitals found nearby")
                .font(.headline)
                .foregroundColor(.gsText)

            Text("Make sure location services are enabled and try again.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task { await viewModel.searchNearbyHospitals() }
            } label: {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsEmerald)
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class NearestHospitalsViewModel: ObservableObject {
    @Published var hospitals: [HospitalItem] = []
    @Published var isLoading = false
    @Published var error: String?

    private let locationManager = CLLocationManager()
    private let maxDistanceMiles: Double = 20

    func searchNearbyHospitals() async {
        isLoading = true
        error = nil

        guard let userLocation = locationManager.location else {
            locationManager.requestWhenInUseAuthorization()
            // Wait briefly for location
            try? await Task.sleep(for: .seconds(2))

            guard let location = locationManager.location else {
                error = "Unable to determine your location"
                isLoading = false
                return
            }

            await performSearch(from: location)
            return
        }

        await performSearch(from: userLocation)
    }

    private func performSearch(from location: CLLocation) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "hospital emergency room"
        request.resultTypes = .pointOfInterest

        let radiusMeters = maxDistanceMiles * 1609.34
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            hospitals = response.mapItems.compactMap { item in
                guard let name = item.name else { return nil }

                let hospitalLocation = CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
                let distanceMeters = location.distance(from: hospitalLocation)
                let distanceMiles = distanceMeters / 1609.34

                guard distanceMiles <= maxDistanceMiles else { return nil }

                let address = [
                    item.placemark.thoroughfare,
                    item.placemark.locality,
                    item.placemark.administrativeArea,
                ].compactMap { $0 }.joined(separator: ", ")

                return HospitalItem(
                    name: name,
                    address: address.isEmpty ? "Address unavailable" : address,
                    distance: distanceMiles,
                    coordinate: item.placemark.coordinate,
                    phoneNumber: item.phoneNumber,
                    mapItem: item
                )
            }
            .sorted { $0.distance < $1.distance }

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        NearestHospitalsView()
    }
    .preferredColorScheme(.dark)
}
