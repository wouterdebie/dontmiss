import Combine
import Foundation
import MapKit

public enum EventLocation {
    public static func searchQuery(for location: String) -> String? {
        let query = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = query.lowercased()
        let virtualLocations: Set<String> = [
            "online", "virtual", "remote", "tbd", "tba", "n/a", "none",
            "zoom", "google meet", "microsoft teams", "teams", "webex",
            "online meeting", "virtual meeting", "phone", "phone call", "video call"
        ]
        guard !query.isEmpty, !virtualLocations.contains(normalized),
              normalized.range(of: #"://|www\.|meet\.google\.com|zoom\.us|teams\.microsoft\.com"#,
                               options: .regularExpression) == nil,
              normalized.range(of: #"^(?:(?:conference|meeting) room|room)\s+[\p{L}\p{N} -]+$"#,
                               options: .regularExpression) == nil else { return nil }
        return query
    }

    public static func specificPlaces(in items: [MKMapItem]) -> [MKMapItem] {
        items.filter { item in
            let placemark = item.placemark
            let hasStreetAddress = !(placemark.thoroughfare ?? "").isEmpty
                && !(placemark.subThoroughfare ?? "").isEmpty
            return !item.isCurrentLocation
                && CLLocationCoordinate2DIsValid(placemark.coordinate)
                && (hasStreetAddress || item.pointOfInterestCategory != nil)
        }
    }
}

@MainActor
public final class EventLocationLookup: ObservableObject {
    public enum State {
        case idle
        case loading
        case resolved(MKMapItem)
        case unavailable(String)
    }

    @Published public private(set) var state: State = .idle
    private let search: @MainActor (String) async throws -> [MKMapItem]

    public convenience init() {
        self.init { query in
            try await AppleLocationSearch(query: query).results()
        }
    }

    @MainActor
    private final class AppleLocationSearch {
        private let search: MKLocalSearch

        init(query: String) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            search = MKLocalSearch(request: request)
        }

        func results() async throws -> [MKMapItem] {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await search.start().mapItems
            } onCancel: {
                Task { @MainActor in self.search.cancel() }
            }
        }
    }

    init(search: @escaping @MainActor (String) async throws -> [MKMapItem]) {
        self.search = search
    }

    public func load(_ location: String) async {
        guard let query = EventLocation.searchQuery(for: location) else {
            state = .idle
            return
        }
        state = .loading
        do {
            let places = EventLocation.specificPlaces(in: try await search(query))
            try Task.checkCancellation()
            if places.count == 1, let place = places.first {
                state = .resolved(place)
            } else {
                state = .unavailable(places.isEmpty
                    ? "No specific address or venue was found for this location."
                    : "This location matches multiple places. Add a more specific address in your calendar.")
            }
        } catch {
            guard !Task.isCancelled else { return }
            state = .unavailable("Could not load the map: \(error.localizedDescription)")
        }
    }
}
