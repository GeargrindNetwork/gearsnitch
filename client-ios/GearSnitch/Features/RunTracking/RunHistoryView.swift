import SwiftUI
import MapKit

struct RunHistoryView: View {
    @StateObject private var viewModel = RunHistoryViewModel()
    @ObservedObject private var runManager = RunTrackingManager.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if viewModel.isLoading && viewModel.runs.isEmpty {
                    LoadingView(message: "Loading runs...")
                } else if viewModel.completedRuns.isEmpty {
                    emptyState
                } else {
                    runList
                }
            }

            // Moved from top-right to bottom-right to avoid overlapping
            // the shared TopNavBar profile/QR cluster (founder bug report).
            NavigationLink {
                ActiveRunView()
            } label: {
                Image(systemName: runManager.activeRun == nil ? "figure.run.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.gsEmerald)
                    .clipShape(Circle())
                    .shadow(radius: 6, y: 3)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
            .accessibilityIdentifier("runHistory.addRunFab")
            .accessibilityLabel("Start a new run")
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Runs")
        .navigationBarTitleDisplayMode(.large)
        // Delete-run alert (PR #96). Toolbar add-run was removed in PR #95 —
        // the "Add Run" action now lives in a bottom-right FAB (see the
        // accessibilityIdentifier "runHistory.addRunFab" above) so it stops
        // overlapping with the shared top-nav cluster.
        .alert(
            "Delete Run",
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.pendingDeletion = nil } }
            ),
            presenting: viewModel.pendingDeletion
        ) { run in
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteRun(run) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeletion = nil
            }
        } message: { run in
            Text("This will permanently remove the \(run.distanceString) run from \(run.startedAt.formatted(date: .abbreviated, time: .shortened)). This cannot be undone.")
        }
        .task {
            await viewModel.loadRuns()
        }
    }

    private var runList: some View {
        ScrollView {
            VStack(spacing: 16) {
                if runManager.activeRun != nil {
                    NavigationLink {
                        ActiveRunView()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "waveform.path.ecg.rectangle")
                                .font(.title3)
                                .foregroundColor(.gsEmerald)
                                .frame(width: 40, height: 40)
                                .background(Color.gsEmerald.opacity(0.12))
                                .cornerRadius(10)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Resume active run")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.gsText)
                                Text("A route is currently recording on this device.")
                                    .font(.caption)
                                    .foregroundColor(.gsTextSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.gsTextSecondary)
                        }
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                }

                if !viewModel.completedRuns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("History")
                            .font(.headline)
                            .foregroundColor(.gsText)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.completedRuns.enumerated()), id: \.element.id) { index, run in
                                if index > 0 {
                                    Divider().background(Color.gsBorder)
                                }
                                NavigationLink {
                                    RunDetailView(initialRun: run, viewModel: viewModel)
                                } label: {
                                    runRow(run)
                                }
                                .buttonStyle(.plain)
                                // Swipe-to-delete (PR #96) doesn't apply outside
                                // of `List`; in the card-refactored layout we
                                // trigger delete via context menu instead. The
                                // confirmation alert on the parent view is
                                // driven by `viewModel.pendingDeletion`.
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.pendingDeletion = run
                                    } label: {
                                        Label("Delete Run", systemImage: "trash.fill")
                                    }
                                }
                            }
                        }
                        .cardStyle(padding: 0)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.loadRuns()
        }
    }

    private func runRow(_ run: RunDTO) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundColor(.gsEmerald)
                .frame(width: 40, height: 40)
                .background(Color.gsEmerald.opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                HStack(spacing: 12) {
                    Label(run.distanceString, systemImage: "figure.walk.motion")
                    Label(run.durationString, systemImage: "clock")
                }
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

                Text(run.paceString)
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 48))
                .foregroundColor(.gsTextSecondary)

            Text("No Runs Yet")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text("Start a run to capture distance, pace, and route history.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            NavigationLink {
                ActiveRunView()
            } label: {
                Label("Start Run", systemImage: "play.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.gsEmerald)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RunDetailView: View {
    let initialRun: RunDTO
    @ObservedObject var viewModel: RunHistoryViewModel
    @State private var run: RunDTO
    @State private var isLoading = false
    @State private var error: String?

    init(initialRun: RunDTO, viewModel: RunHistoryViewModel) {
        self.initialRun = initialRun
        self.viewModel = viewModel
        _run = State(initialValue: initialRun)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    detailStat(title: "Distance", value: run.distanceString)
                    detailStat(title: "Duration", value: run.durationString)
                    detailStat(title: "Pace", value: run.paceString)
                }

                RunRouteMap(route: run.route)
                    .frame(height: 300)
                    .cardStyle(padding: 0)

                VStack(spacing: 0) {
                    detailRow(label: "Started", value: run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Divider().background(Color.gsBorder)
                    detailRow(label: "Finished", value: run.endedAt?.formatted(date: .abbreviated, time: .shortened) ?? "In Progress")
                    Divider().background(Color.gsBorder)
                    detailRow(label: "Route Points", value: "\(run.route.pointCount)")
                }
                .cardStyle(padding: 0)

                if let notes = run.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.gsTextSecondary)
                        Text(notes)
                            .font(.subheadline)
                            .foregroundColor(.gsText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Run Detail")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                LoadingView(message: "Loading run detail...")
            } else if let error {
                ErrorView(message: error)
            }
        }
        .task {
            guard run.route.points == nil else { return }
            isLoading = true
            do {
                run = try await viewModel.loadDetail(id: initialRun.id)
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func detailStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.gsTextSecondary)
            Text(value)
                .font(.headline)
                .foregroundColor(.gsText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func detailRow(label: String, value: String) -> some View {
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
}

struct RunRouteMap: View {
    let route: RunRoutePayload

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var coordinates: [CLLocationCoordinate2D] {
        route.points?.map(\.coordinate) ?? []
    }

    var body: some View {
        Group {
            if coordinates.count >= 2 {
                Map(position: $cameraPosition) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.gsEmerald, lineWidth: 5)

                    if let start = coordinates.first {
                        Annotation("Start", coordinate: start) {
                            marker(color: .gsSuccess, symbol: "flag.fill")
                        }
                    }

                    if let end = coordinates.last {
                        Annotation("Finish", coordinate: end) {
                            marker(color: .gsDanger, symbol: "flag.checkered")
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onAppear {
                    cameraPosition = .rect(mapRect(for: coordinates))
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.title2)
                        .foregroundColor(.gsTextSecondary)
                    Text("Route geometry is not available for this run.")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gsSurface)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func marker(color: Color, symbol: String) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 34, height: 34)
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func mapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let rect = coordinates
            .map { MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 1, height: 1)) }
            .reduce(MKMapRect.null) { partial, next in
                partial.union(next)
            }

        return rect.insetBy(dx: -rect.size.width * 0.35, dy: -rect.size.height * 0.35)
    }
}

#Preview {
    NavigationStack {
        RunHistoryView()
    }
    .preferredColorScheme(.dark)
}
