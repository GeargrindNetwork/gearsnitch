import Foundation
import MapKit

// MARK: - Map Search Manager

/// Manages MKLocalSearchCompleter for real-time place suggestions
/// and MKLocalSearch for detailed place lookups.
@MainActor
final class MapSearchManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var searchText: String = "" {
        didSet { updateCompleterQuery() }
    }
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published var selectedPlace: MKMapItem?
    @Published private(set) var isSearching = false

    // MARK: - Private

    private let completer = MKLocalSearchCompleter()

    private static let gymCategories: [MKPointOfInterestCategory] = [
        .fitnessCenter
    ]

    // MARK: - Init

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest]
    }

    // MARK: - Public API

    /// Search for a specific completion to get full MKMapItem details.
    func search(for completion: MKLocalSearchCompletion) async {
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = [.pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            if let item = response.mapItems.first {
                selectedPlace = item
            }
        } catch {
            // Search failed silently — user can retry
        }
    }

    /// Search nearby for a text query within a given region.
    func searchNearby(query: String, region: MKCoordinateRegion) async {
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = [.pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            if let item = response.mapItems.first {
                selectedPlace = item
            }
        } catch {
            // Search failed silently
        }
    }

    /// Clear current search state.
    func clearSearch() {
        searchText = ""
        completions = []
        selectedPlace = nil
    }

    // MARK: - Private

    private func updateCompleterQuery() {
        if searchText.isEmpty {
            completions = []
        } else {
            completer.queryFragment = searchText
        }
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension MapSearchManager: MKLocalSearchCompleterDelegate {

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor [weak self] in
            self?.completions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            self?.completions = []
        }
    }
}
