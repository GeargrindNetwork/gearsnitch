import SwiftUI
import MapKit
import CoreLocation

// MARK: - Add Gym View

struct AddGymView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchManager = MapSearchManager()
    @ObservedObject private var locationManager = LocationManager.shared

    // MARK: - Map State

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedAnnotation: PlaceAnnotation?

    // MARK: - Form State

    @State private var gymName = ""
    @State private var radiusMeters: Double = 150
    @State private var isDefault = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showLocationDeniedAlert = false
    @State private var isSearchFocused = false
    @State private var pendingLocationFocus = false

    // MARK: - Callback

    var onSaved: (() -> Void)?

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Full-screen map
            mapLayer

            // Search overlay
            VStack(spacing: 0) {
                searchBarOverlay
                if isSearchFocused && !searchManager.completions.isEmpty {
                    searchResultsList
                }
                Spacer()
            }

            // Current location button (bottom-right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    currentLocationButton
                        .padding(.trailing, 16)
                        .padding(.bottom, selectedAnnotation != nil ? 296 : 24)
                }
            }

            // Confirmation panel (bottom)
            VStack {
                Spacer()
                if let annotation = selectedAnnotation {
                    confirmationPanel(for: annotation)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Add Gym")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedAnnotation != nil)
        .alert("Location Services", isPresented: $showLocationDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable Location Services in Settings so GearSnitch can find gyms near you.")
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            guard pendingLocationFocus else { return }

            switch newStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                pendingLocationFocus = false
                focusOnCurrentLocation()
            case .denied, .restricted:
                pendingLocationFocus = false
                showLocationDeniedAlert = true
            case .notDetermined:
                break
            @unknown default:
                pendingLocationFocus = false
            }
        }
        .onDisappear {
            locationManager.stopUpdatingLocation()
        }
    }

    // MARK: - Map Layer

    private var mapLayer: some View {
        Map(position: $position) {
            if locationAccessGranted {
                UserAnnotation()
            }

            if let annotation = selectedAnnotation {
                Annotation(
                    annotation.name,
                    coordinate: annotation.coordinate,
                    anchor: .bottom
                ) {
                    VStack(spacing: 0) {
                        Image(systemName: "building.2.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.gsEmerald)
                            .clipShape(Circle())
                            .shadow(color: .gsEmerald.opacity(0.4), radius: 6, y: 3)

                        // Pin stem
                        Triangle()
                            .fill(Color.gsEmerald)
                            .frame(width: 14, height: 8)
                            .offset(y: -1)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .including([.fitnessCenter])))
        .mapControls {
            MapCompass()
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Search Bar Overlay

    private var searchBarOverlay: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)

            TextField("Search gyms, fitness centers...", text: $searchManager.searchText)
                .font(.subheadline)
                .foregroundColor(.gsText)
                .autocorrectionDisabled()
                .onTapGesture { isSearchFocused = true }

            if !searchManager.searchText.isEmpty {
                Button {
                    searchManager.clearSearch()
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .background(Color.gsSurface.opacity(0.7))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gsBorder.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchManager.completions.prefix(8), id: \.self) { completion in
                    Button {
                        selectCompletion(completion)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundColor(.gsEmerald)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.gsText)
                                    .lineLimit(1)

                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.gsTextSecondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    if completion != searchManager.completions.prefix(8).last {
                        Divider()
                            .background(Color.gsBorder.opacity(0.5))
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
        .background(.ultraThinMaterial)
        .background(Color.gsSurface.opacity(0.85))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gsBorder.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Current Location Button

    private var currentLocationButton: some View {
        Button {
            handleCurrentLocationTap()
        } label: {
            Image(systemName: "location.fill")
                .font(.body.weight(.medium))
                .foregroundColor(.gsEmerald)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .background(Color.gsSurface.opacity(0.7))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.gsBorder.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
    }

    // MARK: - Confirmation Panel

    private func confirmationPanel(for annotation: PlaceAnnotation) -> some View {
        VStack(spacing: 16) {
            // Drag indicator
            Capsule()
                .fill(Color.gsTextSecondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            // Place info header
            HStack(spacing: 12) {
                Image(systemName: "building.2.fill")
                    .font(.title2)
                    .foregroundColor(.gsEmerald)
                    .frame(width: 44, height: 44)
                    .background(Color.gsEmerald.opacity(0.12))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(annotation.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)
                        .lineLimit(1)

                    if let address = annotation.address {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }

            // Gym name field
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

            // Radius slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Monitoring Radius")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.gsTextSecondary)
                    Spacer()
                    Text("\(Int(radiusMeters))m")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gsEmerald)
                        .monospacedDigit()
                }

                Slider(value: $radiusMeters, in: 50...500, step: 25)
                    .tint(.gsEmerald)
            }

            // Default toggle
            Toggle(isOn: $isDefault) {
                Text("Set as default gym")
                    .font(.subheadline)
                    .foregroundColor(.gsText)
            }
            .tint(.gsEmerald)

            // Error
            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption)
                }
                .foregroundColor(.gsDanger)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Save button
            Button {
                Task { await saveGym() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Label("Save Gym", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                    }
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(gymName.isEmpty ? Color.gsTextSecondary.opacity(0.5) : Color.gsEmerald)
                .cornerRadius(14)
            }
            .disabled(gymName.isEmpty || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gsSurface)
                .shadow(color: .black.opacity(0.5), radius: 16, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gsBorder.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func selectCompletion(_ completion: MKLocalSearchCompletion) {
        isSearchFocused = false
        searchManager.searchText = completion.title

        Task {
            await searchManager.search(for: completion)
            if let item = searchManager.selectedPlace {
                let coord = item.placemark.coordinate
                let placeName = item.name ?? completion.title
                let address = formatAddress(from: item.placemark)

                selectedAnnotation = PlaceAnnotation(
                    name: placeName,
                    address: address,
                    coordinate: coord
                )
                gymName = placeName

                withAnimation(.easeInOut(duration: 0.5)) {
                    position = .region(MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 800,
                        longitudinalMeters: 800
                    ))
                }
            }
        }
    }

    private func checkLocationAuthorization() {
        pendingLocationFocus = false

        switch locationManager.authorizationStatus {
        case .notDetermined:
            pendingLocationFocus = true
            locationManager.requestWhenInUse()
        case .denied, .restricted:
            showLocationDeniedAlert = true
        case .authorizedWhenInUse, .authorizedAlways:
            focusOnCurrentLocation()
        @unknown default:
            break
        }
    }

    private var locationAccessGranted: Bool {
        locationManager.authorizationStatus == .authorizedWhenInUse
            || locationManager.authorizationStatus == .authorizedAlways
    }

    private func handleCurrentLocationTap() {
        checkLocationAuthorization()
    }

    private func focusOnCurrentLocation() {
        locationManager.startUpdatingLocation()

        withAnimation(.easeInOut(duration: 0.4)) {
            position = .userLocation(fallback: .automatic)
        }
    }

    private func saveGym() async {
        guard let annotation = selectedAnnotation else { return }

        isSaving = true
        errorMessage = nil

        let body = CreateGymBody(
            name: gymName,
            latitude: annotation.coordinate.latitude,
            longitude: annotation.coordinate.longitude,
            radiusMeters: radiusMeters,
            isDefault: isDefault
        )

        do {
            let _: GymDTO = try await APIClient.shared.request(APIEndpoint.Gyms.create(body))
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func formatAddress(from placemark: MKPlacemark) -> String? {
        var parts: [String] = []
        if let street = placemark.thoroughfare {
            if let number = placemark.subThoroughfare {
                parts.append("\(number) \(street)")
            } else {
                parts.append(street)
            }
        }
        if let city = placemark.locality {
            parts.append(city)
        }
        if let state = placemark.administrativeArea {
            parts.append(state)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Place Annotation

private struct PlaceAnnotation: Equatable {
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: PlaceAnnotation, rhs: PlaceAnnotation) -> Bool {
        lhs.name == rhs.name &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

// MARK: - Triangle Shape (Pin Stem)

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

// MARK: - MKLocalSearchCompletion Identifiable

extension MKLocalSearchCompletion: @retroactive Identifiable {
    public var id: String { "\(title)-\(subtitle)" }
}

#Preview {
    NavigationStack {
        AddGymView()
    }
    .preferredColorScheme(.dark)
}
