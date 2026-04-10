import SwiftUI
import MapKit
import CoreLocation
import CoreBluetooth

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @EnvironmentObject private var bleManager: BLEManager
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.gsBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator (hidden on welcome)
                if viewModel.currentStep != .welcome {
                    stepIndicator
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 4)
                }

                // Step content
                Group {
                    switch viewModel.currentStep {
                    case .welcome:
                        WelcomeView(onGetStarted: { viewModel.advance() })

                    case .signIn:
                        SignInView(onSignInComplete: {
                            viewModel.handleSignInSuccess()
                        })

                    case .subscription:
                        SubscriptionCardsView(
                            onSelect: { tier in
                                viewModel.selectSubscription(tier: tier.rawValue)
                            },
                            onSkip: { viewModel.skipSubscription() }
                        )

                    case .bluetoothPrePrompt:
                        bluetoothStep

                    case .locationWhenInUse:
                        locationStep

                    case .locationAlways:
                        backgroundLocationStep

                    case .notifications:
                        notificationsStep

                    case .healthKit:
                        healthKitStep

                    case .addGym:
                        addGymStep

                    case .pairDevice:
                        pairDeviceStep

                    case .complete:
                        completionStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.easeInOut(duration: 0.35), value: viewModel.currentStep)
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<OnboardingStep.visibleStepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= viewModel.visibleStepIndex
                          ? Color.gsEmerald
                          : Color.gsBorder)
                    .frame(height: 3)
            }
        }
    }

    // MARK: - Bluetooth Step

    private var bluetoothStep: some View {
        permissionStep(
            icon: "antenna.radiowaves.left.and.right",
            iconColor: .blue,
            title: "Bluetooth Access",
            description: "GearSnitch uses Bluetooth to detect and monitor your gym gear in real-time. Without this, we can't track your devices.",
            detail: "This permission is required to continue.",
            buttonTitle: "Enable Bluetooth",
            isRequired: true,
            action: { viewModel.requestBluetoothPermission() }
        )
    }

    // MARK: - Location Step

    private var locationStep: some View {
        permissionStep(
            icon: "location.fill",
            iconColor: .gsEmerald,
            title: "Location Access",
            description: "We use your location to detect when you're at the gym and record where gear was last seen if it disconnects.",
            detail: "This permission is required to continue.",
            buttonTitle: "Share Location",
            isRequired: true,
            action: { viewModel.requestLocationWhenInUse() }
        )
    }

    // MARK: - Background Location Step

    private var backgroundLocationStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.gsEmerald.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "location.fill.viewfinder")
                    .font(.system(size: 48))
                    .foregroundColor(.gsEmerald)
            }
            .padding(.bottom, 32)

            Text("Background Location")
                .font(.title2.bold())
                .foregroundColor(.gsText)
                .padding(.bottom, 12)

            Text("For automatic gym detection and background monitoring, GearSnitch needs 'Always' location access. You can change this anytime in Settings.")
                .font(.body)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            if !viewModel.locationAlwaysGranted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.gsWarning)
                    Text("Without this, gear monitoring only works while the app is open.")
                        .font(.caption)
                        .foregroundColor(.gsWarning)
                }
                .padding(.top, 16)
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: { viewModel.requestLocationAlways() }) {
                    Text("Allow Always")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.gsEmerald)
                        .cornerRadius(14)
                }

                Button(action: { viewModel.skipStep() }) {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Notifications Step

    private var notificationsStep: some View {
        permissionStep(
            icon: "bell.badge.fill",
            iconColor: .gsWarning,
            title: "Push Notifications",
            description: "Get instant alerts when a device disconnects, leaves range, or when your gear needs attention.",
            detail: nil,
            buttonTitle: "Enable Notifications",
            isRequired: false,
            action: { viewModel.requestNotifications() },
            onSkip: { viewModel.skipStep() }
        )
    }

    // MARK: - HealthKit Step

    private var healthKitStep: some View {
        permissionStep(
            icon: "heart.text.square",
            iconColor: .red,
            title: "Apple Health",
            description: "Optionally sync your health metrics like weight, steps, and heart rate for a complete fitness picture.",
            detail: nil,
            buttonTitle: "Connect Health",
            isRequired: false,
            action: { viewModel.requestHealthKitAuthorization() },
            onSkip: { viewModel.skipStep() }
        )
    }

    // MARK: - Add Gym Step (Full Screen Map)

    private var addGymStep: some View {
        OnboardingAddGymView(
            onGymAdded: { name, lat, lng in
                viewModel.gymAdded(name: name, latitude: lat, longitude: lng)
            }
        )
    }

    // MARK: - Pair Device Step

    private var pairDeviceStep: some View {
        OnboardingPairDeviceView(
            bleManager: bleManager,
            onDevicePaired: { name in
                viewModel.devicePaired(name: name)
            }
        )
    }

    // MARK: - Completion Step

    private var completionStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.gsSuccess.opacity(0.2))
                    .frame(width: 140, height: 140)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.gsSuccess)
            }
            .padding(.bottom, 32)

            Text("Setup Complete!")
                .font(.title.bold())
                .foregroundColor(.gsText)
                .padding(.bottom, 12)

            Text("GearSnitch is ready to protect your gear. Head to the dashboard to start monitoring.")
                .font(.body)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                Task {
                    await viewModel.completeOnboarding()
                    onComplete()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isCompleting {
                        ProgressView()
                            .tint(.black)
                    }
                    Text("Go to Dashboard")
                        .font(.headline)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.gsEmerald)
                .cornerRadius(14)
            }
            .disabled(viewModel.isCompleting)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Reusable Permission Step

    private func permissionStep(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        detail: String?,
        buttonTitle: String,
        isRequired: Bool,
        action: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundColor(iconColor)
            }
            .padding(.bottom, 32)

            Text(title)
                .font(.title2.bold())
                .foregroundColor(.gsText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            Text(description)
                .font(.body)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.gsWarning)
                    .padding(.top, 8)
            }

            if let errorMessage = viewModel.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.gsDanger)
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }
                .padding(.top, 12)
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    viewModel.error = nil
                    action()
                }) {
                    Text(buttonTitle)
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.gsEmerald)
                        .cornerRadius(14)
                }

                if !isRequired, let skip = onSkip {
                    Button(action: skip) {
                        Text("Maybe Later")
                            .font(.subheadline)
                            .foregroundColor(.gsTextSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Onboarding Add Gym View (Full Screen Map)

struct OnboardingAddGymView: View {
    let onGymAdded: (String, Double, Double) -> Void

    @StateObject private var searchModel = GymSearchModel()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedResult: MKMapItem?
    @State private var gymName = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        ZStack(alignment: .top) {
            // Full screen map
            Map(position: $cameraPosition, selection: $selectedResult) {
                UserAnnotation()

                ForEach(searchModel.results, id: \.self) { item in
                    Marker(
                        item.name ?? "Gym",
                        systemImage: "building.2.fill",
                        coordinate: item.placemark.coordinate
                    )
                    .tint(Color.gsEmerald)
                    .tag(item)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .including([.fitnessCenter])))
            .ignoresSafeArea(edges: .bottom)

            // Search bar overlay
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if !searchModel.results.isEmpty && !searchModel.query.isEmpty {
                    searchResultsList
                }

                Spacer()

                // Selected gym confirmation / instructions
                if let selected = selectedResult, let name = selected.name {
                    selectedGymCard(name: name, coordinate: selected.placemark.coordinate)
                } else if selectedCoordinate != nil && !gymName.isEmpty {
                    selectedGymCard(name: gymName, coordinate: CLLocationCoordinate2D(
                        latitude: selectedCoordinate!.latitude,
                        longitude: selectedCoordinate!.longitude
                    ))
                } else {
                    instructionCard
                }
            }
        }
        .onChange(of: selectedResult) { _, newValue in
            if let item = newValue {
                gymName = item.name ?? ""
                selectedCoordinate = item.placemark.coordinate
                cameraPosition = .region(MKCoordinateRegion(
                    center: item.placemark.coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                ))
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gsTextSecondary)

            TextField("Search gyms, fitness centers...", text: $searchModel.query)
                .font(.subheadline)
                .foregroundColor(.gsText)
                .autocorrectionDisabled()
                .onSubmit {
                    searchModel.search()
                }

            if !searchModel.query.isEmpty {
                Button {
                    searchModel.query = ""
                    searchModel.results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gsTextSecondary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchModel.results, id: \.self) { item in
                    Button {
                        selectedResult = item
                        gymName = item.name ?? ""
                        selectedCoordinate = item.placemark.coordinate
                        searchModel.query = ""
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "building.2")
                                .foregroundColor(.gsEmerald)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.gsText)
                                    .lineLimit(1)

                                if let address = item.placemark.title {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundColor(.gsTextSecondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    if item != searchModel.results.last {
                        Divider()
                            .background(Color.gsBorder)
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .frame(maxHeight: 240)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Selected Gym Card

    private func selectedGymCard(name: String, coordinate: CLLocationCoordinate2D) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "building.2.fill")
                    .font(.title3)
                    .foregroundColor(.gsEmerald)
                    .frame(width: 44, height: 44)
                    .background(Color.gsEmerald.opacity(0.15))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)
                        .lineLimit(1)

                    Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.gsEmerald)
                    .font(.title3)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.gsDanger)
            }

            Button {
                Task { await saveGym(name: name, coordinate: coordinate) }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView().tint(.black)
                    }
                    Text("This is my gym")
                        .font(.headline)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.gsEmerald)
                .cornerRadius(14)
            }
            .disabled(isSaving)
        }
        .padding(16)
        .background(Color.gsSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gsEmerald.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    // MARK: - Instruction Card

    private var instructionCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "building.2.fill")
                .font(.title2)
                .foregroundColor(.gsEmerald)

            Text("Add Your Gym")
                .font(.headline)
                .foregroundColor(.gsText)

            Text("Search for your gym or tap the map to select a location.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.gsSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    // MARK: - Save

    private func saveGym(name: String, coordinate: CLLocationCoordinate2D) async {
        isSaving = true
        error = nil

        let body = CreateGymBody(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: 200,
            isDefault: true
        )

        do {
            let _: GymDTO = try await APIClient.shared.request(APIEndpoint.Gyms.create(body))
            onGymAdded(name, coordinate.latitude, coordinate.longitude)
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Gym Search Model

@MainActor
final class GymSearchModel: ObservableObject {
    @Published var query = "" {
        didSet { search() }
    }
    @Published var results: [MKMapItem] = []

    private var searchTask: Task<Void, Never>?

    func search() {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

            guard !Task.isCancelled else { return }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])

            do {
                let search = MKLocalSearch(request: request)
                let response = try await search.start()
                if !Task.isCancelled {
                    results = response.mapItems
                }
            } catch {
                if !Task.isCancelled {
                    results = []
                }
            }
        }
    }
}

