import SwiftUI

/// Per-component editor: surface current usage band, allow the user to log
/// usage, edit the lifetime limit, and explicitly retire the component.
///
/// When `logUsage` returns `crossedWarning` or `crossedRetirement` true, we
/// show a banner so the user immediately sees the milestone (the worker
/// also fires an APNs push, but the banner is in-flow confirmation).
struct GearDetailView: View {
    @StateObject private var viewModel: GearDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showRetireConfirm = false
    @State private var logAmount: String = ""

    init(componentId: String) {
        _viewModel = StateObject(wrappedValue: GearDetailViewModel(componentId: componentId))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.component == nil {
                LoadingView(message: "Loading...")
            } else if let component = viewModel.component {
                content(component)
            } else if let error = viewModel.error {
                ErrorView(message: error) {
                    Task { await viewModel.load() }
                }
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle(viewModel.component?.name ?? "Gear")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Retire Gear", isPresented: $showRetireConfirm) {
            Button("Retire", role: .destructive) {
                Task { await viewModel.retire(); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mark this gear as retired? It will stop tracking new usage.")
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func content(_ component: GearComponentDTO) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard(component)
                if viewModel.lastCrossedRetirement {
                    banner(
                        text: "This gear hit its retirement limit and was auto-retired.",
                        color: .gsDanger,
                        icon: "exclamationmark.octagon.fill",
                    )
                } else if viewModel.lastCrossedWarning {
                    banner(
                        text: "Heads up — this gear is approaching its retirement limit.",
                        color: .gsWarning,
                        icon: "exclamationmark.triangle.fill",
                    )
                }
                if !component.isRetired {
                    logUsageCard(component)
                }
                actionsCard(component)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func summaryCard(_ component: GearComponentDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(component.name)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.gsText)
                Spacer()
                Text(component.kind.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gsTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gsTextSecondary.opacity(0.15))
                    .cornerRadius(6)
            }
            ProgressView(value: min(1.0, component.usagePct))
                .tint(bandColor(component.usageBand))
            HStack {
                Text("\(formatValue(component.currentValue))/\(formatValue(component.lifeLimit)) \(component.unit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)
                Spacer()
                Text("\(Int((component.usagePct * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(bandColor(component.usageBand))
            }
            if let retiredAt = component.retiredAt {
                Text("Retired \(retiredAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .cardStyle()
    }

    private func banner(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(.gsText)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.12))
        .cornerRadius(10)
    }

    private func logUsageCard(_ component: GearComponentDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Log Usage", systemImage: "plus.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            HStack {
                TextField("Amount in \(component.unit)", text: $logAmount)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Button {
                    guard let amount = Double(logAmount), amount > 0 else { return }
                    Task {
                        await viewModel.logUsage(amount: amount)
                        logAmount = ""
                    }
                } label: {
                    Text("Log")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.gsEmerald)
                        .cornerRadius(8)
                }
                .disabled(Double(logAmount) == nil || viewModel.isUpdating)
            }
        }
        .cardStyle()
    }

    private func actionsCard(_ component: GearComponentDTO) -> some View {
        VStack(spacing: 10) {
            if !component.isRetired {
                Button {
                    showRetireConfirm = true
                } label: {
                    Label("Retire Gear", systemImage: "archivebox")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsDanger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.gsDanger.opacity(0.1))
                        .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class GearDetailViewModel: ObservableObject {
    @Published var component: GearComponentDTO?
    @Published var isLoading = false
    @Published var isUpdating = false
    @Published var error: String?
    @Published var lastCrossedWarning = false
    @Published var lastCrossedRetirement = false

    private let componentId: String
    private let service: GearService

    init(componentId: String, service: GearService = .shared) {
        self.componentId = componentId
        self.service = service
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            let all = try await service.list()
            component = all.first(where: { $0.id == componentId })
            if component == nil {
                error = "Gear not found"
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func logUsage(amount: Double) async {
        isUpdating = true
        do {
            let response = try await service.logUsage(id: componentId, amount: amount)
            component = response.component
            lastCrossedWarning = response.crossedWarning
            lastCrossedRetirement = response.crossedRetirement
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isUpdating = false
    }

    func retire() async {
        isUpdating = true
        do {
            component = try await service.retire(id: componentId)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isUpdating = false
    }
}

#Preview {
    NavigationStack {
        GearDetailView(componentId: "preview-id")
    }
    .preferredColorScheme(.dark)
}
