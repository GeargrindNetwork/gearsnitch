import SwiftUI

/// Backlog item #39 — achievements grid.
///
/// Renders every catalog badge: earned ones in emerald, locked ones greyed
/// out with a progress subtitle. The server is the source of truth for the
/// catalog so this view never hard-codes badge metadata beyond the SF
/// Symbol fallback.
struct AchievementsView: View {
    @StateObject private var viewModel = AchievementsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerStats
                if !viewModel.earned.isEmpty {
                    section(title: "EARNED", badges: viewModel.earned.map(BadgeTile.earned))
                }
                if !viewModel.locked.isEmpty {
                    section(title: "IN PROGRESS", badges: viewModel.locked.map(BadgeTile.locked))
                }
                if viewModel.earned.isEmpty && viewModel.locked.isEmpty && !viewModel.isLoading {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if viewModel.isLoading && viewModel.earned.isEmpty && viewModel.locked.isEmpty {
                LoadingView(message: "Loading badges…")
            }
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load(forceRefresh: true)
        }
    }

    // MARK: - Header Stats

    private var headerStats: some View {
        HStack(spacing: 12) {
            statTile(
                icon: "rosette",
                label: "Earned",
                value: "\(viewModel.earned.count) / \(viewModel.earned.count + viewModel.locked.count)"
            )
            statTile(
                icon: "flame.fill",
                label: "Streak",
                value: "\(viewModel.currentStreakDays) day\(viewModel.currentStreakDays == 1 ? "" : "s")"
            )
        }
    }

    private func statTile(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.gsEmerald)
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.gsTextSecondary)
                    .tracking(1)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.gsSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }

    // MARK: - Section

    private func section(title: String, badges: [BadgeTile]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundColor(.gsTextSecondary)
                .tracking(1)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(badges) { tile in
                    badgeCell(tile)
                }
            }
        }
    }

    private func badgeCell(_ tile: BadgeTile) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(tile.isEarned ? Color.gsEmerald.opacity(0.15) : Color.gsSurfaceRaised)
                    .frame(width: 56, height: 56)
                Image(systemName: tile.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(tile.isEarned ? .gsEmerald : .gsTextSecondary.opacity(0.6))
            }

            Text(tile.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(tile.isEarned ? .gsText : .gsTextSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let subtitle = tile.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.gsSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
        .opacity(tile.isEarned ? 1.0 : 0.85)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rosette")
                .font(.system(size: 40))
                .foregroundColor(.gsTextSecondary.opacity(0.5))
            Text("No badges yet")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
            Text("Complete a workout, finish a run, or pair a device to earn your first badge.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.gsSurface)
        .cornerRadius(14)
    }
}

// MARK: - Tile View Model

private struct BadgeTile: Identifiable {
    let id: String
    let title: String
    let icon: String
    let subtitle: String?
    let isEarned: Bool

    static func earned(_ dto: EarnedAchievementDTO) -> BadgeTile {
        BadgeTile(
            id: dto.badgeId,
            title: dto.title,
            icon: dto.icon,
            subtitle: "Earned",
            isEarned: true
        )
    }

    static func locked(_ dto: LockedAchievementDTO) -> BadgeTile {
        BadgeTile(
            id: dto.badgeId,
            title: dto.title,
            icon: dto.icon,
            subtitle: dto.progress?.label,
            isEarned: false
        )
    }
}

// MARK: - View Model

@MainActor
final class AchievementsViewModel: ObservableObject {
    @Published private(set) var earned: [EarnedAchievementDTO] = []
    @Published private(set) var locked: [LockedAchievementDTO] = []
    @Published private(set) var currentStreakDays: Int = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private let service: AchievementService

    init(service: AchievementService = .shared) {
        self.service = service
    }

    func load(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await service.load(forceRefresh: forceRefresh)
            earned = response.earned
            locked = response.locked
            currentStreakDays = response.stats.currentStreakDays
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        AchievementsView()
    }
    .preferredColorScheme(.dark)
}
