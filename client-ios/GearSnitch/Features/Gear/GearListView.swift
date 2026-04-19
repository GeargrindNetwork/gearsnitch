import SwiftUI

/// Lists the user's tracked gear components, color-coded by usage band:
/// green < 70%, yellow 70-85%, orange 85-100%, red ≥ 100%.
struct GearListView: View {
    @StateObject private var viewModel = GearListViewModel()
    @State private var showCreateSheet = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.components.isEmpty {
                LoadingView(message: "Loading gear...")
            } else if let error = viewModel.error, viewModel.components.isEmpty {
                ErrorView(message: error) {
                    Task { await viewModel.load() }
                }
            } else if viewModel.components.isEmpty {
                emptyState
            } else {
                gearList
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Gear")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.gsEmerald)
                }
            }
        }
        .sheet(isPresented: $showCreateSheet, onDismiss: {
            Task { await viewModel.load() }
        }) {
            GearCreateSheet()
        }
        .task {
            await viewModel.load()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 48))
                .foregroundColor(.gsTextSecondary)
            Text("No gear tracked yet")
                .font(.headline)
                .foregroundColor(.gsText)
            Text("Track your shoes, chains, and tires so we can ping you before they wear out.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showCreateSheet = true
            } label: {
                Label("Add Gear", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.gsEmerald)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gearList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.components) { component in
                    NavigationLink {
                        GearDetailView(componentId: component.id)
                    } label: {
                        GearRowView(component: component)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await viewModel.load()
        }
    }
}

// MARK: - Row

struct GearRowView: View {
    let component: GearComponentDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: component.kind))
                .font(.title2)
                .foregroundColor(bandColor(component.usageBand))
                .frame(width: 36, height: 36)
                .background(bandColor(component.usageBand).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(component.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)
                        .lineLimit(1)
                    Spacer()
                    if component.isRetired {
                        Text("Retired")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.gsTextSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gsTextSecondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                Text(usageLabel)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)

                ProgressView(value: min(1.0, component.usagePct))
                    .tint(bandColor(component.usageBand))
            }
        }
        .padding(12)
        .background(Color.gsSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }

    private var usageLabel: String {
        let pct = Int((component.usagePct * 100).rounded())
        return "\(formatValue(component.currentValue))/\(formatValue(component.lifeLimit)) \(component.unit) (\(pct)%)"
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case "shoe": return "shoeprints.fill"
        case "chain": return "link"
        case "tire": return "circle.dashed"
        case "cassette": return "gearshape.fill"
        case "helmet": return "shield.lefthalf.filled"
        case "battery": return "battery.50"
        default: return "wrench.and.screwdriver.fill"
        }
    }
}

func bandColor(_ band: GearUsageBand) -> Color {
    switch band {
    case .healthy: return .gsSuccess
    case .caution: return .gsWarning
    case .warning: return .orange
    case .retired: return .gsDanger
    }
}

func formatValue(_ value: Double) -> String {
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        return String(Int(value))
    }
    return String(format: "%.1f", value)
}

// MARK: - View Model

@MainActor
final class GearListViewModel: ObservableObject {
    @Published var components: [GearComponentDTO] = []
    @Published var isLoading = false
    @Published var error: String?

    private let service: GearService

    init(service: GearService = .shared) {
        self.service = service
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            components = try await service.list()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Create Sheet

struct GearCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = "shoe"
    @State private var unit = "miles"
    @State private var lifeLimit: String = "400"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let kinds = ["shoe", "chain", "tire", "cassette", "helmet", "battery", "other"]
    private let units = ["miles", "km", "hours", "sessions"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name (e.g. Hoka Bondi 8)", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(kinds, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Unit", selection: $unit) {
                        ForEach(units, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Lifetime Limit") {
                    TextField("Limit", text: $lifeLimit)
                        .keyboardType(.decimalPad)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.gsDanger)
                    }
                }
            }
            .navigationTitle("Add Gear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let limit = Double(lifeLimit), limit > 0 else {
            errorMessage = "Limit must be a positive number"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            _ = try await GearService.shared.create(CreateGearBody(
                name: name.trimmingCharacters(in: .whitespaces),
                kind: kind,
                unit: unit,
                lifeLimit: limit,
                warningThreshold: nil,
                currentValue: nil,
                deviceId: nil,
            ))
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSaving = false
    }
}

#Preview {
    NavigationStack {
        GearListView()
    }
    .preferredColorScheme(.dark)
}
