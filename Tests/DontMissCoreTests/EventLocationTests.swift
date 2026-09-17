import Contacts
import MapKit
import Testing
@testable import DontMissCore

private final class AddressPlacemark: MKPlacemark, @unchecked Sendable {
    override var thoroughfare: String? { "Main Street" }
    override var subThoroughfare: String? { "123" }
}

private final class AddressMapItem: MKMapItem {
    // MKMapItem reconstructs placemarks, losing structured fields in synthetic addresses.
    override var placemark: MKPlacemark {
        AddressPlacemark(coordinate: super.placemark.coordinate)
    }
}

@MainActor
struct EventLocationTests {
    private func address(latitude: Double = 37.78) -> MKMapItem {
        AddressMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -122.42)))
    }

    @Test(arguments: [
        "", " \n ", "Online", " VIRTUAL ", "Zoom", "Google Meet", "Microsoft Teams",
        "Phone call", "TBD", "https://example.com/call", "meet.google.com/abc-def-ghi",
        "Join at https://zoom.us/j/123", "Conference Room B", "Room 401"
    ])
    func skipsNonphysicalLocations(location: String) {
        #expect(EventLocation.searchQuery(for: location) == nil)
    }

    @Test(arguments: [
        "123 Main Street, San Francisco", "The Fillmore, San Francisco",
        "1 Infinite Loop, Cupertino", "10 Downing Street, London",
        "東京都千代田区丸の内1丁目"
    ])
    func preservesAddressesAndVenues(location: String) {
        #expect(EventLocation.searchQuery(for: " \n\(location) \n") == location)
    }

    @Test func rejectsBroadAndInvalidResults() {
        let city = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42),
            addressDictionary: [CNPostalAddressCityKey: "San Francisco"]))
        let invalid = address(latitude: 100)
        #expect(EventLocation.specificPlaces(in: [city, invalid]).isEmpty)
    }

    @Test func acceptsNumberedAddressesAndVenues() {
        let street = address()
        let venue = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42)))
        venue.name = "The Coffee Shop"
        venue.pointOfInterestCategory = .cafe
        #expect(EventLocation.specificPlaces(in: [street, venue]).count == 2)
    }

    @Test func resolvesOneSpecificPlace() async {
        let place = address()
        let lookup = EventLocationLookup { query in
            #expect(query == "123 Main Street, San Francisco")
            return [place]
        }
        await lookup.load(" 123 Main Street, San Francisco ")
        guard case .resolved(let result) = lookup.state else {
            Issue.record("Expected a resolved location")
            return
        }
        #expect(result === place)
    }

    @Test func skipsSearchForOnlineLocations() async {
        let lookup = EventLocationLookup { _ in
            Issue.record("Online locations must not be sent to Apple")
            return []
        }
        await lookup.load("Online")
        guard case .idle = lookup.state else {
            Issue.record("Expected no map for online locations")
            return
        }
    }

    @Test func explainsMissingAndAmbiguousResults() async {
        let missing = EventLocationLookup { _ in [] }
        await missing.load("Unknown address")
        guard case .unavailable(let missingMessage) = missing.state else {
            Issue.record("Expected an explanation for missing results")
            return
        }
        #expect(missingMessage.contains("No specific address"))

        let ambiguous = EventLocationLookup { _ in [address(), address(latitude: 38)] }
        await ambiguous.load("123 Main Street")
        guard case .unavailable(let ambiguousMessage) = ambiguous.state else {
            Issue.record("Expected an explanation for ambiguous results")
            return
        }
        #expect(ambiguousMessage.contains("multiple places"))
    }

    @Test func reportsSearchErrorsAndCanRetry() async {
        var attempts = 0
        let lookup = EventLocationLookup { _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return [address()]
        }
        await lookup.load("123 Main Street")
        guard case .unavailable(let message) = lookup.state else {
            Issue.record("Expected a visible search error")
            return
        }
        #expect(message.contains("Could not load the map:"))
        await lookup.load("123 Main Street")
        guard case .resolved = lookup.state else {
            Issue.record("Expected retry to resolve the location")
            return
        }
        #expect(attempts == 2)
    }

    @Test func cancelledLookupCannotPublishResults() async {
        let lookup = EventLocationLookup { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return [address()]
        }
        let task = Task { await lookup.load("123 Main Street") }
        await task.value
        guard case .loading = lookup.state else {
            Issue.record("A cancelled lookup must not publish a stale result or error")
            return
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DONTMISS_TEST_MAPS"] == "1"))
    func liveAppleMapsLookup() async {
        let lookup = EventLocationLookup()
        await lookup.load("1 Infinite Loop, Cupertino, CA 95014")
        guard case .resolved(let place) = lookup.state else {
            if case .unavailable(let message) = lookup.state {
                Issue.record("Live lookup failed: \(message)")
            } else {
                Issue.record("Live lookup did not finish")
            }
            return
        }
        let expected = CLLocation(latitude: 37.3317, longitude: -122.0307)
        let actual = CLLocation(latitude: place.placemark.coordinate.latitude,
                                longitude: place.placemark.coordinate.longitude)
        #expect(actual.distance(from: expected) < 2_000)
    }
}
