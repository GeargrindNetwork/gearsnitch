import SwiftUI
import PhotosUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Avatar + name
                profileHeader

                // Health info card
                healthInfoCard

                // Blood type dietary recommendations
                if viewModel.bloodTypeRecommendation != nil {
                    dietaryRecommendationsCard
                }

                // Import from Apple Health
                healthImportButton

                // Devices section (moved from dashboard)
                devicesSectionView

                // Subscription card
                subscriptionCard

                // Purchases / Order History
                purchasesSection

                // Menu sections
                accountSection
                dataSection
                dangerSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .alert("Delete Account", isPresented: $viewModel.showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all data. This cannot be undone.")
        }
        .sheet(isPresented: $viewModel.showEditProfile) {
            editProfileSheet
        }
        .photosPicker(
            isPresented: $viewModel.showPhotoPicker,
            selection: $viewModel.selectedPhoto,
            matching: .images,
            photoLibrary: .shared()
        )
        .overlay {
            if viewModel.isLoading && viewModel.profile == nil {
                LoadingView(message: "Loading profile...")
            }
        }
        .task {
            await viewModel.loadProfile()
            // Auto-import Apple Health data on profile load
            if !viewModel.isImportingHealth {
                await viewModel.importFromHealthKit()
            }
        }
        .onChange(of: viewModel.selectedPhoto) { _, newValue in
            if newValue != nil {
                Task { await viewModel.loadSelectedPhoto() }
            }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Avatar with photo
            ZStack {
                if let image = viewModel.profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gsEmerald.opacity(0.2))
                        .frame(width: 80, height: 80)

                    Text(String(viewModel.displayName.prefix(1)).uppercased())
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.gsEmerald)
                }

                // Camera overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.gsEmerald)
                            .background(Circle().fill(Color.gsBackground).frame(width: 20, height: 20))
                    }
                }
                .frame(width: 80, height: 80)
                .onTapGesture {
                    guard !viewModel.isUpdatingAvatar else { return }
                    viewModel.showPhotoPicker = true
                }

                if viewModel.isUpdatingAvatar {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 80, height: 80)

                    ProgressView()
                        .tint(.white)
                }
            }

            Text(viewModel.displayName)
                .font(.title3.weight(.bold))
                .foregroundColor(.gsText)

            Text(viewModel.email)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)

            // Linked accounts
            if let linked = viewModel.profile?.linkedAccounts, !linked.isEmpty {
                HStack(spacing: 8) {
                    ForEach(linked, id: \.self) { account in
                        Label(account.capitalized, systemImage: accountIcon(account))
                            .font(.caption2)
                            .foregroundColor(.gsTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gsSurfaceRaised)
                            .cornerRadius(6)
                    }
                }
            }

            Button {
                viewModel.showEditProfile = true
            } label: {
                Text("Edit Profile")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.gsEmerald)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.gsEmerald.opacity(0.12))
                    .cornerRadius(8)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.showPhotoPicker = true
                } label: {
                    Text(viewModel.isUpdatingAvatar ? "Updating..." : "Change Photo")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.gsSurfaceRaised)
                        .cornerRadius(8)
                }
                .disabled(viewModel.isUpdatingAvatar)

                if viewModel.profileImage != nil || viewModel.profile?.avatarURL?.isEmpty == false {
                    Button(role: .destructive) {
                        Task { await viewModel.removeAvatar() }
                    } label: {
                        Text("Remove Photo")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    .disabled(viewModel.isUpdatingAvatar)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func accountIcon(_ account: String) -> String {
        switch account.lowercased() {
        case "apple": return "apple.logo"
        case "google": return "g.circle"
        default: return "link"
        }
    }

    // MARK: - Health Info Card

    private var healthInfoCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HEALTH PROFILE")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.gsTextSecondary)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Grid of health data
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                healthTile(
                    icon: "calendar",
                    label: "Date of Birth",
                    value: viewModel.dateOfBirthDisplay
                )
                healthTile(
                    icon: "ruler",
                    label: "Height",
                    value: viewModel.heightDisplay
                )
                healthTile(
                    icon: "scalemass",
                    label: "Weight",
                    value: viewModel.weightDisplay
                )
                healthTile(
                    icon: "number",
                    label: "BMI",
                    value: viewModel.bmiDisplay
                )
                healthTile(
                    icon: "drop.fill",
                    label: "Blood Type",
                    value: viewModel.bloodTypeDisplay
                )
                healthTile(
                    icon: "person.fill",
                    label: "Biological Sex",
                    value: viewModel.biologicalSexDisplay
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(Color.gsSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }

    private func healthTile(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(.gsEmerald)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary)
            }

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gsSurfaceRaised)
        .cornerRadius(8)
    }

    // MARK: - Dietary Recommendations

    private var dietaryRecommendationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.caption)
                    .foregroundColor(.gsEmerald)

                Text("DIETARY RECOMMENDATIONS")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.gsTextSecondary)
                    .tracking(1)
            }

            if let recommendation = viewModel.bloodTypeRecommendation {
                Text("Based on Blood Type \(viewModel.bloodTypeDisplay)")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)

                Text(recommendation)
                    .font(.subheadline)
                    .foregroundColor(.gsText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    // MARK: - Health Import

    private var healthImportButton: some View {
        Button {
            Task { await viewModel.importFromHealthKit() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.body)
                    .foregroundColor(.gsDanger)

                Text("Import from Apple Health")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                Spacer()

                if viewModel.isImportingHealth {
                    ProgressView()
                        .tint(.gsTextSecondary)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.body)
                        .foregroundColor(.gsEmerald)
                }
            }
            .cardStyle()
        }
        .disabled(viewModel.isImportingHealth)
    }

    // MARK: - Devices Section

    private var devicesSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Devices")
                    .font(.headline)
                    .foregroundColor(.gsText)
                Spacer()
                NavigationLink {
                    DeviceListView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.gsEmerald)
                }
            }

            if let profile = viewModel.profile {
                let devices = profile.devices ?? []
                if devices.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.title2)
                            .foregroundColor(.gsTextSecondary)

                        Text("No devices paired yet")
                            .font(.subheadline)
                            .foregroundColor(.gsTextSecondary)

                        Spacer()
                    }
                    .cardStyle()
                } else {
                    ForEach(devices.prefix(3)) { device in
                        NavigationLink {
                            DeviceDetailView(deviceId: device._id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: deviceIconName(device.type))
                                    .font(.title3)
                                    .foregroundColor(deviceStatusColor(device.status ?? "registered"))
                                    .frame(width: 40, height: 40)
                                    .background(deviceStatusColor(device.status ?? "registered").opacity(0.12))
                                    .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(device.nickname ?? device.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.gsText)
                                        if device.isFavorite ?? false {
                                            Image(systemName: "pin.fill")
                                                .font(.caption2)
                                                .foregroundColor(.gsWarning)
                                        }
                                    }
                                    Text(device.status?.capitalized ?? "Registered")
                                        .font(.caption)
                                        .foregroundColor(.gsTextSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gsTextSecondary)
                            }
                            .cardStyle()
                        }
                    }
                }
            }
        }
    }

    private func deviceIconName(_ type: String) -> String {
        switch type {
        case "earbuds": return "airpodspro"
        case "watch": return "applewatch"
        case "tracker": return "sensor.tag.radiowaves.forward"
        case "belt": return "figure.strengthtraining.traditional"
        case "bag": return "bag"
        default: return "sensor.tag.radiowaves.forward"
        }
    }

    private func deviceStatusColor(_ status: String) -> Color {
        switch status {
        case "connected", "monitoring", "reconnected", "active": return .gsSuccess
        case "lost": return .gsDanger
        case "disconnected", "inactive": return .gsWarning
        default: return .gsTextSecondary
        }
    }

    // MARK: - Subscription

    private var subscriptionCard: some View {
        NavigationLink {
            SubscriptionStatusView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundColor(.gsWarning)
                    .frame(width: 44, height: 44)
                    .background(Color.gsWarning.opacity(0.12))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                    Text(viewModel.subscriptionTier.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            .cardStyle()
        }
    }

    // MARK: - Purchases

    private var purchasesSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                OrderHistoryView()
            } label: {
                menuRow(icon: "bag", label: "Purchases", detail: viewModel.orderCountDisplay, color: .gsCyan)
            }
        }
        .cardStyle(padding: 0)
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(spacing: 0) {
            if let code = viewModel.profile?.referralCode {
                NavigationLink {
                    ReferralView()
                } label: {
                    menuRow(icon: "gift", label: "Referral Code", detail: code, color: .gsEmerald)
                }
                Divider().background(Color.gsBorder)
            }

            NavigationLink {
                EmergencyContactsView()
            } label: {
                menuRow(icon: "phone.arrow.up.right", label: "Emergency Contacts", color: .gsDanger)
            }

            Divider().background(Color.gsBorder)

            NavigationLink {
                SettingsView()
            } label: {
                menuRow(icon: "gearshape", label: "Settings", color: .gsTextSecondary)
            }
        }
        .cardStyle(padding: 0)
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(spacing: 0) {
            Button {
                Task { await viewModel.requestDataExport() }
            } label: {
                menuRow(icon: "arrow.down.doc", label: "Export My Data", color: .gsCyan)
            }
        }
        .cardStyle(padding: 0)
    }

    // MARK: - Danger

    private var dangerSection: some View {
        VStack(spacing: 0) {
            Button {
                viewModel.showDeleteConfirm = true
            } label: {
                menuRow(icon: "trash", label: "Delete Account", color: .gsDanger)
            }
        }
        .cardStyle(padding: 0)
    }

    // MARK: - Menu Row

    private func menuRow(icon: String, label: String, detail: String? = nil, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 28)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsText)

            Spacer()

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Edit Profile Sheet

    private var editProfileSheet: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    TextField("First Name", text: $viewModel.editFirstName)
                        .foregroundColor(.gsText)
                    TextField("Last Name", text: $viewModel.editLastName)
                        .foregroundColor(.gsText)
                    DatePicker(
                        "Date of Birth",
                        selection: $viewModel.editDateOfBirth,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }

                Section("Body Metrics") {
                    HStack {
                        Text("Height (in)")
                        Spacer()
                        TextField("0", value: $viewModel.editHeightInches, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Weight (lbs)")
                        Spacer()
                        TextField("0", value: $viewModel.editWeightLbs, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.gsBackground.ignoresSafeArea())
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.showEditProfile = false
                    }
                    .foregroundColor(.gsTextSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            await viewModel.saveProfileEdits()
                            viewModel.showEditProfile = false
                        }
                    }
                    .foregroundColor(.gsEmerald)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .preferredColorScheme(.dark)
}