// MARK: - Onboarding Pair Device View

struct OnboardingPairDeviceView: View {
    @ObservedObject var bleManager: BLEManager
    let onDevicePaired: (String) -> Void

    @State private var isPairing = false
    @State private var pairingDevice: BLEDevice?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Pair Your Device")
                    .font(.title2.bold())
                    .foregroundColor(.gsText)

                Text("Make sure your Bluetooth tracker is powered on and nearby.")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Scanning indicator
            if bleManager.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.gsEmerald)
                    Text("Scanning for devices...")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
                .padding(.bottom, 12)
            }

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.gsDanger)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            // Device list
            if bleManager.discoveredDevices.isEmpty && bleManager.isScanning {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 48))
                        .foregroundColor(.gsTextSecondary)
                        .symbolEffect(.variableColor.iterative, options: .repeating)

                    Text("Looking for nearby devices...")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(bleManager.discoveredDevices) { device in
                            deviceCard(device)
                        }

                        ForEach(bleManager.connectedDevices) { device in
                            connectedDeviceCard(device)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }

            // Bottom controls
            VStack(spacing: 12) {
                if !bleManager.isScanning {
                    Button {
                        bleManager.startScanning()
                    } label: {
                        Label("Start Scanning", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.gsEmerald)
                            .cornerRadius(14)
                    }
                } else {
                    Button {
                        bleManager.stopScanning()
                    } label: {
                        Text("Stop Scanning")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gsEmerald)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            if bleManager.bluetoothState == .poweredOn {
                bleManager.startScanning()
            }
        }
        .onDisappear {
            bleManager.stopScanning()
        }
    }

    // MARK: - Device Card

    private func deviceCard(_ device: BLEDevice) -> some View {
        Button {
            pairDevice(device)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gsEmerald)
                    .frame(width: 44, height: 44)
                    .background(Color.gsEmerald.opacity(0.12))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsText)

                    HStack(spacing: 8) {
                        Text("Signal: \(device.rssi) dBm")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)

                        signalBars(rssi: device.rssi)
                    }
                }

                Spacer()

                if isPairing && pairingDevice?.identifier == device.identifier {
                    ProgressView()
                        .tint(.gsEmerald)
                } else {
                    Text("Pair")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gsEmerald)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.gsEmerald.opacity(0.12))
                        .cornerRadius(8)
                }
            }
            .cardStyle()
        }
        .disabled(isPairing)
    }

    private func connectedDeviceCard(_ device: BLEDevice) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.gsSuccess)
                .frame(width: 44, height: 44)
                .background(Color.gsSuccess.opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                Text("Connected")
                    .font(.caption)
                    .foregroundColor(.gsSuccess)
            }

            Spacer()
        }
        .cardStyle()
    }

    private func signalBars(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barActive(index: index, rssi: rssi) ? Color.gsEmerald : Color.gsBorder)
                    .frame(width: 3, height: CGFloat(4 + index * 3))
            }
        }
    }

    private func barActive(index: Int, rssi: Int) -> Bool {
        let thresholds = [-90, -70, -55, -40]
        return rssi >= thresholds[index]
    }

    // MARK: - Pair

    private func pairDevice(_ device: BLEDevice) {
        isPairing = true
        pairingDevice = device
        error = nil

        bleManager.connect(to: device)

        // Register the device on the backend
        Task {
            let body = CreateDeviceBody(
                name: device.name,
                bluetoothIdentifier: device.identifier.uuidString,
                type: "tracker"
            )

            do {
                let _: EmptyData = try await APIClient.shared.request(APIEndpoint.Devices.create(body))
                isPairing = false
                onDevicePaired(device.name)
            } catch {
                isPairing = false
                self.error = "Failed to register device: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        OnboardingView(onComplete: {})
            .environmentObject(BLEManager())
    }
    .preferredColorScheme(.dark)
}
